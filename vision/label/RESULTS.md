# Ball detector: recall and false positives (`eval_ball.py`)

What `eval_ball.py` measures: a Basketball prediction counts as a hit when its IoU
with the hand box (a square of side 2r around Sami's click) is at least 0.3.
Recall is frames with a hit divided by frames with a ball. A false positive is
any other prediction, counted over every frame of the split, including the
frames with no ball.

## Status on 2026-10-20: I could not re-run it on this Mac

I tried both evaluations at 21:59 CEST, from the repo root on branch
`rpl-review-additions`. The older docs use `.venv/bin/python`, but that venv
does not exist on this Mac (see `CLAUDE.md`), so I used `ml/.venv`:

```
ml/.venv/bin/python vision/label/eval_ball.py --split val --device mps
ml/.venv/bin/python vision/label/eval_ball.py --weights models/ball_hoop_v2.pt --split val --device mps
```

Both runs stop before any prediction with
`FileNotFoundError: .../out/qa/ball_labels.json`. These inputs are gitignored,
were never committed, and are nowhere on this Mac. I searched with `mdfind` and
`find` under the home folder:

| Missing path | What it is | Made by |
|---|---|---|
| `out/qa/ball_labels.json` | Sami's 120 hand labels `(cx, cy, r)`: 90 with a ball, 30 without | browser export of `vision/qa/ball_label.py`. The copy is probably on Sami's laptop: he committed `90e5472` and `6a2f8ad` |
| `data/frames/f_*.jpg` | the game10 frames (1920x1080) that the labels point to | `extract_frames.py` from `data/clips/game10.mp4`, which is also missing |
| `data/dataset_ball/split.json` | which labeled frame is train and which is val | `build_ball_dataset.py`. The split depends only on `ball_labels.json`: sorted by frame index, the first 60 ball and 20 no-ball frames go to train, the rest to val |
| `models/ball_hoop_v2.pt` | the fine-tuned weights that `train_ball.py` writes | `train_ball.py`. Not retrained here, because retraining is out of scope |

The base weights `models/ball_hoop_avishah.pt` are present. That is not enough,
because without the labels and frames neither the "before" nor the "after"
numbers can be recomputed.

## Recorded results (hackathon, 2026-08-28; I did not re-run these)

The table below quotes `docs/RESULTS.md`, section "Ball fine-tune on 80
coach-labeled frames", added in commit `6a2f8ad` (2026-08-28 13:56). The
scripts it ran are from commit `90e5472`. Recorded setup:

- val split: 40 held-out frames, 30 with a ball and 10 without, split by frame index;
- IoU 0.3 against the 2r squares, imgsz 1280, CPU;
- fine-tune: started from `ball_hoop_avishah.pt`, 122 train images, imgsz 1280, batch 4, AdamW lr0 0.002, 12 epochs in 12.1 min on MPS.

| conf | before: `ball_hoop_avishah.pt` recall | before: FP / 40 frames | before: precision | after: `ball_hoop_v2.pt` recall | after: FP / 40 frames | after: precision |
|---|---|---|---|---|---|---|
| 0.30 | not recorded | not recorded | not recorded | 16/30 = 53 % | 9 | 64 % |
| **0.35** (script default) | 13/30 = 43 % | 36 | 27 % | **16/30 = 53 %** | **8** | **67 %** |
| 0.45 | 10/30 = 33 % | 29 | 26 % | 13/30 = 43 % | 4 | 76 % |

I computed 95 % Wilson intervals from the recorded counts on 2026-10-20:
13/30 is 27–61 %, 16/30 is 36–70 % and 10/30 is 19–51 %.

**Reading**

- The fine-tune's clearest effect is on false positives. At the default conf 0.35, false balls drop from 36 to 8 in 40 frames, and precision rises from 27 % to 67 %.
- Recall rises by 3 balls (13 to 16 of 30). With only 30 labeled balls the two intervals overlap, so the recall gain is a hint, not a proven result.
- Changing conf trades recall against false positives. For v2, 0.45 halves the false positives again (8 to 4) but loses 3 of the 30 balls. 0.30 finds no extra ball and adds one false positive.
- I would pick **0.35** for v2. It finds as many balls as 0.30 with fewer false positives. Recall is the weak point (about half the frames), so 3 more balls are worth 4 more false positives over 40 frames.
- Pick 0.45 only if the next step reacts badly to a false ball. For example, the shot detector could take a ball on a wall fixture near the hoop as a shot.

## Reproduce once the labels and frames are back

```
ml/.venv/bin/python vision/label/build_ball_dataset.py --labels out/qa/ball_labels.json --device cpu
ml/.venv/bin/python vision/label/eval_ball.py --weights models/ball_hoop_avishah.pt --split val --conf 0.30 0.35 0.45 --device mps
ml/.venv/bin/python vision/label/eval_ball.py --weights models/ball_hoop_v2.pt     --split val --conf 0.30 0.35 0.45 --device mps
```

## Measured today on other labeled data

`ml/trees/RESULTS.md` runs `ball_hoop_avishah.pt` with the same IoU-0.3 rule on
221 human-labeled frames from a public dataset. These frames are not game10
frames. That file also adds a decision-tree filter on top of the detector.
