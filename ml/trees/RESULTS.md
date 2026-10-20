# Decision trees on top of the ball detector

This folder adds two scripts. The first, `fp_filter_tree.py`, is a
classification tree that looks at one YOLO ball detection at a time and keeps
it or drops it: true hit or false positive. The second,
`size_regression_tree.py`, is a regression tree that tries to predict ball size
from height in the image. Labels follow the rule of `vision/label/eval_ball.py`:
a hit is a box with IoU of at least 0.3 against a labeled ball, and the
`iou()` function is imported from that file.

## Why trees here

- **Easy to check.** The whole filter prints as a few if/else rules
  (`export_text`), so you can check that each rule makes physical sense: orange,
  round, not in the crowd at the bottom of the frame, near the hoop. A neural
  post-filter would not show that.
- **Cheap.** After YOLO, the filter costs a handful of comparisons per box, with
  no GPU and no feature scaling. It can be ported to Swift on the phone as
  nested `if`s.
- **Mixed features, no scaling needed.** Confidence, pixel ratios, colour
  fractions and counts can go in raw, and a tree can learn combinations such as
  "orange AND high in the frame".
- **Gini vs entropy.** Both measure how mixed a node is: Gini is `1 − Σ p²`,
  entropy is `−Σ p log₂ p`. Each split is chosen to lower the impurity as much
  as possible. They usually pick very similar splits, and entropy penalises
  mixed nodes a little more. I did not fix one: cross-validation picks the
  criterion together with the pruning strength.
- **Why pruning.** Grown to the end, a tree splits until every leaf is pure,
  which means it memorises single boxes. Cost-complexity pruning minimises
  `error(T) + α · leaves(T)`. The candidate α values come from
  `cost_complexity_pruning_path`, and the α that scores best in an *inner*
  grouped CV on the training folds wins. That makes the outer CV numbers below
  honest: no score comes from a test fold that was also used for tuning.
- **Grouped CV.** Roboflow exports contain several augmented copies of one frame
  (same frame number, different `.rf` hash) and neighbouring frames of one
  video. A random split would put near-copies on both sides, so the groups are
  source videos: 11 groups in total.

## Data: why not Sami's game10 labels

Sami's 120 game10 hand labels (`out/qa/ball_labels.json`) and their frames are
not on this Mac (see `vision/label/RESULTS.md`), and neither are the fine-tuned
weights. The only human-labeled ball data on this Mac is `data/spark/test_r1`
(gitignored). It is the fixed test set of the Spark pipeline on branch
`hoopergpt`, made of round 1's 221 validation images (commit `4e04b2d`). The
box labels come from three Roboflow Universe datasets, listed in
`ml/spark/sources.yaml` on `hoopergpt`:

- `deeplearning-gmyc6/basketball-game-detection` v4
- `tomas-34ray/basketball-detection-cjjxp` v4
- `deep-learning-training/basketball-z0v4x` v10

What the set contains:

- 221 frames: 83 with a ball, 88 ball boxes (one frame has 2 balls, one has 5);
- 180 frames are 640x640 and 41 are 700x700;
- the frames are 16:9 broadcast frames stretched to a square. The median
  labeled ball width/height is 0.52, 0.56 and 0.54 for the three sources, and a
  round ball stretched this way gives 9/16 = 0.56.

When the game10 labels come back, the same scripts run on them unchanged. That
is the default input:
`ml/.venv/bin/python ml/trees/fp_filter_tree.py --split all`. Use `--split val`
for weights that were trained on the train frames.

## Commands (run 2026-10-20 22:07 CEST, Apple MPS)

Environment: Python 3.14.4, ultralytics 8.4.131, torch 2.13.0, scikit-learn 1.9.1 (`ml/.venv`). I passed `data/spark/test_r1` as an absolute path to the
main checkout's copy, because `data/` is gitignored. Each detector run took
30 to 40 s.

```
ml/.venv/bin/python -m pip install -r ml/trees/requirements.txt
ml/.venv/bin/python ml/trees/fp_filter_tree.py --yolo-dir data/spark/test_r1 --ball-class 1 \
    --weights models/followcam_s_1280.pt --det-class 1 --hoop-class 2 --device mps        # run A
ml/.venv/bin/python ml/trees/fp_filter_tree.py --yolo-dir data/spark/test_r1 --ball-class 1 --device mps   # run B, avishah
ml/.venv/bin/python ml/trees/size_regression_tree.py --yolo-dir data/spark/test_r1 --ball-class 1          # run C
```

The defaults in all runs:

- `--min-conf 0.05`: every box above it is a row;
- `--iou 0.3`, imgsz 1280;
- 5 outer and 4 inner `GroupKFold` folds;
- `random_state 0`.

I ran each command twice and got identical output.

## Summary

| Detector on `test_r1` | candidate boxes (hits / FP) | conf-threshold baseline, out-of-fold F1 | pruned tree, out-of-fold F1 | final tree | top features |
|---|---|---|---|---|---|
| A: `followcam_s_1280.pt` (Spark round 1) | 143 (71 / 72) | **0.848** (P 80.0 %, R 90.1 %) | 0.803 (P 80.3 %, R 80.3 %) | depth 1, 2 leaves: `conf <= 0.228` means FP | conf (1.000) |
| B: `ball_hoop_avishah.pt` (base of `train_ball.py`) | 542 (22 / 520) | 0.167 (P 21.4 %, R 13.6 %) | **0.350** (P 38.9 %, R 31.8 %) | depth 7, 12 leaves | cy 0.212, aspect 0.180, orange_frac 0.169, conf_gap 0.136, hoop_dist 0.124 |

P and R are precision and recall over the candidate detections. Each detection
is scored by a model fitted without its CV group.

**Reading.**

- **Run A, a good in-domain detector.** Pruning, with α chosen by cross-validation, cuts the tree back to a single split on confidence. The tree has in effect re-discovered the threshold rule (cut at 0.228).
- The other features do not generalise across videos. With 71 positives, the extra freedom costs a little: out-of-fold F1 is 0.803 for the tree vs 0.848 for the CV-chosen threshold.
- Verdict for A: keep the plain confidence threshold. The tree confirms where to put it.
- **Run B, a detector out of its domain.** On stretched 640 px frames, 96 % of avishah's candidate boxes are false.
- In run B, confidence alone hardly separates hits from false boxes. The tree uses colour (`orange_frac`), shape (`aspect` 0.49–0.65 is a round ball stretched 9:16), height in the frame (`cy`) and distance to the hoop.
- The result: out-of-fold F1 roughly doubles (0.167 to 0.350), and the tree finds 7 balls vs 3 at the same 11 false positives.
- Run B has only 22 positives, so its tree is unstable: fold depths range from 6 to 10. A post-filter can also only drop boxes, never find a missed ball, so recall stays low (7/88).
- **Overall.** A tree post-filter pays off when the detector's confidence does not fit the domain. When the detector is good, CV pruning shows that by collapsing the tree to a confidence threshold.

**Caveats.**

- `test_r1` was round 1's validation set, so run A's detector picked its best epoch on these images. Run A's detector numbers are therefore somewhat optimistic, even though the model never trained on these images.
- avishah's training data is unknown (third-party weights). Its 10.2 % recall at conf 0.35 on these stretched frames says nothing about game10, where 43 % was recorded at the same conf.
- The labels are Roboflow annotators' labels, not Sami's.
- The positive counts are small (71 and 22).

## Run A: `models/followcam_s_1280.pt` (ball = class 1, hoop = class 2)

#### Data

followcam_s_1280.pt on test_r1: 221 frames (83 with a ball, 88 ball boxes), 11 CV groups; 143 ball detections (class 1) at conf >= 0.05 (imgsz 1280, mps): 71 hits, 72 false positives (IoU >= 0.3).

#### Confidence threshold only (no fitting)

| conf | balls found | recall | false positives | detection precision | detection F1 |
|---|---|---|---|---|---|
| 0.05 | 71/88 | 80.7% | 72 | 49.7% | 0.664 |
| 0.25 | 69/88 | 78.4% | 19 | 78.4% | 0.868 |
| 0.35 | 66/88 | 75.0% | 15 | 81.5% | 0.868 |
| 0.45 | 65/88 | 73.9% | 11 | 85.5% | 0.884 |

#### Outer grouped CV, per fold

| fold | test groups | test dets | threshold | tree criterion | ccp_alpha | depth | leaves |
|---|---|---|---|---|---|---|---|
| 0 | 1 | 33 | 0.229 | gini | 0.02572 | 3 | 4 |
| 1 | 1 | 30 | 0.458 | gini | 0.01716 | 4 | 5 |
| 2 | 2 | 26 | 0.458 | entropy | 0.08270 | 1 | 2 |
| 3 | 3 | 26 | 0.459 | gini | 0.01923 | 4 | 6 |
| 4 | 4 | 28 | 0.458 | gini | 0.02049 | 4 | 5 |

#### Out-of-fold result (each detection scored by a model that never saw its CV group)

| method | det. precision | det. recall | det. F1 | balls found | recall | false positives |
|---|---|---|---|---|---|---|
| all detections (conf >= 0.05) | 49.7% | 100.0% | 0.664 | 71/88 | 80.7% | 72 |
| confidence threshold (CV-chosen) | 80.0% | 90.1% | 0.848 | 64/88 | 72.7% | 16 |
| pruned decision tree | 80.3% | 80.3% | 0.803 | 57/88 | 64.8% | 14 |

#### Final tree (all 143 detections)

criterion entropy, ccp_alpha 0.07491 (grouped 5-fold CV F1 0.845), depth 1, 2 leaves; class 1 = hit, 0 = false positive.

```
|--- conf <= 0.228
|   |--- weights: [53.000, 1.000] class: 0
|--- conf >  0.228
|   |--- weights: [19.000, 70.000] class: 1
```

| feature | importance |
|---|---|
| conf | 1.000 |

(cached detections: out/trees/dets_followcam_s_1280_test_r1_c0.05_i1280.json)

## Run B: `models/ball_hoop_avishah.pt` (Basketball = class 0, hoop = class 1)

#### Data

ball_hoop_avishah.pt on test_r1: 221 frames (83 with a ball, 88 ball boxes), 11 CV groups; 542 ball detections (class 0) at conf >= 0.05 (imgsz 1280, mps): 22 hits, 520 false positives (IoU >= 0.3).

#### Confidence threshold only (no fitting)

| conf | balls found | recall | false positives | detection precision | detection F1 |
|---|---|---|---|---|---|
| 0.05 | 22/88 | 25.0% | 520 | 4.1% | 0.078 |
| 0.25 | 11/88 | 12.5% | 153 | 6.7% | 0.118 |
| 0.35 | 9/88 | 10.2% | 102 | 8.1% | 0.135 |
| 0.45 | 7/88 | 8.0% | 64 | 9.9% | 0.151 |

#### Outer grouped CV, per fold

| fold | test groups | test dets | threshold | tree criterion | ccp_alpha | depth | leaves |
|---|---|---|---|---|---|---|---|
| 0 | 2 | 121 | 0.774 | entropy | 0.01309 | 7 | 9 |
| 1 | 2 | 106 | 0.690 | entropy | 0.01247 | 7 | 10 |
| 2 | 2 | 106 | 0.671 | entropy | 0.01877 | 6 | 8 |
| 3 | 3 | 109 | 0.738 | entropy | 0.01224 | 6 | 8 |
| 4 | 2 | 100 | 0.738 | entropy | 0.00000 | 10 | 14 |

#### Out-of-fold result (each detection scored by a model that never saw its CV group)

| method | det. precision | det. recall | det. F1 | balls found | recall | false positives |
|---|---|---|---|---|---|---|
| all detections (conf >= 0.05) | 4.1% | 100.0% | 0.078 | 22/88 | 25.0% | 520 |
| confidence threshold (CV-chosen) | 21.4% | 13.6% | 0.167 | 3/88 | 3.4% | 11 |
| pruned decision tree | 38.9% | 31.8% | 0.350 | 7/88 | 8.0% | 11 |

#### Final tree (all 542 detections)

criterion entropy, ccp_alpha 0.00909 (grouped 5-fold CV F1 0.542), depth 7, 12 leaves; class 1 = hit, 0 = false positive.

```
|--- orange_frac <= 0.490
|   |--- hoop_dist <= 0.318
|   |   |--- hoop_dist <= 0.308
|   |   |   |--- h <= 0.099
|   |   |   |   |--- conf <= 0.356
|   |   |   |   |   |--- weights: [66.000, 0.000] class: 0
|   |   |   |   |--- conf >  0.356
|   |   |   |   |   |--- weights: [12.000, 2.000] class: 0
|   |   |   |--- h >  0.099
|   |   |   |   |--- weights: [0.000, 1.000] class: 1
|   |   |--- hoop_dist >  0.308
|   |   |   |--- weights: [0.000, 1.000] class: 1
|   |--- hoop_dist >  0.318
|   |   |--- weights: [292.000, 0.000] class: 0
|--- orange_frac >  0.490
|   |--- cy <= 0.722
|   |   |--- conf_gap <= 0.029
|   |   |   |--- aspect <= 0.493
|   |   |   |   |--- weights: [10.000, 0.000] class: 0
|   |   |   |--- aspect >  0.493
|   |   |   |   |--- aspect <= 0.648
|   |   |   |   |   |--- n_in_frame <= 3.500
|   |   |   |   |   |   |--- cy <= 0.174
|   |   |   |   |   |   |   |--- weights: [1.000, 0.000] class: 0
|   |   |   |   |   |   |--- cy >  0.174
|   |   |   |   |   |   |   |--- weights: [0.000, 15.000] class: 1
|   |   |   |   |   |--- n_in_frame >  3.500
|   |   |   |   |   |   |--- weights: [5.000, 1.000] class: 0
|   |   |   |   |--- aspect >  0.648
|   |   |   |   |   |--- weights: [7.000, 0.000] class: 0
|   |   |--- conf_gap >  0.029
|   |   |   |--- weights: [49.000, 2.000] class: 0
|   |--- cy >  0.722
|   |   |--- weights: [78.000, 0.000] class: 0
```

| feature | importance |
|---|---|
| cy | 0.212 |
| aspect | 0.180 |
| orange_frac | 0.169 |
| conf_gap | 0.136 |
| hoop_dist | 0.124 |
| n_in_frame | 0.086 |
| conf | 0.048 |
| h | 0.046 |

(cached detections: out/trees/dets_ball_hoop_avishah_test_r1_c0.05_i1280.json)

## Run C: regression tree, ball size from vertical position (negative result)

This run tests whether ball height in the image (fraction of image height)
follows from its vertical position (perspective), using the 88 labeled boxes
and the same 11 video groups.

88 labeled balls in 11 groups; ball height / image height: median 0.0375, min 0.0157, max 0.7906

| out-of-fold (grouped) | MAE (fraction of image height) | R^2 |
|---|---|---|
| mean of training folds | 0.0584 | -0.115 |
| pruned regression tree on y position | 0.0689 | -0.451 |

final tree on all rows: ccp_alpha 4.14e-05, depth 5, 6 leaves
```
|--- cy <= 0.762
|   |--- cy <= 0.568
|   |   |--- value: [0.038]
|   |--- cy >  0.568
|   |   |--- cy <= 0.577
|   |   |   |--- value: [0.289]
|   |   |--- cy >  0.577
|   |   |   |--- cy <= 0.655
|   |   |   |   |--- value: [0.034]
|   |   |   |--- cy >  0.655
|   |   |   |   |--- cy <= 0.669
|   |   |   |   |   |--- value: [0.259]
|   |   |   |   |--- cy >  0.669
|   |   |   |   |   |--- value: [0.055]
|--- cy >  0.762
|   |--- value: [0.224]
```

On out-of-fold MAE, the pruned regression tree does worse than always
predicting the training mean (0.0689 vs 0.0584 of image height), and both
have negative R². The data do not support a perspective model across these
mixed broadcast cameras: zoom changes from shot to shot, and 6 of the 88 boxes
are more than 15 % of image height (4 of them in a single frame). Those large
boxes drive the squared-error splits, which is why the final tree splits on
narrow `cy` bands. A size-from-position model would need a single fixed camera,
such as game10 or the rig. On game10 the same script runs with
`ml/.venv/bin/python ml/trees/size_regression_tree.py` once the labels are back.
I am keeping it here as a negative result, not as a model to use.
