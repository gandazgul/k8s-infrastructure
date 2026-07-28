---
planId: "498db2dd-2ed6-4ecb-8f25-a6222b8cacfa"
classification: "PLANNED_CHANGE"
workKind: "FEATURE"
complexity: "MEDIUM"
summary: "Add a book ingestion CronJob that submits torrent files to Transmission and copy-only imports completed book downloads into Audiobookshelf's Books library."
affectedPaths:
    - "containers/book-ingest/"
    - "clusters/gandazgul/apps/BookIngestCronJob.yaml"
    - "clusters/gandazgul/apps/kustomization.yaml"
    - "CONTEXT.md"
executionAgent: "engineer"
collaborationRecommendation: "autonomous"
createdAt: "2026-07-27T22:01:05-04:00"
updatedAt: "2026-07-28T03:06:55.169Z"
status: "verified"
origin: "internal"
implementedAt: "2026-07-28T02:52:06.221Z"
verifiedAt: "2026-07-28T03:06:47.813Z"
userVerifiedAt: null
executionReport: "- Implemented `containers/book-ingest` Node ESM CronJob container with Transmission RPC session-id retry, torrent inbox/archive handling, completed `/data/books` discovery, metadata/heuristic classification, `_needs-review` fallback, per-file JSONL import state, archive/temporary skip logging, collision-safe copy behavior, and dry-run support.\n- Added focused unit tests for extension handling, sanitization, metadata confidence/grouping, `_needs-review`, state idempotence, Transmission completion filtering, and collision suffix planning.\n- Added `clusters/gandazgul/apps/BookIngestCronJob.yaml`, included it in `clusters/gandazgul/apps/kustomization.yaml`, and documented stable book-ingest vocabulary/paths in `CONTEXT.md`.\n- Verification passed: `cd containers/book-ingest && npm test` (10 passed); `kustomize build --load-restrictor LoadRestrictionsNone clusters/gandazgul/apps`; `kubectl apply --dry-run=client -f /tmp/book-ingest-kustomize.yaml` (warnings only about existing live resources missing last-applied annotations); local dry-run execution against a mock Transmission RPC copied/planned correctly and exited 0.\n- Repository pre-commit command was attempted: `node scripts/pre-commit.js --all` returned `pre-commit: no staged files to check`.\n- Image build verification partially failed: `node containers/container-build.js --i=book-ingest --force` completed the multi-arch podman build/tag steps, then failed at non-interactive `podman login --username=gandazgul docker.io`; pushing the image and moving to a published pinned tag remain blocked by Docker Hub credentials."
workRecord:
    status: "generated"
    recordId: "f1fb6977-ade0-49de-899d-cb5713c69896"
    path: "docs/work-records/2026-07-28-book-ingest-cronjob-implemented.md"
    lastAttemptAt: "2026-07-28T03:06:48.505Z"
humanReviewMode: "ask"
humanReviewDecision: "approved"
humanReviewedAt: "2026-07-28T03:06:47.713Z"
executionMode: "worktree"
deliveryEvidence:
    version: 1
    mode: "worktree_merge"
    executionCommit: "a4b602d04a91592bed70cbea25d37df8b266f30e"
    targetBranch: "plex-backup"
    targetHeadBeforeMerge: "f09434d3e33a3a514b1452bc62d89f1a497ea7fc"
---

# Implement Book Ingest CronJob

## Context

The current book download workflow is manual: torrent files are manually added to Transmission, the download directory is manually set to `/data/books`, completed files are manually copied from the YASR-backed Transmission books directory (`/media/yasr/configs/transmission/books/`), and files are manually organized under the Audiobookshelf library path (`/media/main/public/Books/`).

The desired outcome is a GitOps-managed ingestion pipeline for the `gandazgul` cluster: drop `.torrent` files into a YASR-backed inbox, have automation add them to Transmission with the books download directory, and periodically copy completed supported book/audio/video files into Audiobookshelf's `Books` library using a conservative best-effort `Author/Book/` layout. Transmission torrents must remain untouched after submission so seeding can continue.

Repository evidence:

- Transmission is deployed as a generic overlay in `apps/generic/overlays/transmission/`; its Service exposes port `9091` as `transmission.default.svc.cluster.local:9091`.
- Transmission mounts `yasr-volume` at `/data` and `/config`, both using `subPath: configs/transmission/`, so `/data/books` inside Transmission corresponds to `/media/yasr/configs/transmission/books/` on the host.
- Audiobookshelf mounts `main-volume` with `AUDIOBOOKSHELF_BOOKS_PATH: "public/Books"` in `clusters/gandazgul/ClusterKustomization.yaml`, so the import destination is `/media/main/public/Books/` on the host.
- Existing custom scheduled jobs are modeled as Flux Kustomizations that instantiate the shared `infrastructure/cronjob/` base from `clusters/gandazgul/apps/*CronJob.yaml`.
- Existing custom container code uses Node.js ECMAScript modules and lives under `containers/`.

## Objective

Build a new `book-ingest` custom container and run it as a Kubernetes CronJob every 10 minutes on the `gandazgul` cluster.

The CronJob will:

- Start quickly and exit quickly when there is no work.
- Scan a YASR-backed torrent inbox for `.torrent` files.
- Add each torrent to Transmission through Transmission remote procedure call (RPC) using `download-dir: /data/books`.
- Archive successfully submitted or duplicate `.torrent` files so they are not retried forever.
- Query Transmission for completed torrents whose download directory is `/data/books`.
- Scan completed torrent content for supported ebook/audio/video files.
- Ignore compressed archives without extraction, logging each ignored archive.
- Copy supported files into `/media/main/public/Books/`, never moving/removing/stopping the source torrent or files.
- Prefer metadata-derived organization, then folder/file-name heuristics.
- Route uncertain imports to `/media/main/public/Books/_needs-review/<torrent-or-folder-name>/`.
- Persist import state per source file so reruns are idempotent while still discovering files that appear later after manual extraction.
- Produce detailed logs explaining every important action and skip decision.

## Approach

Use a standalone Node.js container invoked by the shared CronJob base. This matches the repository's existing container tooling and Flux CronJob pattern while keeping Transmission and Audiobookshelf deployments decoupled.

The container should be implemented as a short-lived `run once` program, not a daemon:

1. Load configuration from environment variables.
2. Ensure inbox/archive/state directories exist.
3. Submit pending `.torrent` files through Transmission RPC.
4. Query completed Transmission torrents under `/data/books`.
5. If no completed book torrents exist, log a summary and exit `0`.
6. For completed torrents, scan only the corresponding YASR paths instead of walking all of `/media/yasr`.
7. Classify and copy supported files not already imported.
8. Write state updates atomically and log a final summary.

Use Transmission's existing RPC protocol for the deployed `linuxserver/transmission:4.0.6` container:

- Endpoint: `http://transmission.default.svc.cluster.local:9091/transmission/rpc`.
- Handle `409` responses by reading `X-Transmission-Session-Id` and retrying the original request.
- Add torrents with `torrent-add` and `arguments.metainfo` containing the base64-encoded `.torrent` file plus `arguments.download-dir: "/data/books"`.
- Query with `torrent-get` fields including `id`, `name`, `hashString`, `downloadDir`, `percentDone`, `files`, and `fileStats`.
- Treat a torrent as import-eligible only when `downloadDir` is `/data/books` or below it and `percentDone >= 1` (with file stats as a defensive fallback).
- Never call `torrent-stop`, `torrent-remove`, `torrent-set-location`, or any mutation other than `torrent-add`.

Use conservative file organization:

- Supported ebook extensions: `.epub`, `.mobi`, `.azw`, `.azw3`, `.pdf`.
- Supported audiobook/media extensions: `.mp3`, `.m4a`, `.m4b`, `.mp4`, `.flac`, `.ogg`, `.opus`, `.wav`, `.aac`.
- Ignored compressed/archive extensions: `.zip`, `.rar`, `.7z`, `.tar`, `.tgz`, `.tar.gz`, `.gz`, `.bz2`, `.xz`.
- Ignore temporary/partial files such as hidden files, `.part`, `.tmp`, and files with zero bytes.
- Extract metadata before relying on names:
  - For ebooks, try Calibre `ebook-meta` first, then ExifTool JSON fallback.
  - For audio/video, try ExifTool JSON first and optionally `ffprobe` fallback when ExifTool has no usable album/title/artist fields.
- Use metadata confidently only when it yields usable author and book/title values without conflicts across files in the same book candidate.
- For audiobook tracks, prefer `AlbumArtist`/`Artist`/`Author` for author and `Album` for book title; do not use per-track `Title` as the book title unless there is only one file and no album is present.
- If metadata is missing/conflicting, try simple folder-name heuristics, for example `Author - Book`, `Author/Book`, or a completed torrent folder already shaped as `Author/Book`.
- If confidence is still low, copy into `_needs-review/<safe torrent-or-folder-name>/`.
- Sanitize all generated path segments: strip path separators/control characters, trim whitespace, collapse repeated spaces, reserve safe fallback names, and avoid path traversal.

Persist state under the YASR-backed config area, for example `/media/yasr/configs/book-ingest/state/imported-files.jsonl` mounted as `/state/imported-files.jsonl` in the job. Record one entry per imported source file with enough information to detect reruns and later manual extraction:

- Transmission `hashString` when available.
- Torrent name.
- Source absolute path inside the container.
- Source relative path within the torrent.
- File size.
- File modified time.
- Destination path.
- Timestamp imported.

Use atomic state writes: write to a temporary file and rename, or append JSON lines only after a successful copy. If a source file changes after import, treat it as a new version only when size or modified time changes; avoid duplicate destination overwrites unless content appears identical.

Implement copy behavior with safety first:

- Create destination directories as needed.
- If destination path does not exist, copy the file and preserve timestamps when possible.
- If destination path exists with the same size, log `already present` and mark/keep state without recopying.
- If destination path exists with a different size, do not overwrite; copy with a collision suffix such as `filename (source-hash-short).ext` or route the whole candidate to `_needs-review`, logging the collision.
- Do not delete source files or destination files.

## Files to Modify

- `containers/book-ingest/package.json` — define the private Node.js ESM package for the ingestion container; keep dependencies minimal and prefer native Node APIs.
- `containers/book-ingest/Dockerfile` — build the runtime image, likely from `node:24-bookworm-slim`, installing metadata CLIs such as `calibre`, `libimage-exiftool-perl`, and `ffmpeg`/`ffprobe` with `--no-install-recommends` where possible.
- `containers/book-ingest/app.js` — entry point that loads configuration, coordinates torrent submission, completed torrent discovery, scanning, classification, copying, state, and summary logging.
- `containers/book-ingest/lib/config.js` — configuration defaults and validation for paths, Transmission RPC URL, supported/ignored extensions, and dry-run/test flags.
- `containers/book-ingest/lib/transmission.js` — Transmission RPC client with session-id retry handling, `torrent-add`, and completed book torrent query functions.
- `containers/book-ingest/lib/metadata.js` — metadata extraction adapters around `ebook-meta`, `exiftool`, and optional `ffprobe`, with timeouts and fail-soft parsing.
- `containers/book-ingest/lib/classify.js` — confidence rules for metadata/folder heuristics and `_needs-review` routing.
- `containers/book-ingest/lib/import-state.js` — imported-file state loading, matching, and atomic persistence.
- `containers/book-ingest/lib/files.js` — filesystem scanning, archive/temporary-file detection, path sanitization, collision-safe copy helpers, and candidate grouping.
- `containers/book-ingest/*.test.js` or `containers/book-ingest/test/*.test.js` — focused unit tests for pure logic: path sanitization, supported/ignored extension classification, metadata confidence, destination planning, collision behavior, and state matching.
- `clusters/gandazgul/apps/BookIngestCronJob.yaml` — Flux Kustomization that instantiates `infrastructure/cronjob/` with the `book-ingest` image, 10-minute schedule, YASR/main-volume mounts, environment variables, security context, resources, deadline/backoff policy, and optional image pull policy patch.
- `clusters/gandazgul/apps/kustomization.yaml` — include `./BookIngestCronJob.yaml` in the `gandazgul` app resource list.
- `CONTEXT.md` — document the new book ingestion component and its stable vocabulary: torrent inbox, copy-only import, `_needs-review`, YASR source path, and Audiobookshelf destination path.

## Reuse Opportunities

Existing functions, modules, or patterns to reuse:

- `infrastructure/cronjob/cronjob.yaml` — reuse the shared CronJob base rather than creating a bespoke CronJob manifest.
- `clusters/gandazgul/apps/ImmichBackupCronJob.yaml` — reuse the Flux Kustomization + volume patching pattern for a custom image running in `default`.
- `clusters/gandazgul/apps/RsyncCronJobs.yaml` — reuse the established pattern for mounting `main-volume` into scheduled copy/sync jobs.
- `containers/container-build.js` — build and push the new image using the existing repository tool (`node containers/container-build.js --i=book-ingest`, based on current script behavior).
- `containers/immich-backup/app.js` — follow existing Node.js ESM style, explicit logging, and `process.exit(1)` on fatal errors.
- `apps/generic/overlays/transmission/patches/service.yaml` — use the existing Transmission Service on port `9091` instead of changing Transmission networking.
- `apps/generic/overlays/transmission/patches/deployment.yaml` — rely on the existing `/data` mount backed by `configs/transmission/`; no Transmission Deployment mutation should be needed for v1.
- `apps/generic/overlays/audiobookshelf/patches/deployment.yaml` and `clusters/gandazgul/ClusterKustomization.yaml` — align the import destination with the current Audiobookshelf `main-volume` `public/Books` mount.

## Implementation Steps

- [ ] Create `containers/book-ingest/package.json` with `type: "module"`, a `start` script such as `node app.js`, and a `test` script using Node's built-in test runner.
- [ ] Create `containers/book-ingest/Dockerfile` from a Node 24 Debian slim base; install `calibre`, `libimage-exiftool-perl`, `ffmpeg`, and `ca-certificates`; copy package files and source; run as a non-root UID/GID compatible with the existing `1000:1000` storage convention if the installed tools permit it.
- [ ] Implement `lib/config.js` with defaults:
  - `TRANSMISSION_RPC_URL=http://transmission.default.svc.cluster.local:9091/transmission/rpc`
  - `TRANSMISSION_DOWNLOAD_DIR=/data/books`
  - `TRANSMISSION_BOOKS_PATH=/transmission/books`
  - `TORRENT_INBOX=/inbox`
  - `TORRENT_ARCHIVE=/inbox/archive`
  - `STATE_DIR=/state`
  - `BOOKS_DEST=/books`
  - `NEEDS_REVIEW_DIR=/books/_needs-review`
  - `LOG_LEVEL=info`
  - bounded metadata command timeout, e.g. 10 seconds per file.
- [ ] Implement a small structured logger that prefixes messages with level and area (`INFO inbox: ...`, `WARN metadata: ...`, `ERROR copy: ...`) and emits a final summary with counts for torrents added, duplicates, completed torrents scanned, files copied, files skipped, archives ignored, and errors.
- [ ] Implement `lib/transmission.js` using native `fetch`; support Transmission's `409` session-id handshake and basic-auth credentials only if optional `TRANSMISSION_RPC_USERNAME`/`TRANSMISSION_RPC_PASSWORD` are provided.
- [ ] Implement torrent inbox handling in `app.js`/`files.js`: find top-level `.torrent` files in `/inbox`, ignore non-torrent files with a log entry, submit each torrent via RPC with `metainfo` and `/data/books`, then move successfully added or duplicate torrents into `/inbox/archive/` with a timestamped safe name.
- [ ] Implement completed torrent discovery: call `torrent-get`, filter to completed torrents under `/data/books`, map each torrent's `downloadDir` + file names to the mounted source path under `/transmission/books`, and skip paths that do not exist yet with an explanatory log.
- [ ] Implement filesystem candidate scanning for each completed torrent path: include supported book/media files, ignore archive extensions with explicit logs, ignore temporary/partial/zero-byte files with reasons, and group files into book candidates conservatively.
- [ ] Implement metadata extraction:
  - Call `ebook-meta` for ebook extensions and parse author/title fields.
  - Call `exiftool -json` for ebook/media fallback and parse author/title/album/album-artist fields.
  - Call `ffprobe` only as a fallback for media when ExifTool provides no usable result.
  - Treat command failures/timeouts as warnings and continue to heuristics or `_needs-review`.
- [ ] Implement `lib/classify.js` confidence rules for `Author/Book` destination selection; route conflicting or incomplete metadata to `_needs-review` instead of guessing aggressively.
- [ ] Implement `lib/import-state.js` to load existing state, determine whether a source file with the same path/size/mtime has already been imported, and persist successful imports atomically or append-only after copy success.
- [ ] Implement collision-safe copy behavior and destination path sanitization in `lib/files.js`; never overwrite a different-size destination file and never delete source/destination files.
- [ ] Add unit tests for pure logic: supported vs ignored extensions, path sanitization, metadata confidence, audiobook album grouping, `_needs-review` fallback, state idempotence, and destination collision planning.
- [ ] Add `clusters/gandazgul/apps/BookIngestCronJob.yaml` as a Flux Kustomization over `./infrastructure/cronjob/` with:
  - `CRONJOB_NAME: book-ingest`
  - `SCHEDULE: "*/10 * * * *"`
  - `IMAGE: docker.io/gandazgul/book-ingest:latest` initially, or a version tag after the first image build is available.
  - YASR mounts for `/transmission` (`subPath: configs/transmission/`), `/inbox` (`subPath: configs/book-ingest/inbox`), and `/state` (`subPath: configs/book-ingest/state`).
  - main-volume mount for `/books` (`subPath: public/Books`).
  - environment variables listed in `lib/config.js`.
  - pod/container security context using UID/GID `1000` or an equivalent writable configuration.
  - resources sized for metadata tools, e.g. request `50m` CPU / `128Mi` memory and limit `1000m` CPU / `1Gi` memory.
  - `activeDeadlineSeconds` high enough for copying large books, e.g. 20 minutes, while preserving fast no-op behavior.
  - `backoffLimit: 1` and existing `concurrencyPolicy: Forbid` from the base.
- [ ] Add `./BookIngestCronJob.yaml` to `clusters/gandazgul/apps/kustomization.yaml` near the other CronJob resources.
- [ ] Update `CONTEXT.md` in the same change to describe `book-ingest` as a copy-only torrent-to-Audiobookshelf ingestion CronJob, including the YASR inbox/state/source paths, the `main-volume` `public/Books` destination, and `_needs-review` semantics.
- [ ] Build the image with the existing build tool, push it, and update `BookIngestCronJob.yaml` to a concrete version tag if the workflow requires pinned image tags.

## Verification Plan

- Automated: run unit tests for the new container logic:
  - `cd containers/book-ingest && npm test`
- Automated: run repository pre-commit validation:
  - `node scripts/pre-commit.js --all`
- Automated: build the custom image locally:
  - `node containers/container-build.js --i=book-ingest --force`
- Automated: validate the new Flux/CronJob manifest renders:
  - `kustomize build clusters/gandazgul/apps`
  - If cluster access is available, also run `kubectl apply --dry-run=client -f <(kustomize build clusters/gandazgul/apps)` or the repository's preferred dry-run equivalent.
- Manual: create test folders/files in a safe local or cluster-mounted test area and run the container in dry-run mode, verifying logs for:
  - Empty inbox and no completed torrents exits quickly with a clear no-op summary.
  - `.torrent` files are submitted with `download-dir=/data/books` and archived only after success or duplicate acknowledgement.
  - Completed torrent with clear ebook metadata copies to `/books/<Author>/<Book>/`.
  - Completed audiobook tracks with shared album/artist metadata copy to one `/books/<Author>/<Book>/` folder.
  - Missing/conflicting metadata routes to `/books/_needs-review/<torrent-or-folder-name>/`.
  - Archive files such as `.zip`, `.rar`, and `.7z` are logged as ignored and not extracted.
  - A file manually extracted into a completed torrent folder after an earlier run is discovered on a later run because state is per imported file, not per torrent.
  - Already imported files are skipped without duplicate copies.
  - Destination collisions are not overwritten silently.
- Manual: after deployment, check the CronJob and logs:
  - `kubectl get cronjob book-ingest -n default`
  - `kubectl create job --from=cronjob/book-ingest book-ingest-manual-$(date +%s) -n default`
  - `kubectl logs -n default job/<manual-job-name>`
- Manual: confirm Transmission still shows completed torrents seeding after import; no torrents are stopped, removed, or moved.
- Manual: confirm Audiobookshelf sees confidently organized imports after a library scan and that uncertain imports appear only under `_needs-review` for review.
- Expected results for key scenarios:
  - No work: job exits `0` quickly with no filesystem changes.
  - New torrent: torrent is added to Transmission with `/data/books`; the `.torrent` file moves to archive.
  - Completed confident import: files are copied to `Author/Book`; source remains in Transmission books folder.
  - Completed uncertain import: files are copied to `_needs-review`; source remains in Transmission books folder.
  - Archive-only torrent: logs ignored archives; no extraction and no successful-file state entries.
- Confirm `CONTEXT.md` describes the implemented behavior and does not claim archive extraction, torrent cleanup, or aggressive organization that v1 does not implement.

## Edge Cases & Considerations

- Transmission RPC authentication is not currently configured in the Transmission Deployment; implement optional username/password env support but default to unauthenticated in-cluster RPC to match current repo state.
- Transmission 4.0.6 uses the legacy RPC method/key naming; use the existing `torrent-add`/`torrent-get` style and do not rely solely on Transmission 4.1 JSON-RPC snake_case names.
- Calibre can make the image large. This is acceptable for v1 if runtime stays fast, but if the image becomes operationally painful, keep the metadata adapter interface and replace Calibre with ExifTool-only or a smaller ebook parser later.
- Metadata can be wrong. Conservative confidence rules and `_needs-review` are required to avoid Audiobookshelf mis-grouping books.
- Audiobookshelf can treat folders as library items; routing bad guesses into the main `Author/Book` tree can require manual cleanup/rescan. Prefer `_needs-review` whenever unsure.
- Copy-only import intentionally duplicates storage between YASR Transmission downloads and `main-volume` Audiobookshelf library so torrents can continue seeding.
- The job must not mark an entire torrent as done, because manually extracted files may appear later and should be discovered on subsequent runs.
- The job should scan completed torrent paths from Transmission rather than recursively scanning all YASR config data to keep no-op runs fast.
- The shared CronJob base already sets `concurrencyPolicy: Forbid`; preserve it so long copies do not overlap with the next 10-minute run.
- Ensure mounted subPaths are writable by the container UID/GID. Transmission uses PUID/PGID `1000`, so matching `1000:1000` is the safest default.
- The inbox path under `configs/book-ingest/inbox` is intentionally separate from Transmission's own config/download directory so Resilio/rsync/scp drops do not interfere with active Transmission files.
