"""Regression tree: labeled ball size from its vertical image position (perspective), grouped CV vs the mean.

Usage (repo root):
    ml/.venv/bin/python ml/trees/size_regression_tree.py                      # Sami's game10 hand labels
    ml/.venv/bin/python ml/trees/size_regression_tree.py --yolo-dir data/spark/test_r1 --ball-class 1

x = ball centre y / image height, target = ball box height / image height (hand
labels: 2r / H). sklearn DecisionTreeRegressor (squared error), ccp_alpha chosen
by an inner grouped CV, scored by an outer grouped CV (groups as in
fp_filter_tree.py: source video, or blocks of frame indices) against a
DummyRegressor that always predicts the training mean. No detector involved.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from fp_filter_tree import ROOT, load_hand_labels, load_yolo_dir  # noqa: E402


def fit_tree(X, y, g, folds: int, seed: int):
    from sklearn.model_selection import GridSearchCV, GroupKFold
    from sklearn.tree import DecisionTreeRegressor
    alphas = DecisionTreeRegressor(random_state=seed, min_samples_leaf=3).cost_complexity_pruning_path(X, y).ccp_alphas
    gs = GridSearchCV(DecisionTreeRegressor(random_state=seed, min_samples_leaf=3),
                      {"ccp_alpha": sorted(set(np.clip(alphas, 0, None)))},
                      cv=GroupKFold(n_splits=min(folds, len(set(g)))), scoring="neg_mean_absolute_error")
    gs.fit(X, y, groups=g)
    return gs


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--yolo-dir", type=Path, default=None)
    ap.add_argument("--ball-class", type=int, default=1)
    ap.add_argument("--labels", type=Path, default=ROOT / "out" / "qa" / "ball_labels.json")
    ap.add_argument("--split-file", type=Path, default=ROOT / "data" / "dataset_ball" / "split.json")
    ap.add_argument("--split", default="all")
    ap.add_argument("--frames-dir", type=Path, default=ROOT / "data" / "frames")
    ap.add_argument("--hand-block", type=int, default=20)
    ap.add_argument("--outer-folds", type=int, default=5)
    ap.add_argument("--inner-folds", type=int, default=4)
    ap.add_argument("--seed", type=int, default=0)
    args = ap.parse_args()

    from sklearn.dummy import DummyRegressor
    from sklearn.metrics import mean_absolute_error, r2_score
    from sklearn.model_selection import GroupKFold
    from sklearn.tree import export_text

    frames = (load_yolo_dir(args.yolo_dir, args.ball_class) if args.yolo_dir else
              load_hand_labels(args.labels, args.split_file, args.split, args.frames_dir, args.hand_block))
    rows = [(f, b) for f in frames for b in f["gt"]]
    X = np.array([[(b[1] + b[3]) / 2 / f["H"]] for f, b in rows])
    y = np.array([(b[3] - b[1]) / f["H"] for f, b in rows])
    g = np.array([f["group"] for f, _ in rows])
    print(f"{len(rows)} labeled balls in {len(set(g))} groups; ball height / image height: "
          f"median {np.median(y):.4f}, min {y.min():.4f}, max {y.max():.4f}\n")

    pred_tree, pred_mean = np.zeros_like(y), np.zeros_like(y)
    for tr, te in GroupKFold(n_splits=min(args.outer_folds, len(set(g)))).split(X, y, g):
        pred_tree[te] = fit_tree(X[tr], y[tr], g[tr], args.inner_folds, args.seed).predict(X[te])
        pred_mean[te] = DummyRegressor().fit(X[tr], y[tr]).predict(X[te])
    print("| out-of-fold (grouped) | MAE (fraction of image height) | R^2 |\n|---|---|---|")
    for name, p in (("mean of training folds", pred_mean), ("pruned regression tree on y position", pred_tree)):
        print(f"| {name} | {mean_absolute_error(y, p):.4f} | {r2_score(y, p):.3f} |")

    gs = fit_tree(X, y, g, args.outer_folds, args.seed)
    est = gs.best_estimator_
    print(f"\nfinal tree on all rows: ccp_alpha {gs.best_params_['ccp_alpha']:.2e}, depth {est.get_depth()}, "
          f"{est.get_n_leaves()} leaves\n```\n{export_text(est, feature_names=['cy'], decimals=3)}```")
    return 0


if __name__ == "__main__":
    sys.exit(main())
