# Plan: make/miss and shooter identity to 90%+ (2026-11-20)

Status: draft for review. Written from the repo as of 2026-11-20 (code cited as file:line). Every number not in the
repo is marked *(estimate)*. Spark = the DGX Spark, reached **only via NVIDIA Sync**, one heavy job at a time, never
polled in a loop.

## Summary

- **Where we are.** game10 (10-minute edited broadcast clip, `docs/RESULTS.md:200-210`): make/miss 16/22 (73%),
  shooter identity 6/15 (40%), shooter team 17/22 (77%). 95% Wilson intervals: make/miss **52-87%**, shooter **20-64%**.
  Today's numbers are a rough starting point, not a precise one.
- **The eval set comes first.** Claiming "≥ 90%" with a 95% lower bound needs about **200-300 labelled shots** from a
  system that is really about 94% accurate (189/200 correct gives a lower bound of 90.4%), split by game, filmed from
  the product's own camera position. The only labelled clip today is edited broadcast with 48 cuts.
- **Make/miss root cause:** the verdict is final on the first ball sample below the rim, from a 2D line crossing or a
  single sample in the net zone, with no depth (`vision/stats/shots.py:145-163, 280-286`; same in
  `app/FollowCamApp/Game/ShotDetector.swift:115-118`). From a sideline phone a rim-out crosses the rim on screen like a
  make: that is 4 of the 6 errors. Fixes: proof of passage through the net, a re-rise check, a delayed verdict, hoop
  hygiene, then a rim-crop make/miss classifier trained on the Spark, then a second phone at the baseline.
- **Shooter root cause:** the iOS app names the last ball holder, which is the nearest box centre
  (`ShotDetector.swift:99`, `Possession.swift:47-57`). Python extrapolates 0.12 s back to a widened box
  (`shots.py:454-511`). Tracker ReID is off (`vision/track/botsort.yaml:15`), and jersey OCR numbered 1 of 75 tracks
  (`docs/PR_BODY.md:9`). Fixes: score the eval per person (team + number); pose-based last touch; jersey OCR limited to
  the roster in a window around the release; per-game team set-up; ReID merge after the game.
- **Live versus after the game.** The phone gives a fast provisional call with one-tap correction. The Spark
  re-processes the full-resolution game afterwards with heavier models and sends a final report back to the app. The
  90% claim is made first for the **after-game report**. Live target: about 85-90% on its own, above 90% with the one
  tap counted.
- **When 90% shooter identity may be out of reach:** from one sideline phone, numbers are often unreadable. Fallbacks:
  roster plus one tap, a second camera, or making **shooter team** the hard ≥ 90% metric and reporting person-level as
  accuracy over the shots the system answers, with coverage stated.

---

## 1. What the code does today

### 1.1 Python make/miss (`vision/stats/shots.py`)

| Step | Code | Behaviour |
|---|---|---|
| "up" (ball rising near the hoop) | `in_up_zone` :133-138, `_arc_ok` :374-397 | Ball within 4 hoop widths × 4 hoop heights above the rim, moved ≥ 0.5 widths, rose ≥ 1 hoop height |
| attempt | :256-264 | First non-predicted ball sample below the rim line after "up" |
| rim line | `rim_y` :129-130, `rim_frac = 0.0` :61 | Top edge of the hoop box (the box covers rim and net) |
| **made (a)** | `crosses_rim` :152-163, `rim_inner_frac 0.8` :63 | 2D line from the last sample above to the first below crosses the rim line inside the central 80% of the box |
| **made (b)** | `in_net` :145-149, `net_depth (0.5, 2.0)` :62 | **One** sample inside the hoop x-range, 0.5-2.0 hoop heights below the rim, within 0.5 s |
| verdict timing | :282-286 | **Final on the first sample below the rim**; later evidence is never considered |
| vanished | `_vanished_attempt` :313-355 | Ball lost near the rim → miss with `made_confirmed=False` (a hint is computed but not used) |
| hoop | `vision/track/tracker.py:16-17, 70` | TRACK keeps the largest hoop and carries it forward up to `hoop_hold=50` frames during pans |

### 1.2 iOS make/miss (`app/FollowCamApp/Game/ShotDetector.swift`)

- A port of the same rules (`:24-40` mirror `ShotParams`). It picks the hoop nearest the ball (`:97`), has no
  `made_confirmed` (a vanished ball is a plain miss, `:129-139`), and makes the same single-sample decision (`:115-118`).
- The on-device detector takes 41-69 ms per frame on an iPhone 16, so analysis runs at 10-15 fps against a 30 fps
  picture (`Screens/ContentView.swift:74, 721`). Only a few samples land in the rim-to-net window.
- Detector round 5 mini: ball recall 0.739, precision 0.856 (`Vision/DetectorConfig.swift:6-11`).

### 1.3 Shooter attribution

- **Python** (`shots.py:399-511`): walk the flight backwards, then extrapolate at most 0.12 s to a release point
  (`:466-469`). Pick the player whose widened upper box contains it, ranked by distance to the **box centre**
  (`:487-489`). Fallbacks: the box the first sample left, the nearest top edge, the possession holder. Team comes from
  the track's majority colour.
- **Possession** (Python and iOS): nearest box centre within 1.5 box heights (`vision/stats/possession.py:29-31,
  75-84`; `Possession.swift:17, 47-57`).
- **iOS**: shooter = `lastHolder` within 4 s before "up" (`ShotDetector.swift:60-66, 99`). No release logic, no pose.
- **Teams**: hand-written colour rules for one game (`vision/track/teams.py:10-14, 34-41`).
- **Tracking**: ByteTrack/BoT-SORT with `with_reid: False`, `track_buffer 50`.
- **Jersey numbers**: EasyOCR on 6 torso crops over the track's life, boxes under 60 px skipped
  (`vision/numbers/read.py:44-55`): 1 of 75 tracks numbered. On iOS, Vision OCR with up to 12 reads per track, at any
  time rather than at the release (`Game/JerseyVotes.swift:9-12`).

### 1.4 Human correction today

- The phone's `GameStats` has `undoLast()`, `addManual` and `setPoints(_:shot:)` (`Game/GameStats.swift:103-130`). The
  UI wires only Undo and +1/+2/+3 (`Screens/GameReportView.swift:63-90`), and `setPoints` is never called from the UI.
  You cannot flip a past shot, reassign its shooter, or delete a false shot. Corrections are not stored anywhere they
  could become training data.

### 1.5 Evaluation today

- `vision/qa/shot_sheets.py` and `vision/stats/eval_human.py` review only the shots the system *called*. Missed attempts
  are found only by chance.
- Shooter correctness is tied to track ids. 7 attributions changed after a fix and were never re-judged
  (`RESULTS.md:207`).
- There are no confidence intervals.
- The one clip is edited broadcast (48 cuts) with the hoop about 30 px across. That is not the product's camera
  position.

---

## 2. Root causes

### 2.1 Make/miss (6 errors of 22)

| Errors | Root cause | Code |
|---|---|---|
| **4 rim-outs called makes** | The 2D crossing has no depth. `in_net` takes one sample in a tall zone that also covers the space in front of and behind the net. The verdict is final on the first sample below the rim, so a bounce back up never overturns it. | `shots.py:152-163, 145-149, 280-286`; Swift `:115-118` |
| **1 ball lost at the rim** | The ball isn't detected at the ring, a vanished ball always becomes a miss, and the hint is ignored. Ball recall is the bottleneck. | `shots.py:313-355`; `RESULTS.md:116-121` |
| **1 make called a miss** | Hypothesis, not checked on video: the ball crossed the net between samples (10-15 fps on the phone). | `shots.py:62, 70` |
| Likely contributors | A carried-forward (stale) hoop box during pans; the rim line taken as the top of a box that includes the net | `tracker.py:16-17, 70` |

**About the KILL_LIST C1 "rim depth gate"** (ball wider than 1.2 × the rim = in front of it). It is cheap and worth
adding, but from a sideline phone 10-15 m away, front iron and back iron differ by only a 3-5% size change
*(estimate)*, which is below box noise. So it rejects balls clearly nearer the camera, such as balls in hands or passes
in front of the hoop, but **it won't separate a rim-out from a make**. That has to come from what the ball does after
the rim.

### 2.2 Shooter identity (9 of 15 wrong; team 5 of 22 wrong)

- **The eval is ill-posed.** It judges track ids, not people.
- **The release point is a guess.** At most 0.12 s of back-extrapolation from sparse samples, and the ball is rarely
  detected in the hands.
- **Box containment, not hands.** In the paint, several widened boxes contain the release point, including a
  defender's raised arms.
- **iOS shooter = last holder** by nearest box centre, so a defender standing next to the ball can win.
- **Track ids are not people.** Without ReID, an id switch strands the shot on a new id that has no number.
- **Jersey OCR almost never sets a number.** Crops are spread over the track's life, the OCR is generic, numbers aren't
  limited to a roster, and boxes under 60 px are skipped.
- **Team rules were written for one game** and confuse referees and spectators with players.

---

## 3. Evaluation set (build before any fix)

### 3.1 How many shots (95% Wilson lower bound must clear 90%)

| True accuracy | Labelled shots needed |
|---|---|
| 97% | about 75 |
| 95% | about 150 |
| 94% | about 200 (≥ 189 correct) |
| 93% | about 400 |
| 92% | about 900 |
| 90% | never |

- Target **300 test shots per metric**, aiming for ≥ 94% observed.
- Split by **game**, with at least 4 test games, and report each game separately.
- Shooter identity: report accuracy over all real attempts (where "unknown" counts as wrong), plus coverage and
  accuracy over the shots the system answers.

### 3.2 Footage to collect

- **Games:** at least 6, from at least 3 gyms and 2 kit-colour pairings: 2 dev games and 4 held-out test games. Expect
  about 80-120 attempts per 40-minute game *(estimate)*.
- **Main camera:** an iPhone at the product position (sideline midpoint, raised tripod), full resolution, 60 fps if
  possible.
- **Reference camera:** a second phone high behind one baseline, recorded with the existing synced multi-cam
  (`MultiCam/Sidecar.swift`). It's a labelling aid and later the multi-cam test.
- **Official score sheet** of each game, as an independent check on makes per player.
- **Consent** as in `docs/PRIVACY.md`. Footage stays on the Mac and the Spark, with no outside APIs.

### 3.3 Labelling

- **Who:** Sammy as main labeller, plus a second labeller who double-labels 20% of shots; settle disagreements with the
  reference camera.
- **Tool:** a static page `vision/qa/label_shots.py` (the same pattern as `shot_sheets.py`) with both videos side by
  side and hotkeys to mark every attempt, **independent of what the system called**.
- **Fields per shot:** `game_id, camera_id, t_release, t_rim, hoop, outcome (made/missed/unclear), rim_contact
  (swish/rim-in/rim-out/airball/blocked/backboard), shot_type, shooter_team, shooter_number, number_legible_main_cam,
  shooter_visible_at_release, occluded_at_release, labeller, note`, plus a per-game `roster.json`.
- **Time:** about 1-2 minutes per shot *(estimate)*.

### 3.4 Keeping it held out

- Freeze `data/eval/manifest.json` with video and label hashes.
- Test games are never used as Spark training sources. Use `HOLDOUT=` in the dataset build, plus a test that fails if
  a test frame appears in `data/spark/dataset`.
- Dev games are for tuning. Test games are scored only at milestone gates, and every score is logged in
  `docs/RESULTS.md`.

### 3.5 Harness (M0)

- `vision/stats/eval_shots.py`: attempt precision and recall, make/miss accuracy on matched attempts, shooter team,
  shooter person (team, number), and coverage. All with Wilson intervals, per-game tables and error categories.
- A **Python/Swift parity runner**: one JSONL of detections per clip, run through `shots.py` and through
  `ShotDetector.swift` in a test harness, comparing the event lists. This keeps live and after-game logic from
  drifting apart.

---

## 4. Candidate fixes, ranked

### 4.1 Make/miss

| # | Fix | Expected gain *(est.)* | Effort | Where |
|---|---|---|---|---|
| **MM1** | **Proof the ball went through.** A crossing inside the central ~60% of the rim **and** ≥ 2 net samples (or 1 sample plus the ball leaving the bottom of the net), moving down with little sideways speed | High (rim-outs) | 1-2 d | Phone + Spark |
| **MM2** | **No re-rise / sideways exit** within 0.6 s after the rim, else the make becomes a miss | High | 0.5 d | Both |
| **MM3** | **Delayed verdict** 0.6-0.8 s after the ball drops below the rim, with a `made_score` 0-1 that drives `made_confirmed` | Medium | 1 d | Both |
| **MM4** | **Hoop hygiene:** nearest hoop in Python; no carried-forward hoop at verdict time; rim line from a short median | Medium | 1 d | Both |
| **MM5** | **Size / depth gate** (KILL_LIST C1) | Low on rim-outs | 0.5 d | Both |
| **MM6** | **Hoop crop at full frame rate** inside the shot window on the phone; dense full-resolution re-detection on the Spark | High (vanished balls, net crossed between samples) | phone 3-4 d, Spark 1-2 d | Both |
| **MM7** | **Rim-crop make/miss classifier:** about 16 frames around the rim, a small temporal CNN with frame differences, trained on the Spark, exported to Core ML (pattern in `ml/spark/export_coreml.py`) | High: likely the step from ~88% to ≥ 94% | 5-8 d | Train on Spark; run on phone + Spark |
| **MM8** | **Net motion** feature (frame difference in the net area) | Medium | 1 d | Both |
| **MM9** | **Calibrated fusion** of rules, classifier and second view | Medium | 1-2 d | Spark |
| **MM10** | **Second phone at the baseline** (multi-cam): removes the depth ambiguity | Highest | 3-5 d | Mostly after game |
| **MM11** | **Scoreboard OCR check** where a scoreboard is visible | Low coverage, high precision | 2-3 d | After game |
| **MM12** | **Detector round 6** with hard rim and in-hand examples (pseudo-labels via `ml/spark/pseudo_label.py`) | Medium | 3-4 d, one Spark run | Spark → phone |
| MM13 | **Local VLM judge** for low-confidence clips, **Spark only** (minors' footage must not go to outside APIs) | Low-medium | 2 d | After game |

**MM7 data:** dev pilot games, game10, broadcast footage with play-by-play make/miss labels
(`docs/ML_DATA_PLAN.md`, `ml/fetch_playbyplay.py`), public clip datasets if any exist (not verified), and later user
corrections. It needs about 1,000+ clips *(estimate)* before it can be trusted on its own; until then it runs only
inside the MM9 fusion.

### 4.2 Shooter identity

| # | Fix | Expected gain *(est.)* | Effort | Where |
|---|---|---|---|---|
| **SH0** | **Person-level eval** (team, number); re-judge the 7 changed attributions | Measurement only (required) | 1 d | Mac |
| **SH1** | **Pose-based last touch** on the 2-4 players nearest the ball: wrist-to-ball distance before the release, wrists above the head at the release, wrist distance to the release point (replacing box centre) | High | 2-3 d Python, 2-3 d phone | Phone: Apple Vision body pose; Spark: ViTPose / YOLO11-pose |
| **SH2** | **Phone shooter = SH1 release score** instead of the last holder | High (live) | in SH1 | Phone |
| **SH3** | **Roster-limited jersey OCR around the release** (−1.5 to +1.0 s), with a pre-game roster screen; on the Spark, a fine-tuned digit recogniser | High where numbers are legible | phone 2 d, Spark 4-6 d | Both |
| **SH4** | **Per-game team set-up:** tap one Home and one Away player, fit colour centroids, exclude referees (referee class mAP50 0.950) | Medium-high (team 77% → ≥ 90%) | 2 d | Both |
| **SH5** | **ReID + merge by (team, number)** in the Spark re-process | Medium-high | 2-3 d | Spark |
| **SH6** | **Dense full-resolution ball backtracking** around each shot | Medium | 2-4 d | Spark |
| **SH7** | **Multi-cam fusion** (the baseline view sees fronts and numbers) | High where present | in MM10 | Mostly after game |
| SH8 | **Free-throw shortcut** from the court homography | Small, certain | 0.5 d | Both |

---

## 5. Live on the phone versus after the game on the Spark

| Layer | Phone (live, Core ML) | Spark (after the game, via NVIDIA Sync) |
|---|---|---|
| Detection | Round 5 mini at 10-15 fps, plus a hoop crop at camera rate inside shot windows | Full resolution, every frame, newest detector |
| Make/miss | MM1-MM5 + MM8; MM7 once it proves itself | Dense rules + full MM7 + MM9 fusion + MM10 + MM11 + MM13 |
| Shooter | SH1/SH2 (Apple Vision pose), SH3 roster OCR, SH4 | ViTPose, jersey recogniser, SH5 ReID, SH6, SH7 |
| What the user sees | Provisional call within ~1 s, with a confidence colour and one-tap fix | A **final report** that replaces the provisional one and shows what changed |

**How results come back to the app** (to build in M5; `ingest/` from CLAUDE.md isn't in this checkout):

1. The phone writes the clip, its sidecar, `<clip>.events.json` and `<clip>.corrections.json`.
2. The Mac pushes the clip to the Spark via NVIDIA Sync.
3. The Spark runs one queued job per game and writes `report.json`.
4. The Mac pulls the report back and AirDrops it to the phone; the app imports it, keeping user corrections over model
   output.

A server upload can replace steps 2-4 later. Turnaround is minutes to under an hour per game *(estimate, measure in
M4)*.

---

## 6. Human in the loop

- **Correction UI** in `GameReportView`, as a shot list:
  - tap flips made/miss (wire up `setPoints`);
  - long-press picks the shooter from the top 3 or the roster;
  - swipe deletes a non-shot;
  - "+ missed shot" adds an attempt.
  - Low-confidence shots get a small non-blocking chip during play ("#12 Home, made?").
- **Corrections become training data:** append `{shot_id, t_video, field, old, new, model_version, ts, who}` to
  `<clip>.corrections.json`. They train MM7, SH3 and detector round 6, but **never go into the test set**.
- **Correction rate per 100 shots** is a running health metric on the dashboard; a jump means drift (new gym, new
  kit).

---

## 7. Milestones

| # | Milestone | Exit criteria | Effort *(est.)* |
|---|---|---|---|
| **M0** | Eval harness, SH0, parity runner, game10 re-scored | game10 baseline reproduced with intervals; parity differences listed | 2-3 d |
| **M1** | 6 pilot games recorded (main + baseline phone) and labelled, manifest frozen, leak test added | ≥ 300 test + ~200 dev attempts labelled; labeller agreement measured | 3-4 d + labelling; **2-4 weeks calendar** |
| **M2** | Make/miss rules v2 in Python **and** Swift (MM1-MM5, MM8) | Dev make/miss ≥ 88%; attempt precision ≥ 95%; parity ≥ 98% | 3-5 d |
| **M3** | Shooter v2, after game (SH1, SH3, SH4, SH8) | Dev shooter team ≥ 90%; person ≥ 75% with coverage | 4-6 d |
| **M4** | Spark after-game pipeline (dense re-process, ViTPose, ReID, MM7 v1, MM9, MM11); `ml/spark/SETUP.md` updated to "via NVIDIA Sync" | **Test gate:** make/miss lower bound ≥ 90%; shooter team lower bound ≥ 90%; person ≥ 85% with coverage | 8-12 d |
| **M5** | App: correction UI + log, low-confidence chips, roster and team taps, Apple Vision pose, hoop crop, report import | Live make/miss ≥ 88%, ≥ 95% after corrections at ≤ 1 tap per 10 shots; no frame-rate or thermal loss over 40 min | 8-10 d |
| **M6** | Multi-cam fusion | After-game make/miss lower bound ≥ 95% (stretch); person ≥ 90% on multi-cam games | 4-6 d |
| **M7** | Keep it there: CI on frozen fixtures, a 50-shot sample per new game, rolling test pool, correction-rate dashboard, quarterly Spark retrains | Each release logs its test numbers in `docs/RESULTS.md` | ~1 d per game |

**Order:**
- M0 and M1 start now; pilot games set the pace.
- M2 and the M5 correction UI can run in parallel, since they need no new data.
- M3 needs dev labels; M4 needs the test set; M6 needs the baseline-phone footage.
- Total: about 32-46 engineering days plus 2-4 weeks of recording *(estimate)*.

**Spark rules:** one job at a time (a detector round, MM7 training, or a game re-process), queued one after another.
Start each through NVIDIA Sync, check `results.csv` or a done-marker once at the expected end, and pull artefacts back
with NVIDIA Sync.

---

## 8. Risks and fallbacks

| Risk | Effect | Fallback |
|---|---|---|
| Jersey numbers unreadable from one sideline phone | Person-level ≥ 90% may be unreachable with one camera | Roster + one-tap top-3 pick; report accuracy over answered shots with coverage; multi-cam; make **shooter team** the hard metric |
| Rim-outs still ambiguous from the side | Make/miss stuck at ~85-90% *(est.)* | MM7 with more data; baseline phone; placement guidance; low-confidence chips |
| Domain gap (broadcast vs pilot gyms) | Dev gains don't carry over | ≥ 3 gyms in test; per-gym table |
| Too little data for MM7 | Overfits | Weak play-by-play labels, corrections; fusion-only until ~1,000 clips |
| Phone compute or heat | Frame rate drops or throttling | Pose and crop only inside shot windows; heavy heads on the Spark only |
| Overfitting the test set | Overstated numbers | Score only at gates; log every score; rotate in fresh test games |
| Spark contention (shared) | Slow experiment loop | Batch work; rules on the Mac; game re-processes overnight |
| Licences (ViTPose, SAM 3.1, VLMs, ultralytics AGPL) | Can't ship a model | Check each first; fall back to Apple Vision pose |
| Privacy (minors' footage) | Legal or trust issue | Own hardware only, no outside APIs, follow `docs/PRIVACY.md`, initials only in training data |
| No back-end round trip yet | No after-game report reaches users | AirDrop round trip first (M5), a server later |

### Critical files
- `vision/stats/shots.py`, `app/FollowCamApp/Game/ShotDetector.swift`
- `vision/stats/eval_human.py` (+ new `eval_shots.py`, `vision/qa/label_shots.py`)
- `vision/numbers/read.py`, `app/FollowCamApp/Game/JerseyVotes.swift`, `vision/track/teams.py`
- `app/FollowCamApp/Game/GameStats.swift`, `app/FollowCamApp/Screens/GameReportView.swift`
- `ml/spark/` (training, export, `SETUP.md`)
