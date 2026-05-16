# AI Subtitle Progress Plan

## Goal

Improve the Apple TV AI subtitle flow so the user can see these stages clearly:

1. Audio is being extracted
2. Audio is being uploaded
3. AI is generating subtitles
4. `.srt` is being downloaded/received
5. New video file is being merged/muxed

The current flow is functional but too opaque. `POST /api/v1/subtitles/generate` blocks until everything is finished, so the Apple TV app can only show a generic loading state.

## Current State

### Apple TV app

- The AI tab already lets the user pick a video and trigger subtitle generation.
- The app currently waits for one final response from `POST /api/v1/subtitles/generate`.
- There is no stage-by-stage feedback yet.

### Windows API

- The Windows API currently performs the whole generate flow inside one request:
  - extract audio with `ffmpeg`
  - send audio to the Mac helper
  - receive generated SRT text
  - save `{stem}.generated.srt`
  - mux `{stem}_generated_subs{ext}`
- This makes fine-grained progress hard to expose to the Apple TV client.

### Mac helper

- The Mac helper currently accepts one audio upload and returns one final JSON response.
- It does not expose job progress yet.

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

Best-case option:

- MLX Whisper exposes a callable API or callback with progress we can observe directly

Fallback option:

- split the extracted audio into time chunks
- transcribe chunk-by-chunk on the Mac helper
- update progress from completed audio duration / total audio duration
- merge and re-time SRT segments at the end

Recommendation:

- build the job flow first with coarse `transcribing` status
- then evaluate whether MLX Whisper can provide real progress
- if not, move to chunk-based transcription for deterministic progress

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

For phase 1, the Mac helper does not need a new endpoint if the Windows API keeps sending one upload and waiting for one final result.

### Better version

Add Mac-side transcription jobs:

- `POST /api/v1/transcriptions/jobs`
- `GET /api/v1/transcriptions/jobs/{jobId}`
- `GET /api/v1/transcriptions/jobs/{jobId}/result`

Benefits:

- real transcription progress becomes much easier to expose
- the Windows API can poll the Mac instead of blocking
- the Apple TV user gets a more believable `Generating subtitles` stage

Recommendation:

- do not require this for phase 1
- likely require this for accurate phase 2 or phase 3 progress

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

### Stage detail examples

- `Extracting audio: 00:42 of 02:31`
- `Uploading audio: 8.1 MB of 13.0 MB`
- `Generating subtitles: processing audio on Mac`
- `Receiving subtitle file: finalizing SRT`
- `Merging into new video: 61%`

## Rollout Plan

### Phase 1

Add async jobs and coarse stage changes.

Deliverables:

- new Windows API job endpoints
- Apple TV polling UI
- visible stage transitions
- final success/failure states

Tradeoff:

- `transcribing` will likely be indeterminate at first

### Phase 2

Add real progress for extraction, upload, and muxing.

Deliverables:

- `ffmpeg` extraction progress
- upload byte progress
- mux progress where tools support it

### Phase 3

Improve transcription progress.

Deliverables:

- direct MLX progress if available
- otherwise chunk-based transcription progress on the Mac helper

## Non-Goals

For this pass, do not:

- change the legacy subtitle download endpoint behavior
- remove the current synchronous generate endpoint
- redesign the file picker
- add auth or multi-user job persistence

## Acceptance Criteria

The work is done when:

1. The Apple TV app shows at least the five requested stages during AI subtitle generation
2. The app no longer looks frozen during long subtitle jobs
3. The user sees clear success or failure without leaving the AI tab
4. Existing subtitle download/merge flows still work unchanged
5. Existing `POST /api/v1/subtitles/generate` clients continue to function

## Recommended Execution Order

1. Build Windows API async job endpoints
2. Wire Apple TV polling UI to the new job model
3. Add extraction progress
4. Add upload progress
5. Add mux progress
6. Evaluate MLX transcription progress capability
7. If needed, redesign Mac helper transcription as chunked or job-based
