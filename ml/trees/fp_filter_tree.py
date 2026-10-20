"""Pruned decision tree that keeps or drops YOLO Basketball detections (true hit vs false positive).

Usage (repo root, the ml venv has ultralytics + scikit-learn):
    ml/.venv/bin/python ml/trees/fp_filter_tree.py                      # Sami's game10 hand labels
    ml/.venv/bin/python ml/trees/fp_filter_tree.py --yolo-dir data/spark/test_r1 --ball-class 1 \
        --weights models/followcam_s_1280.pt --det-class 1 --hoop-class 2

Detector: --weights (default models/ball_hoop_avishah.pt: class 0 Basketball,
1 Basketball Hoop; Spark/FollowCam models: 1 ball, 2 hoop), run once at
--min-conf so every candidate box is a training row.
Label of a detection: the rule of vision/label/eval_ball.py. Boxes of a frame are
taken in descending confidence; a box is a hit when its IoU with a not yet
matched ball box is >= --iou (0.3), otherwise it is a false positive. The iou()
function is imported from eval_ball.py, not copied.
Ground truth, one of:
  * hand labels (default): out/qa/ball_labels.json + data/dataset_ball/split.json,
    images in data/frames, ball box = square of side 2r (exactly as eval_ball.py);
  * --yolo-dir DIR: DIR/images + DIR/labels in YOLO txt format, ball = --ball-class.
Features per detection: confidence, box w/h, pixel aspect ratio, area, normalised
x/y centre, rank and count of ball boxes in the frame, confidence gap to the
frame's best box, distance to the nearest hoop box, orange-pixel fraction.
Model: sklearn DecisionTreeClassifier. criterion (gini/entropy) and ccp_alpha
(cost-complexity pruning, candidates from cost_complexity_pruning_path) are
chosen by an inner grouped CV, inside an outer grouped CV that reports
precision/recall/F1 against a confidence-threshold-only baseline (threshold
chosen on the same training folds). Groups = source video (Roboflow file names)
or blocks of --hand-block consecutive frame indices (single game10 video), so
near-identical frames never sit on both sides of a split.
Prints tables in markdown, the final tree (export_text) and feature importances.
Detections are cached in --cache-dir (gitignored out/trees); --reuse skips YOLO.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "vision" / "label"))
from eval_ball import iou  # noqa: E402  the IoU used for every hit/FP decision in eval_ball.py

FEATURES = ["conf", "w", "h", "aspect", "area", "cx", "cy",
            "rank_in_frame", "n_in_frame", "conf_gap", "hoop_dist", "orange_frac"]
NO_HOOP = 1.5  # hoop_dist when no hoop is detected (real distances are <= 1, a diagonal)


# ---------------------------------------------------------------- ground truth

def video_group(stem: str) -> str:
    """<source>__<video>_mp4-<n>_jpg.rf.<hash> -> <source>/<video>; else <source>/<alpha prefix>."""
    src, _, rest = stem.rpartition("__")
    m = re.match(r"(.+?)_mp4-", rest)
    name = m.group(1) if m else (re.match(r"[A-Za-z]*", rest).group(0) or rest)
    return f"{src}/{name}" if src else name


def load_yolo_dir(d: Path, ball_class: int) -> list[dict]:
    from PIL import Image
    frames = []
    for img in sorted(p for p in (d / "images").iterdir() if p.suffix.lower() in {".jpg", ".jpeg", ".png"}):
        W, H = Image.open(img).size
        gt = []
        lab = d / "labels" / f"{img.stem}.txt"
        for line in (lab.read_text().splitlines() if lab.exists() else []):
            parts = line.split()
            if len(parts) == 5 and int(parts[0]) == ball_class:
                cx, cy, bw, bh = (float(v) for v in parts[1:])
                gt.append([(cx - bw / 2) * W, (cy - bh / 2) * H, (cx + bw / 2) * W, (cy + bh / 2) * H])
        frames.append({"path": str(img), "file": img.name, "group": video_group(img.stem), "W": W, "H": H, "gt": gt})
    return frames


def load_hand_labels(labels: Path, split_file: Path, split: str, frames_dir: Path, block: int) -> list[dict]:
    from PIL import Image
    rows = json.loads(labels.read_text())["frames"]
    if split != "all":
        assign = json.loads(split_file.read_text())["split"]
        rows = [f for f in rows if assign.get(f["file"]) == split]
    frames = []
    for f in rows:
        path = frames_dir / f["file"]
        W, H = Image.open(path).size
        gt = []
        if f["ball"]:
            cx, cy, r = f["ball"]
            gt.append([cx - r, cy - r, cx + r, cy + r])  # square of side 2r, as eval_ball.py
        i = int(re.sub(r"\D", "", f["file"]) or 0)
        frames.append({"path": str(path), "file": f["file"], "group": f"block{i // block}", "W": W, "H": H, "gt": gt})
    return frames


# ---------------------------------------------------------------- detections + features

def orange_fraction(img_bgr, box) -> float:
    import cv2
    x1, y1, x2, y2 = (int(round(v)) for v in box)
    crop = img_bgr[max(y1, 0):max(y2, 0), max(x1, 0):max(x2, 0)]
    if crop.size == 0:
        return 0.0
    hsv = cv2.cvtColor(crop, cv2.COLOR_BGR2HSV)
    h, s, v = hsv[..., 0], hsv[..., 1], hsv[..., 2]
    return float(((h >= 5) & (h <= 25) & (s >= 80) & (v >= 50)).mean())


def match(dets: list[dict], gt: list[list[float]], thr: float) -> list[int]:
    """eval_ball.py rule, generalised to several balls: by descending conf, first IoU>=thr with an unused GT box."""
    used, out = set(), []
    for d in dets:  # already sorted by conf, descending
        best = next((j for j, g in enumerate(gt) if j not in used and iou(d["box"], g) >= thr), None)
        if best is None:
            out.append(0)
        else:
            used.add(best)
            out.append(1)
    return out


def detect(frames: list[dict], weights: Path, min_conf: float, imgsz: int, device: str, iou_thr: float,
           det_class: int, hoop_class: int) -> None:
    import cv2
    from ultralytics import YOLO
    model = YOLO(str(weights))
    for f in frames:
        img = cv2.imread(f["path"])
        r = model.predict(img, imgsz=imgsz, conf=min_conf, classes=[det_class, hoop_class], device=device, verbose=False)[0]
        boxes, confs, cls = r.boxes.xyxy.tolist(), r.boxes.conf.tolist(), r.boxes.cls.tolist()
        balls = sorted(([b, c] for b, c, k in zip(boxes, confs, cls) if int(k) == det_class), key=lambda t: -t[1])
        hoops = [b for b, c, k in zip(boxes, confs, cls) if int(k) == hoop_class and c >= 0.25]
        W, H = f["W"], f["H"]
        diag = (W ** 2 + H ** 2) ** 0.5
        dets = []
        for rank, (b, c) in enumerate(balls):
            bw, bh = b[2] - b[0], b[3] - b[1]
            cx, cy = (b[0] + b[2]) / 2, (b[1] + b[3]) / 2
            hd = min((((cx - (h[0] + h[2]) / 2) ** 2 + (cy - (h[1] + h[3]) / 2) ** 2) ** 0.5 / diag for h in hoops),
                     default=NO_HOOP)
            dets.append({"box": b, "conf": c, "w": bw / W, "h": bh / H, "aspect": bw / max(bh, 1e-6),
                         "area": bw * bh / (W * H), "cx": cx / W, "cy": cy / H, "rank_in_frame": rank,
                         "n_in_frame": len(balls), "conf_gap": balls[0][1] - c, "hoop_dist": hd,
                         "orange_frac": orange_fraction(img, b)})
        for d, y in zip(dets, match(dets, f["gt"], iou_thr)):
            d["hit"] = y
        f["dets"] = dets


# ---------------------------------------------------------------- evaluation

def prf(y, p) -> tuple[float, float, float]:
    from sklearn.metrics import f1_score, precision_score, recall_score
    return (precision_score(y, p, zero_division=0), recall_score(y, p, zero_division=0),
            f1_score(y, p, zero_division=0))


def system_score(frames: list[dict], keep: np.ndarray, iou_thr: float) -> tuple[int, int, int]:
    """eval_ball.py-style counts on the kept boxes: (balls found, all labeled balls, false positives)."""
    k, found, fps = 0, 0, 0
    for f in frames:
        n = len(f["dets"])
        kept = [d for d, m in zip(f["dets"], keep[k:k + n]) if m]
        k += n
        m = match(kept, f["gt"], iou_thr)
        found += sum(m)
        fps += len(m) - sum(m)
    return found, sum(len(f["gt"]) for f in frames), fps


def best_threshold(conf: np.ndarray, y: np.ndarray) -> float:
    """Confidence cut with the best F1 on the given (training) rows."""
    cands = np.unique(conf)
    return float(max(cands, key=lambda t: (prf(y, conf >= t)[2], -t)))


def tree_search(X, y, g, n_inner: int, seed: int):
    from sklearn.metrics import f1_score, make_scorer
    from sklearn.model_selection import GridSearchCV, GroupKFold
    from sklearn.tree import DecisionTreeClassifier
    grid = []
    for crit in ("gini", "entropy"):
        alphas = DecisionTreeClassifier(criterion=crit, random_state=seed).cost_complexity_pruning_path(X, y).ccp_alphas
        grid.append({"criterion": [crit], "ccp_alpha": sorted(set(np.round(np.clip(alphas, 0, None), 8)))})
    cv = GroupKFold(n_splits=min(n_inner, len(set(g))))
    gs = GridSearchCV(DecisionTreeClassifier(random_state=seed), grid, cv=cv,
                      scoring=make_scorer(f1_score, zero_division=0), refit=True)
    gs.fit(X, y, groups=g)
    return gs


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--weights", type=Path, default=ROOT / "models" / "ball_hoop_avishah.pt")
    ap.add_argument("--yolo-dir", type=Path, default=None, help="labeled YOLO dir (images/, labels/) instead of hand labels")
    ap.add_argument("--ball-class", type=int, default=1, help="ball class id in --yolo-dir labels (Spark: 1)")
    ap.add_argument("--det-class", type=int, default=0, help="ball class id of the detector (avishah: 0)")
    ap.add_argument("--hoop-class", type=int, default=1, help="hoop class id of the detector (avishah: 1)")
    ap.add_argument("--labels", type=Path, default=ROOT / "out" / "qa" / "ball_labels.json")
    ap.add_argument("--split-file", type=Path, default=ROOT / "data" / "dataset_ball" / "split.json")
    ap.add_argument("--split", default="all", help="hand labels: all / train / val (use val for weights trained on train)")
    ap.add_argument("--frames-dir", type=Path, default=ROOT / "data" / "frames")
    ap.add_argument("--hand-block", type=int, default=20, help="hand labels: frames i//block form one CV group")
    ap.add_argument("--min-conf", type=float, default=0.05, help="detector floor; every box above it is a row")
    ap.add_argument("--conf", type=float, nargs="+", default=[0.25, 0.35, 0.45], help="fixed thresholds to report")
    ap.add_argument("--iou", type=float, default=0.3)
    ap.add_argument("--imgsz", type=int, default=1280)
    ap.add_argument("--device", default="mps")
    ap.add_argument("--outer-folds", type=int, default=5)
    ap.add_argument("--inner-folds", type=int, default=4)
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--cache-dir", type=Path, default=ROOT / "out" / "trees")
    ap.add_argument("--reuse", action="store_true", help="load cached detections instead of running YOLO")
    args = ap.parse_args()

    from sklearn.model_selection import GroupKFold
    from sklearn.tree import export_text

    data_name = args.yolo_dir.name if args.yolo_dir else f"hand_{args.split}"
    cache = args.cache_dir / f"dets_{args.weights.stem}_{data_name}_c{args.min_conf}_i{args.imgsz}.json"
    if args.reuse and cache.exists():
        frames = json.loads(cache.read_text())
    else:
        if args.yolo_dir:
            frames = load_yolo_dir(args.yolo_dir, args.ball_class)
        else:
            frames = load_hand_labels(args.labels, args.split_file, args.split, args.frames_dir, args.hand_block)
        detect(frames, args.weights, args.min_conf, args.imgsz, args.device, args.iou, args.det_class, args.hoop_class)
        cache.parent.mkdir(parents=True, exist_ok=True)
        cache.write_text(json.dumps(frames))

    rows = [(f, d) for f in frames for d in f["dets"]]
    X = np.array([[d[k] for k in FEATURES] for _, d in rows], dtype=float)
    y = np.array([d["hit"] for _, d in rows], dtype=int)
    g = np.array([f["group"] for f, _ in rows])
    conf = X[:, 0]
    n_gt = sum(len(f["gt"]) for f in frames)
    print(f"## Data\n\n{args.weights.name} on {data_name}: {len(frames)} frames "
          f"({sum(1 for f in frames if f['gt'])} with a ball, {n_gt} ball boxes), {len(set(f['group'] for f in frames))} CV groups; "
          f"{len(rows)} ball detections (class {args.det_class}) at conf >= {args.min_conf} (imgsz {args.imgsz}, {args.device}): "
          f"{int(y.sum())} hits, {int(len(y) - y.sum())} false positives (IoU >= {args.iou}).\n")

    # fixed thresholds, no fitting (the eval_ball.py table on this data)
    print("## Confidence threshold only (no fitting)\n")
    print("| conf | balls found | recall | false positives | detection precision | detection F1 |\n|---|---|---|---|---|---|")
    for t in [args.min_conf] + args.conf:
        keep = conf >= t
        found, total, fps = system_score(frames, keep, args.iou)
        p, r, f1 = prf(y, keep)
        print(f"| {t:.2f} | {found}/{total} | {found / max(total, 1):.1%} | {fps} | {p:.1%} | {f1:.3f} |")

    # outer grouped CV: tree vs threshold, both fitted on the same training folds
    outer = GroupKFold(n_splits=min(args.outer_folds, len(set(g))))
    pred_tree = np.zeros_like(y)
    pred_thr = np.zeros_like(y)
    print("\n## Outer grouped CV, per fold\n\n| fold | test groups | test dets | threshold | tree criterion | ccp_alpha | depth | leaves |\n|---|---|---|---|---|---|---|---|")
    for k, (tr, te) in enumerate(outer.split(X, y, g)):
        t = best_threshold(conf[tr], y[tr])
        pred_thr[te] = conf[te] >= t
        gs = tree_search(X[tr], y[tr], g[tr], args.inner_folds, args.seed)
        pred_tree[te] = gs.predict(X[te])
        est = gs.best_estimator_
        print(f"| {k} | {len(set(g[te]))} | {len(te)} | {t:.3f} | {gs.best_params_['criterion']} | "
              f"{gs.best_params_['ccp_alpha']:.5f} | {est.get_depth()} | {est.get_n_leaves()} |")

    print("\n## Out-of-fold result (each detection scored by a model that never saw its CV group)\n")
    print("| method | det. precision | det. recall | det. F1 | balls found | recall | false positives |\n|---|---|---|---|---|---|---|")
    for name, pred in (("all detections (conf >= %.2f)" % args.min_conf, np.ones_like(y)),
                       ("confidence threshold (CV-chosen)", pred_thr), ("pruned decision tree", pred_tree)):
        p, r, f1 = prf(y, pred)
        found, total, fps = system_score(frames, pred.astype(bool), args.iou)
        print(f"| {name} | {p:.1%} | {r:.1%} | {f1:.3f} | {found}/{total} | {found / max(total, 1):.1%} | {fps} |")

    # final model on all rows (criterion + alpha by grouped CV), for reading
    gs = tree_search(X, y, g, args.outer_folds, args.seed)
    est = gs.best_estimator_
    print(f"\n## Final tree (all {len(y)} detections)\n\ncriterion {gs.best_params_['criterion']}, "
          f"ccp_alpha {gs.best_params_['ccp_alpha']:.5f} (grouped {min(args.outer_folds, len(set(g)))}-fold CV F1 "
          f"{gs.best_score_:.3f}), depth {est.get_depth()}, {est.get_n_leaves()} leaves; class 1 = hit, 0 = false positive.\n")
    print("```\n" + export_text(est, feature_names=FEATURES, decimals=3, show_weights=True) + "```\n")
    print("| feature | importance |\n|---|---|")
    for i in np.argsort(-est.feature_importances_):
        if est.feature_importances_[i] > 0:
            print(f"| {FEATURES[i]} | {est.feature_importances_[i]:.3f} |")
    print(f"\n(cached detections: {cache.relative_to(ROOT) if cache.is_relative_to(ROOT) else cache})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
