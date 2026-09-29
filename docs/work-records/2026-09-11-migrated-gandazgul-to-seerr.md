---
kind: "work_record"
recordId: "2d4661e2-ca9b-46cf-93ef-22c07d789160"
status: "approved"
scope: "planned_change"
workKind: "FEATURE"
origin: "internal"
completionMode: "verified"
createdAt: "2026-09-11T03:36:28.319Z"
provenance:
    sourcePlans:
        - "059e9178-179b-49db-b83e-a6b95169d20e"
---
# Migrated gandazgul to Seerr

## Summary

Gandazgul was migrated from Overseerr to the official Seerr chart 3.9.1 and image ghcr.io/seerr-team/seerr:v3.4.1 while preserving the existing configs/overseerr data, HTTPS address, accounts, and request history. Flux reconciliation completed with Seerr active and the old gandazgul Overseerr resources absent; rafag intentionally remains on Overseerr. Validation passed through kustomize builds for gandazgul, rafag, and renepor, git diff checks, pre-commit checks, rendered chart checks, live pod readiness, HTTPS 200 with valid TLS, restart persistence, API data counts, and user verification of existing-account login plus a real request.

## Deviations from Plan

The migration also fixed infrastructure/setup/change-branch.sh so branch names containing slashes work. yamllint was not run because it was not installed locally.

## Future Planning Notes

For future live app migrations that reuse a SQLite-backed config path, stop the old workload before backup and startup to avoid concurrent writers. Keep the pre-migration archive and checksum evidence available for rollback until the user accepts the result.