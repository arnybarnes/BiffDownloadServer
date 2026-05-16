# AI Subtitle Progress Plan

## Goal

Improve the Apple TV AI subtitle flow so the user can see these stages clearly:

1. Audio is being extracted
2. Audio is being uploaded
3. AI is generating subtitles
4. `.srt` is being downloaded/received
5. New video file is being merged/muxed

The current flow is functional but too opaque. `POST /api/v1/subtitles/generate` blocks until everything is finished, so the Apple TV app can only show a generic loading state.

## Current Execution Status

Implemented:

- Phase 1 async job endpoints on the Windows API
- Apple TV polling UI for AI subtitle jobs
- Weighted overall job progress
- Real extraction progress from `ffmpeg`
- Real upload progress from bytes sent
- Real mux progress when `mkvmerge` emits progress lines
- Apple TV stage timeline showing completed, active, pending, and failed stages
- `transcribing` intentionally uses elapsed time on Apple TV instead of a fake percentage

Deferred optional work:

- True transcription progress from the Mac helper during the `transcribing` stage
- A Mac-side job API or chunked transcription flow if we later decide elapsed time is not sufficient

## Current State

### Apple TV app

- The AI tab lets the user pick a video and trigger subtitle generation.
- The app uses the async job flow instead of waiting on one blocking request.
- The app shows a progress card with:
  - current stage
  - weighted overall progress
  - stage detail text
  - elapsed time
  - a stage timeline
- During `transcribing`, the app deliberately shows elapsed time instead of a made-up percentage.

### Windows API

- The Windows API now supports:
  - `POST /api/v1/subtitles/generate/jobs`
  - `GET /api/v1/subtitles/generate/jobs/{jobId}`
- The Windows API runs the full subtitle job in a background thread:
  - extract audio with `ffmpeg`
  - send audio to the Mac helper
  - receive generated SRT text
  - save `{stem}.generated.srt`
  - mux `{stem}_generated_subs{ext}`
- The job payload exposes:
  - `state`
  - `activeStage`
  - `progressPercent`
  - `stageProgressPercent`
  - `detail`
  - timestamps, error state, and result paths
- Real measured progress is available for extraction, upload, and muxing.
- `transcribing` remains a coarse in-progress state because the Mac helper is still one-shot.

### Mac helper

- The Mac helper currently accepts one audio upload and returns one final JSON response.
- It does not expose job progress yet.
- For this pass, that is acceptable because the Apple TV app shows elapsed time while the helper is working.

## Recommended Architecture

Do not replace the current synchronous endpoint immediately.

Keep:

- `POST /api/v1/subtitles/generate`

Add a new async job-based flow for the Apple TV app:

- `POST /api/v1/subtitles/generate/jobs`
- `GET /api/v1/subtitles/generate/jobs/{jobId}`

This avoids breaking the existing tester and any current clients. The old endpoint can remain as a compatibility wrapper for now.

## Proposed User Experience

### AI tab behavior

After the user selects a video and starts generation:

- Replace the single spinner with a progress card
- Show the current stage label in large text
- Show an overall progress bar
- Show stage detail text under it
- Show elapsed time
- Show success/failure state at the end

### Stage list

Recommended server job states:

1. `queued`
2. `extracting_audio`
3. `uploading_audio`
4. `transcribing`
5. `receiving_srt`
6. `muxing`
7. `completed`
8. `failed`

Recommended user-facing labels:

- `Queued`
- `Extracting audio`
- `Uploading audio to Mac`
- `Generating subtitles`
- `Receiving subtitle file`
- `Merging into new video`
- `Completed`
- `Failed`

## API Plan

### 1. Create a generate job endpoint

Add:

`POST /api/v1/subtitles/generate/jobs`

Request body:

```json
{
  "videoPath": "From-season4\\s04e01.mkv",
  "language": "en"
}
```

Response:

```json
{
  "status": "accepted",
  "job": {
    "id": "subgen_20260516_001",
    "state": "queued",
    "progressPercent": 0,
    "videoPath": "From-season4\\s04e01.mkv",
    "startedAt": "2026-05-16T02:10:00Z"
  }
}
```

### 2. Create a poll endpoint

Add:

`GET /api/v1/subtitles/generate/jobs/{jobId}`

Response shape:

```json
{
  "status": "ok",
  "job": {
    "id": "subgen_20260516_001",
    "state": "uploading_audio",
    "stageLabel": "Uploading audio to Mac",
    "progressPercent": 24,
    "stageProgressPercent": 62,
    "detail": "8.1 MB of 13.0 MB sent",
    "videoPath": "From-season4\\s04e01.mkv",
    "subtitlePath": null,
    "outputPath": null,
    "startedAt": "2026-05-16T02:10:00Z",
    "updatedAt": "2026-05-16T02:10:11Z",
    "error": null
  }
}
```

### 3. Preserve the existing sync route

Keep:

- `POST /api/v1/subtitles/generate`

Options:

- Leave it as-is for the HTML tester and older clients
- Or later make it internally create a job and wait for completion before returning

## Windows API Work

### Job manager

Add an in-memory job registry in `app.py`:

- keyed by `jobId`
- stores current state, timestamps, progress, detail text, result paths, and error
- expires old jobs after a reasonable window, for example 1 hour

### Background execution

When `POST /api/v1/subtitles/generate/jobs` is called:

- validate request
- create a job record
- return immediately
- perform work in a background thread

### Stage instrumentation

#### Audio extraction

Current tool:

- `ffmpeg`

Recommended progress source:

- run `ffmpeg` with `-progress pipe:1`
- get source duration from `ffprobe`
- compute `stageProgressPercent` from extracted time vs total duration

#### Audio upload

Current limitation:

- the current code posts the whole audio blob in one call

Recommended change:

- stream the request body in chunks
- update progress as bytes sent / total bytes

Implementation note:

- `urllib` is awkward for upload progress
- switching this one call to `requests` or `http.client` with manual chunking will likely be simpler

#### AI generation

This is the hardest stage.

Current decision:

- keep the Mac helper one-shot for now
- show `transcribing` as an active stage with elapsed time on Apple TV
- do not invent a percentage for this stage

Optional future upgrades:

- if MLX Whisper exposes usable progress, surface it directly
- otherwise split the extracted audio into chunks and report progress by processed duration

#### `.srt` receiving

Important note:

- with the current one-shot helper response, this stage will usually be very short

Still useful:

- explicitly switch from `transcribing` to `receiving_srt`
- show it even if it lasts less than a second

If we want real measurable progress later:

- move the Mac helper to its own job API
- have the Windows API fetch the final result from a separate result endpoint

#### Video muxing

Current tools:

- `.mkv`: `mkvmerge`
- `.mp4`: `ffmpeg`

Recommended progress source:

- for `.mp4`, parse `ffmpeg -progress pipe:1`
- for `.mkv`, parse `mkvmerge` progress output if reliable
- if `mkvmerge` progress parsing is messy, start with a stage spinner and elapsed time only

## Mac Helper Work

### Minimum version

This is the current implementation.

- The Windows API uploads one extracted audio file.
- The Mac helper returns one final JSON response with SRT text.
- No Mac-side job API is required for the current user experience.

### Better version

Add Mac-side transcription jobs:

- `POST /api/v1/transcriptions/jobs`
- `GET /api/v1/transcriptions/jobs/{jobId}`
- `GET /api/v1/transcriptions/jobs/{jobId}/result`

Benefits:

- real transcription progress becomes much easier to expose
- the Windows API can poll the Mac instead of blocking
- the Apple TV user gets a more believable `Generating subtitles` stage

Status:

- deferred
- not required for the current pass because elapsed time is the accepted fallback for `transcribing`

## Apple TV App Work

### View model changes

Add job-based polling to `AIViewModel`:

- start the async generate job
- store `jobId`
- poll every 0.5 to 1.0 seconds while the job is active
- stop polling on `completed` or `failed`

Published properties to add:

- `jobID`
- `jobState`
- `jobStageLabel`
- `progressPercent`
- `stageProgressPercent`
- `jobDetail`
- `jobStartedAt`
- `jobUpdatedAt`
- `isPollingJob`

### UI changes

Add a dedicated progress card in `AIView`:

- headline with current stage
- progress bar
- secondary detail line
- elapsed time
- maybe a small list of completed stages with checkmarks

Keep:

- existing file selection UI
- existing result summary panel

### Failure UX

On failure:

- show the stage where it failed
- show the server error text
- keep the selected video intact so the user can retry immediately

## Progress Semantics

### Overall progress

Use weighted overall progress, not equal stage counts.

Suggested starting weights:

- `extracting_audio`: 15%
- `uploading_audio`: 15%
- `transcribing`: 45%
- `receiving_srt`: 5%
- `muxing`: 20%

This will feel more honest than a five-step equal bar.

Important rule:

- `transcribing` should not display a fake live percentage on Apple TV when the backend cannot measure it
- during that stage, the UI should show elapsed time and the current stage label instead

### Stage detail examples

- `Extracting audio: 00:42 of 02:31`
- `Uploading audio: 8.1 MB of 13.0 MB`
- `Generating subtitles: processing audio on Mac`
- `AI elapsed 1:32`
- `Receiving subtitle file: finalizing SRT`
- `Merging into new video: 61%`

## Rollout Plan

### Phase 1

Status: complete

Deliverables:

- new Windows API job endpoints
- Apple TV polling UI
- visible stage transitions
- final success/failure states

Tradeoff:

- `transcribing` will likely be indeterminate at first

### Phase 2

Status: complete

Deliverables:

- `ffmpeg` extraction progress
- upload byte progress
- mux progress where tools support it

### Phase 3

Status: deferred optional work

Chosen fallback:

- keep `transcribing` elapsed-time-based on Apple TV
- revisit only if we later decide true AI progress is worth the added backend complexity

## Non-Goals

For this pass, do not:

- change the legacy subtitle download endpoint behavior
- remove the current synchronous generate endpoint
- redesign the file picker
- add auth or multi-user job persistence

## Acceptance Criteria

Status: met for this pass

The work is done when:

1. The Apple TV app shows at least the five requested stages during AI subtitle generation
2. The app no longer looks frozen during long subtitle jobs
3. The user sees clear success or failure without leaving the AI tab
4. Existing subtitle download/merge flows still work unchanged
5. Existing `POST /api/v1/subtitles/generate` clients continue to function

## Optional Future Work

1. Check whether a future MLX Whisper update exposes usable progress callbacks.
2. If not, evaluate chunked transcription on the Mac helper only if elapsed time proves insufficient in real use.
3. Leave the current async job model and Apple TV stage UI in place either way.
