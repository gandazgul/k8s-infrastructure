---
kind: "work_record"
recordId: "db8899d8-c2df-493f-98cd-b0e167701dca"
status: "approved"
scope: "planned_change"
workKind: "FEATURE"
origin: "internal"
completionMode: "verified"
createdAt: "2026-09-10T21:59:14.754Z"
provenance:
    sourcePlans:
        - "e7716ac7-ac22-40fa-88e2-e96f1ee7b94e"
---
# K7 media trial added

## Summary

Added a K7 media-server trial for the gandazgul cluster at k7.dumbhome.uk. The change creates a CNPG-backed K7 app, a Generic overlay with pinned ghcr.io/kaybi-gh/k7:1.10.0 image, YASR-backed state, read-only TV/Movies/Music mounts, TLS ingress, required sealed hash secret, and first-run setup documentation. Static validation, rendered Flux substitution, dry-run apply checks, image manifest inspection, parsed route/mount checks, diff checks, and the pre-commit script passed.

## Deferred Work

Runtime acceptance remains pending until the GitOps change is delivered and Flux reconciles K7. Follow-up checks should confirm CNPG readiness, K7 rollout, /alive and /health over HTTPS, read-only media access, first-run setup, library scans, playback, restart persistence, and Plex continued access to the shared media.

## Future Planning Notes

For app trials that use shared media, keep application state on a separate writable YASR path and mount media libraries read-only at app-specific paths. K7 library definitions are database-owned and must be created through the admin UI rather than via invented environment variables.