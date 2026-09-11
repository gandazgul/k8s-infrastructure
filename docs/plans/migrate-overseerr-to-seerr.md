---
planId: "059e9178-179b-49db-b83e-a6b95169d20e"
classification: "PLANNED_CHANGE"
workKind: "FEATURE"
complexity: "MEDIUM"
affectedPaths:
  - "apps/Overseerr.yaml"
  - "apps/Seerr.yaml"
  - "clusters/gandazgul/apps/kustomization.yaml"
  - "docs/seerr-migration.md"
executionAgent: "engineer"
collaborationRecommendation: "pair"
createdAt: "2026-09-10"
status: "in_progress"
origin: "internal"
userVerifiedAt: null
targetBranch: "main"
---

# Migrate Overseerr to Seerr on Gandazgul

## Context

The user reports that the deprecated request app does not work correctly and wants the unified successor to Overseerr and Jellyseerr. The user first requested both gandazgul and rafag, then explicitly narrowed the live work to **gandazgul only** because rafag is unreachable.

The gandazgul app list includes `apps/Overseerr.yaml`. It defines HelmRelease `default/overseerr`, using the `k8s-at-home` Overseerr chart `5.4.2` and an unpinned `latest` image. The instance uses `yasr-volume`, subPath `configs/overseerr`, and `media.${CLUSTER_DOMAIN_NAME}` ingress.

Upstream evidence checked on 2026-09-10:

- [Seerr migration guide](https://docs.seerr.dev/migration-guide/): Seerr migrates Overseerr data on first startup. Back up first. The official image runs as UID/GID 1000 and needs write access to `/app/config`.
- [Official Kubernetes installation](https://docs.seerr.dev/getting-started/kubernetes/): official OCI chart at `oci://ghcr.io/seerr-team/seerr/seerr-chart`.
- [Latest release](https://github.com/seerr-team/seerr/releases/latest): stable application `v3.4.1`. `helm show chart` resolved chart `3.9.1`, appVersion `v3.4.1`, chart digest `sha256:d882289589ac20469a92c1554e21813ca9c8d96ec986fe9ea7dbc7473c3ce404`.
- [Backup guide](https://docs.seerr.dev/using-seerr/backups/): stop the application before a file-based SQLite backup. Preserve settings and the database.

A local chart render confirms a StatefulSet, `/app/config` mount, port 5055, and HTTP health checks. Planning did not inspect live workload or data. During execution, read-only checks confirmed local context `home` maps to gandazgul. Local tools include Helm, Flux, Kustomize, kubectl, and Podman.

## Objective

Gandazgul runs the official stable Seerr application and chart. It retains its accounts, request history, permissions, integrations, configuration directory, time zone, and HTTPS address. Forecastle lists the application as **Seerr**.

Gandazgul cannot run Overseerr and Seerr against the same database at the same time. It has a verified pre-migration backup and a documented rollback procedure. Repository validation alone does not count as a completed live migration. Rafag remains on its existing Overseerr desired state and is intentionally out of scope for this run.

## Approach

Use an app-local OCIRepository and a new HelmRelease `default/seerr`, following `apps/Flaresolverr.yaml`. Set `fullnameOverride: seerr`. Use the official chart rather than a new Generic overlay. An image-only change would be smaller, but would retain the old chart and its unverified runtime defaults.

Keep `configs/overseerr` as the on-disk path. A cosmetic directory rename adds data movement without improving the migration. Seerr remains a request app; this change does not replace Plex, install Jellyfin, or change existing media-server choices.

Final path:

```text
Gandazgul cluster app list
  apps/Seerr.yaml
    OCIRepository kube-system/seerr (chart 3.9.1)
    HelmRelease default/seerr
      StatefulSet seerr (image v3.4.1)
      yasr-volume: configs/overseerr -> /app/config
      media.<existing cluster domain> -> Service seerr -> port 5055
```

Use a controlled, staged cutover. First publish Seerr in a suspended state while keeping Overseerr unchanged. Then migrate gandazgul with its parent Flux Kustomization suspended. Only publish the final removal of Overseerr and active Seerr configuration after the migration passes. Do not trust Flux prune ordering to stop the old writer before starting the new one.

Recommend paired execution for context confirmation, backup checks, publishing, and authenticated application checks. If live access is unavailable, finish safe preparation and report the live migration as blocked, not complete.

## Expected Change Surface

The boundaries this change is expected to touch. This list is guidance, not an allowlist: verify the real footprint
during implementation and change whatever the Implementation Steps need, including files not named here. Stop and report
only when discovery changes approved intent — the change reaches another subsystem, public behavior or architecture
shifts, migration or compatibility risk grows, or the Verification Plan no longer proves the objective.

- `apps/Seerr.yaml` — app-local source and official-chart HelmRelease with preserved storage and ingress.
- `apps/Overseerr.yaml` — retained because rafag still references it; removed only from the final gandazgul app list after cutover.
- `clusters/gandazgul/apps/kustomization.yaml` — staged addition of Seerr, then final removal of the Overseerr reference.
- `docs/seerr-migration.md` — exact operator commands, gates, backup/restore instructions, and gandazgul verification checklist. Keep secrets and data exports out of Git.
- Live resources on the gandazgul cluster context — temporary reconciliation suspension, old workload shutdown/uninstall, scoped permission correction, backup, and new release startup.

Do not change shared PVCs, PVs, other applications, `rafag`, `renepor`, the global `k8s-at-home` source, or generic base manifests. Other apps still use the old repository. No domain term is introduced or redefined; `docs/domain-language.md` remains unchanged.

## Reuse Opportunities

- `apps/Flaresolverr.yaml` — OCIRepository in `kube-system`, HelmRelease in `default`, and `spec.chartRef` pattern.
- `apps/Overseerr.yaml` — existing host, TLS secret, time zone, Forecastle metadata, and storage location.
- `clusters/gandazgul/ClusterKustomization.yaml` — existing per-cluster substitutions and Flux ownership.
- `infrastructure/storage/{pv,pvc}/` — existing retained local storage; no new claim or provisioner is needed.

## Implementation Steps

1. **The deployment and recovery inputs are known for gandazgul before outage.** Confirm context-to-cluster mapping and inspect the installed release, workload, image digest, config mount, database type, file ownership, and Flux reconciliation state. Record the old chart/values and retrievable old image version/digest for rollback in private operational notes. Establish a baseline of user IDs/counts, permission samples, request IDs/statuses/counts, and configured integration targets without exporting credentials. Confirm node access and a usable backup destination outside the config directory before cutover. Unexpected data layout or an unreadable/corrupt database requires review, not an empty replacement instance.

2. **`apps/Seerr.yaml` renders the official application with the required storage and network behavior.** Use OCIRepository `kube-system/seerr` with exact `ref.tag: "3.9.1"`, official chart URL, and HelmRelease `default/seerr` through `chartRef`. Explicitly pin image registry `ghcr.io`, repository `seerr-team/seerr`, and tag `v3.4.1`. Keep `fullnameOverride: seerr`, one StatefulSet replica (chart default), and no extra replica writer. Set:
   - `config.persistence.existingClaim: yasr-volume` and `subPath: configs/overseerr`; render must not create a PVC.
   - `extraEnv` for `TZ=${CLUSTER_TIME_ZONE}`.
   - Ingress enabled, `ingressClassName: nginx`, existing media host, `/` with `pathType: Prefix`, and existing `internal-ingress-cert` TLS reference.
   - Forecastle name `Seerr`, group `Media`, exposed flag, and existing same-host icon URL.
   - Chart non-root UID/GID 1000 and restricted container security defaults. Explicitly null `podSecurityContext.fsGroup` and `fsGroupChangePolicy` so Helm removes the chart defaults. Render must contain no volume-wide group ownership setting. An empty map alone does not remove merged defaults.
   - `serviceAccount.automount: false`; the application needs no Kubernetes API credentials.
   - HTTP startup probe at `/api/v1/settings/public`, named port `http`, period 10 seconds, failure threshold 60, timeout 3 seconds. Keep the chart HTTP readiness/liveness probes. Migration gets up to ten minutes before startup failures cause a restart; an overrun requires inspection.
   - `spec.suspend: true` for the preparation stage only. The gandazgul app list adds this resource while retaining Overseerr. Existing apps remain unchanged after this stage is reconciled.

3. **The operator runbook defines a safe, executable cutover and restore path.** Include commands with explicit context/namespace placeholders, how to find the actual old workload, and checks at every gate. Backups contain the complete stopped config directory, including SQLite sidecars and settings, preserve numeric ownership, and have restricted access. Check archive contents and a checksum; test extraction and SQLite integrity on an isolated copy where applicable. If the installed database is external, include its consistent dump/restore or stop for a revised procedure. Do not assume existing backup CronJobs cover YASR. Restore must use the pre-migration data and recorded old runtime, not just a Git revert.

4. **Gandazgul completes this sequence without concurrent writers.** Publish/reconcile the suspended preparation stage only after user confirmation. Then process gandazgul:
   ```text
   confirm parent applied preparation revision; Seerr is suspended, no new pod
     suspend that cluster's parent Flux Kustomization and old HelmRelease
     stop actual old workload; wait for all its pods to terminate
     back up and validate the stopped data
     correct permissions only within configs/overseerr if needed
     remove old HelmRelease; wait for Helm uninstall and old ingress removal
     verify no old writer; resume Seerr while parent remains suspended
     verify migration, preserved data, and application behavior
   ```
   Suspension is not shutdown. Account for any higher-level reconciler that could undo the temporary suspension. The backup gate precedes permission changes and Seerr startup. Do not recursively change `/media/yasr`, follow symlinks into other apps, or use pod-level fsGroup on the shared PVC. If uninstall fails, do not bypass finalizers or start Seerr. Keep the parent suspended until final Git state is published; otherwise it could recreate Overseerr or suspend Seerr.

5. **Final Git desired state and live state agree on gandazgul.** After the gandazgul migration passes, the gandazgul app list references only `apps/Seerr.yaml`; `apps/Overseerr.yaml` remains in Git for rafag, and Seerr is no longer suspended. Rafag keeps its existing Overseerr reference. Publish the final revision with user confirmation, then reconcile and verify gandazgul. Restore only reconciliation states changed for this migration; do not blindly resume resources already suspended for unrelated work. Keep pre-migration backups until the user accepts the result. If any live step is unavailable or fails, report the exact completed stage and remaining work rather than publishing an unsafe final state or claiming completion.

## Approval Confirmation

No Work Records are superseded. Scope is gandazgul only, as revised by the user during execution because rafag is unreachable. The plan preserves existing data and address rather than setting up a fresh instance. Brief downtime and live checkpoints are part of this migration.

## Verification Plan

- **Static validation:** `kustomize build clusters/gandazgul/apps`, `kustomize build clusters/rafag/apps`, and `kustomize build clusters/renepor/apps`. Gandazgul must include Seerr. Rafag and renepor must remain unchanged. Run `yamllint` on changed YAML if available and `node scripts/pre-commit.js` on staged files. Report pre-existing failures separately.
- **Actual chart output:** extract values from the implemented HelmRelease to a temporary file, substitute a safe sample domain/time zone, then run `helm template seerr oci://ghcr.io/seerr-team/seerr/seerr-chart --version 3.9.1 --namespace default -f <extracted-values.yaml>`. Inspect parsed resources, not merely source text. Verify official image/version, singleton StatefulSet, exact config mount, no new PVC, absent fsGroup, UID/GID 1000, disabled API-token mount, startup/readiness checks, and complete Ingress -> Service -> port 5055 routing. Repeat substitution for the gandazgul configuration without exposing secrets. Check that the final gandazgul build includes the new source/release and no old HelmRelease, while rafag and renepor are unchanged.
- **Cluster validation:** run context-explicit client dry-runs against the relevant substituted resources; use server dry-runs where available to validate installed Flux APIs. Do not apply a full rendered chart outside Helm. `kustomize build` alone does not render Helm workloads.
- **Backup evidence for gandazgul:** old pods absent before backup; readable archive and checksum; successful isolated extraction; database integrity where applicable; settings present. Prove the restore path on the isolated copy. Never point old software at Seerr's migrated database.
- **Cutover evidence:** old workload and ingress absent before new startup; exactly one Seerr pod uses this config; logs show no failed migration or permission errors; health endpoint returns success; StatefulSet is ready. Record deployed image ID and source/chart revision for gandazgul.
- **Preservation and functional checks for gandazgul:** open the existing HTTPS media address, verify valid TLS and Seerr identity, log in with an existing account, compare users/permissions and request history with the baseline, and check existing Plex and Radarr/Sonarr connections. Test a notification if configured. Submit one user-approved test request and confirm it reaches the correct configured request service; avoid unwanted downloads by agreeing on the test item first. No setup wizard or empty history is acceptable when the old instance had data. Confirm the Forecastle entry is Seerr.
- **Persistence and reconciliation:** restart the Seerr pod after successful migration and confirm login, settings, and history still exist. Reconcile final Git state and verify old resources do not return, the Seerr release is healthy, and unrelated applications/storage are unchanged.
- The data-baseline comparison and existing-account login reject a fresh empty install. The end-to-end request and restart checks prove that the migrated app works and retains data. Source/chart and rendered-resource checks reject an image-only replacement that retains the old chart. Keep timestamped, secret-free evidence of the shutdown, backup, uninstall, and startup gates; final healthy state alone cannot prove safe ordering. There is no existing automated app test suite to retire. Existing media request, account, integration, persistence, and HTTPS behavior must remain; only the old application/chart identity is retired.

## Edge Cases & Considerations

- `ReadWriteOnce` does not prevent two pods on the same node from opening SQLite. Explicit old-pod termination is required.
- The new chart uses a StatefulSet; the old chart's exact installed workload and naming must be inspected. New names avoid adoption conflicts but do not establish startup order.
- The old data may already be damaged. Preserve the backup and failure evidence; do not repair or discard user data without approval.
- Rollback after migration requires stopping Seerr, restoring the full pre-migration config with old ownership, and restoring the old release/image while reconciliation is controlled. Requests made after migration are not present in that backup; obtain user approval before discarding them.
- Current release/chart versions are verified planning targets. Recheck release status before implementation. If a newer stable release changes migration or chart requirements, report the difference for review rather than silently adopting it. Do not use rolling `latest` or `develop` tags.
- Rafag is out of scope because it is unreachable. Do not change or copy rafag configuration during this run.
- The reported malfunction is not yet reproduced. The migration must pass the defined request workflow; unrelated upstream or integration faults found during verification must be reported explicitly.
