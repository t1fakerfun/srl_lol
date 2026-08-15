# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

SRL LoL is a League of Legends "self-regulated learning" reflection coach. Players fill out a
post-match reflection form in a Flutter app; the reflection is scored by Gemini for how
substantive it is (vs. blaming luck/teammates), and only reflections that clear a quality
threshold are persisted. Players can also attach their match recording, which is analyzed
asynchronously (OpenCV) for death/impulse-control events and linked to the reflection as a
separate metric. There's also an unrelated Gemini-backed Socratic coaching chat.

The repo is two independent apps that talk over HTTP on `localhost:5001`:
- `lib/` — Flutter client (all platforms scaffolded, but this is developed as the primary target).
- `backend/` — Flask + Postgres API, including the async video-analysis pipeline.

## Commands

### Flutter app (root directory)
- `flutter pub get` — install/sync dependencies.
- `flutter run` — run the app (pick a device/simulator when prompted).
- `flutter analyze` — static analysis (uses `flutter_lints` via `analysis_options.yaml`).
- `flutter test` — run tests (the `test/` directory is currently empty).
- `dart run build_runner build --delete-conflicting-outputs` — regenerate `*.g.dart` Riverpod
  code after editing any `@riverpod`/`@Riverpod`-annotated class (e.g. after touching
  `lib/chat_controller.dart`).
- The app loads secrets from a root-level `.env` (via `flutter_dotenv`, declared as an asset in
  `pubspec.yaml`). It must contain `API_KEY` (Gemini API key) or the chat model fails to load.

### Backend (`backend/`)
- `docker-compose up --build` — starts the Flask API (`app`, port 5001, `threaded=True` so
  status-polling requests aren't blocked by an in-flight video analysis) and a Postgres 15
  container (`db`), per `docker-compose.yml`. Two named volumes (`video_uploads`,
  `video_highlights`) persist uploaded videos and generated highlight clips outside the
  bind-mounted repo tree.
- To run the API without Docker: `pip install -r requirements.txt` (includes
  `opencv-python-headless`/`moviepy`/`numpy`/`imageio-ffmpeg` for video analysis — also needs
  system `ffmpeg` on PATH), ensure a Postgres instance matching `DB_CONFIG` in `database.py`
  (host `db`, db `srl_database`, user/pass `srl_user`/`srl_password`) is reachable, then
  `python database.py`. `init_db()` creates `approved_reflections` and `video_analysis_jobs`
  on startup, and `ALTER TABLE ... ADD COLUMN IF NOT EXISTS` handles the one column added later
  (`video_job_id`) — this `ADD COLUMN IF NOT EXISTS` pattern is how this repo does idempotent
  schema migrations without a framework; follow it for future schema changes to existing tables.
- Backend secrets live in `backend/.env` (`API_KEY` for Gemini, loaded via `python-dotenv` in
  `quantificate.py`).
- No test suite or lint config exists for the backend.

### Known inconsistencies (don't "fix" silently — confirm with the user first)
- `quantificate.py`'s `keyword_analysis()` reads `data/beginner.txt`, but the sample file is at
  `backend/beginner.txt` (no `data/` subdirectory exists) — that endpoint will raise `FileNotFoundError` as-is.
- `lib/helpers/database_helper.dart` (sqflite, local `reflections.db`) is defined but not
  referenced anywhere else in `lib/` — all reflection persistence actually goes through the Flask
  API, not local SQLite.
- `backend/map_vision.py` is an older, simpler standalone precursor to `video_analysis.py`
  (minimap enemy-proximity detection only, no death detection, prints to stdout). It's untracked,
  not imported anywhere, and safe to delete — kept around only because no one has removed it yet.

## Architecture

### Data flow: reflection submission
1. `lib/screens/self_learning.dart` collects a multi-step reflection (target type, routine score,
   monitored metrics, failure categories, judgment logic, lesson learned) via a `Stepper` UI, then
   `POST`s it as JSON to `http://127.0.0.1:5001/api/reflection` (hardcoded `backendUrl`, shared by
   `report_db.dart` for the GET side).
2. `backend/database.py`'s `handle_reflection()` receives it, calls
   `quantificate.ai_analysis(lesson_learned)`, which prompts Gemini (`google-genai` client) to
   return a 0.0–5.0 "SRL score" (low = blames luck/teammates, high = concrete actionable
   analysis) as the last line of its response.
3. Only if `srl_score >= 3.0` is the reflection inserted into Postgres' `approved_reflections`
   table; otherwise the API returns 400 and the Flutter UI shows a "try again" message. Rejected
   reflections are not stored anywhere. If a video was attached (see below), its `videoJobId` is
   stored alongside on insert — but it plays no part in the `srl_score`/threshold decision.
4. `lib/screens/report_db.dart` fetches `GET /api/reflections` and lists approved reflections,
   each with a `video_status`/`video_result` pair (both `null` if no video was attached).

**Field-name mapping is manual and asymmetric**: the Flutter side sends camelCase
(`targetType`, `routineScore`, `judgementLogic`) but `database.py` stores/returns snake_case
columns (`target_type`, `routine_score`, `judgment_logic`) and remaps again to the UI's expected
keys (`topic`, `content`, `date`) in `get_reflections()`. When adding a new reflection field, it
must be threaded through all three representations by hand.

### Video analysis pipeline (async job, separate metric from `srl_score`)
Uploading a match video and scoring reflection text are two independent flows that only meet at
the very end via a foreign key. This split exists because frame-by-frame OpenCV/moviepy analysis
of a GB-scale video is too slow to do inside a request/response cycle.
1. `self_learning.dart`'s `_pickFile()` uploads the picked video immediately (Step 0 of the
   `Stepper`, well before the user finishes the form) via multipart `POST /api/video_analysis`.
   `database.py`'s `handle_video_upload()` saves it via `video_storage.save_upload()`, creates a
   `video_analysis_jobs` row (`status='pending'`), and hands it to `video_jobs.submit_job()`,
   which runs it on a module-level `ThreadPoolExecutor(max_workers=2)` — returns `202` immediately.
2. `video_jobs._run_job()` opens its own DB connection (psycopg2 connections aren't thread-safe
   to share) and calls `video_analysis.analyze()`, which detects `DEATH` events by tracking a
   hardcoded HP-bar HSV color region and classifies each as `IMPULSE_MISSED` (an enemy appeared
   on the minimap within 15s beforehand) or `NORMAL_DEATH`, then cuts ±10-15s highlight clips
   around each event via moviepy. The job row is updated to `status='done'` with a `result` jsonb
   blob (`death_count`, `impulse_missed_count`, `impulse_control_failure_ratio`, `highlight_refs`),
   or `status='error'` with `error_message` if anything raises.
3. Meanwhile, `self_learning.dart` polls `GET /api/video_analysis/<job_id>` every ~5s and shows
   a live status indicator; the resulting `job_id` is only threaded into `POST /api/reflection`
   as `videoJobId` when the user finally submits the form (steps 2-4 of `Stepper`), so an
   uploaded-but-never-submitted video leaves an orphaned job row — there's no cleanup job for
   this yet.
4. `video_storage.py` is the only module that knows uploads/highlights live on local disk
   (`VIDEO_UPLOAD_DIR`/`VIDEO_HIGHLIGHT_DIR` env vars, backed by the `video_uploads`/
   `video_highlights` Docker volumes). Everything else only ever passes around opaque ref
   strings — this is the intended seam for swapping in S3 later without touching callers.
   `video_jobs.py`'s `ThreadPoolExecutor`-based orchestration is a similar seam: a future
   AWS-backed version would replace `submit_job()`'s body with an SQS `send_message` and run
   `_run_job()`'s logic in a Lambda instead, without changing `create_job`/`get_job`/the schema.

**Fixed-resolution assumption**: the HP-bar/minimap ROI coordinates in `video_analysis.py` were
manually calibrated (via the sibling project's `get_coords.py`, a GUI tool that can't run
headless) against one specific recording — 1280x720 @ 60fps. `analyze()` checks the uploaded
video's actual resolution first and raises `UnsupportedResolutionError` (surfaced as
`status='error'`) on any mismatch, rather than silently running detection with meaningless
coordinates. There is no per-resolution calibration flow yet — this is a known scope limit, not
a bug to "fix" by guessing at new coordinates.

### Gemini chat coaching
`lib/chat_controller.dart` defines two Riverpod providers:
- `GeminiController.loadModel()` builds a `GenerativeModel` (`gemini-2.5-flash`) with a large
  hardcoded Japanese system prompt implementing a Socratic-coaching persona — it must never
  give players the "correct" play directly, only ask questions that push them from
  "what button did I press wrong" toward "what judgment rule led me there" (framed around 5
  cognitive-demand categories: initiation, attention allocation, suppression/improvisation,
  commitment, heuristics). Edit this prompt with care — it encodes the product's core coaching
  philosophy, not incidental copy.
- `ChatController` owns a single `ChatSession` for the app's lifetime and appends messages to
  Riverpod state; `lib/screens/gemini_chat.dart` renders it with `flutter_chat_ui`.
- This chat is independent of the reflection-scoring flow in `quantificate.py` — both call
  Gemini but for different purposes (interactive coaching vs. one-shot scoring) and neither
  shares code with the other.

### Flutter app shell
`lib/main.dart` loads `.env`, wraps everything in a Riverpod `ProviderScope`, and hosts four
screens behind a fixed `BottomNavigationBar` (`self_learning.dart` → `gemini_chat.dart` →
`User_config.dart` → `report_db.dart`). `User_config.dart` stores Riot ID/region/rank in
`shared_preferences` purely client-side; it's not sent to or used by the backend anywhere yet.
