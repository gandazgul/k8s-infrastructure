---
planId: "059e9178-179b-49db-b83e-a6b95169d20e"
classification: "PLANNED_CHANGE"
workKind: "FEATURE"
complexity: "MEDIUM"
affectedPaths:
  - "apps/Overseerr.yaml"
  - "apps/Seerr.yaml"
  - "clusters/gandazgul/apps/kustomization.yaml"
  - "clusters/rafag/apps/kustomization.yaml"
  - "docs/seerr-migration.md"
executionAgent: "engineer"
collaborationRecommendation: "pair"
createdAt: "2026-09-10"
status: "in_progress"
origin: "internal"
userVerifiedAt: null
targetBranch: "main"
---

# Migrate Overseerr to Seerr on Both Clusters

## Context

The user reports that the deprecated request app does not work correctly and wants the unified successor to Overseerr and Jellyseerr. The user confirmed that this change covers **both gandazgul and rafag**.

Both cluster app lists include `apps/Overseerr.yaml`. It defines HelmRelease `default/overseerr`, using the `k8s-at-home` Overseerr chart `5.4.2` and an unpinned `latest` image. Each instance uses its own `yasr-volume` PVC, subPath `configs/overseerr`, and `media.${CLUSTER_DOMAIN_NAME}` ingress.

Upstream evidence checked on 2026-09-10:

- [Seerr migration guide](https://docs.seerr.dev/migration-guide/): Seerr migrates Overseerr data on first startup. Back up first. The official image runs as UID/GID 1000 and needs write access to `/app/config`.
- [Official Kubernetes installation](https://docs.seerr.dev/getting-started/kubernetes/): official OCI chart at `oci://ghcr.io/seerr-team/seerr/seerr-chart`.
- [Latest release](https://github.com/seerr-team/seerr/releases/latest): stable application `v3.4.1`. `helm show chart` resolved chart `3.9.1`, appVersion `v3.4.1`, chart digest `sha256:d882289589ac20469a92c1554e21813ca9c8d96ec986fe9ea7dbc7473c3ce404`.
- [Backup guide](https://docs.seerr.dev/using-seerr/backups/): stop the application before a file-based SQLite backup. Preserve settings and the database.

A local chart render confirms a StatefulSet, `/app/config` mount, port 5055, and HTTP health checks. No live workload or data has been inspected during planning. Local tools include Helm, Flux, Kustomize, kubectl, and Podman. The local current context is `home`; no context explicitly named `rafag` is listed. This does not establish access to either target.

## Objective

Both clusters run the official stable Seerr application and chart. Each retains its own accounts, request history, permissions, integrations, configuration directory, time zone, and HTTPS address. Forecastle lists the application as **Seerr**.

Neither cluster can run Overseerr and Seerr against the same database at the same time. Each has a verified pre-migration backup and a documented rollback procedure. Repository validation alone does not count as a completed live migration.

## Approach

Use an app-local OCIRepository and a new HelmRelease `default/seerr`, following `apps/Flaresolverr.yaml`. Set `fullnameOverride: seerr`. Use the official chart rather than a new Generic overlay. An image-only change would be smaller, but would retain the old chart and its unverified runtime defaults.

Keep `configs/overseerr` as the on-disk path. A cosmetic directory rename adds data movement without improving the migration. Seerr remains a request app; this change does not replace Plex, install Jellyfin, or change existing media-server choices.

Final path:

```text
Both cluster app lists
  apps/Seerr.yaml
    OCIRepository kube-system/seerr (chart 3.9.1)
    HelmRelease default/seerr
      StatefulSet seerr (image v3.4.1)
      yasr-volume: configs/overseerr -> /app/config
      media.<existing cluster domain> -> Service seerr -> port 5055
```

Use a controlled, staged cutover. First publish Seerr in a suspended state while keeping Overseerr unchanged. Then migrate one cluster at a time with its parent Flux Kustomization suspended. Only publish the final removal of Overseerr and active Seerr configuration after both migrations pass. Do not trust Flux prune ordering to stop the old writer before starting the new one.

Recommend paired execution for context confirmation, backup checks, publishing, and authenticated application checks. If live access is unavailable, finish safe preparation and report the live migration as blocked, not complete.

## Expected Change Surface

The boundaries this change is expected to touch. This list is guidance, not an allowlist: verify the real footprint
during implementation and change whatever the Implementation Steps need, including files not named here. Stop and report
only when discovery changes approved intent — the change reaches another subsystem, public behavior or architecture
shifts, migration or compatibility risk grows, or the Verification Plan no longer proves the objective.

- `apps/Seerr.yaml` — app-local source and official-chart HelmRelease with preserved storage and ingress.
- `apps/Overseerr.yaml` — retained during preparation; removed from final desired state after both cutovers.
- `clusters/{gandazgul,rafag}/apps/kustomization.yaml` — staged addition of Seerr, then final removal of Overseerr references.
- `docs/seerr-migration.md` — exact operator commands, gates, backup/restore instructions, and per-cluster verification checklist. Keep secrets and data exports out of Git.
- Live resources on both approved cluster contexts — temporary reconciliation suspension, old workload shutdown/uninstall, scoped permission correction, backup, and new release startup.

Do not change shared PVCs, PVs, other applications, `renepor`, the global `k8s-at-home` source, or generic base manifests. Other apps still use the old repository. No domain term is introduced or redefined; `docs/domain-language.md` remains unchanged.

## Reuse Opportunities

- `apps/Flaresolverr.yaml` — OCIRepository in `kube-system`, HelmRelease in `default`, and `spec.chartRef` pattern.
- `apps/Overseerr.yaml` — existing host, TLS secret, time zone, Forecastle metadata, and storage location.
- `clusters/{gandazgul,rafag}/ClusterKustomization.yaml` — existing per-cluster substitutions and Flux ownership.
- `infrastructure/storage/{pv,pvc}/` — existing retained local storage; no new claim or provisioner is needed.

## Implementation Steps

1. **The deployment and recovery inputs are known for each cluster before any outage.** Confirm context-to-cluster mapping with the user and inspect each installed release, workload, image digest, config mount, database type, file ownership, and Flux reconciliation state. Record the old chart/values and retrievable old image version/digest for rollback in private operational notes. Establish a baseline of user IDs/counts, permission samples, request IDs/statuses/counts, and configured integration targets without exporting credentials. Confirm both cluster/node access and a usable backup destination outside the config directory before starting either cutover. Unexpected data layout or an unreadable/corrupt database requires review, not an empty replacement instance.

2. **`apps/Seerr.yaml` renders the official application with the required storage and network behavior.** Use OCIRepository `kube-system/seerr` with exact `ref.tag: "3.9.1"`, official chart URL, and HelmRelease `default/seerr` through `chartRef`. Explicitly pin image registry `ghcr.io`, repository `seerr-team/seerr`, and tag `v3.4.1`. Keep `fullnameOverride: seerr`, one StatefulSet replica (chart default), and no extra replica writer. Set:
   - `config.persistence.existingClaim: yasr-volume` and `subPath: configs/overseerr`; render must not create a PVC.
   - `extraEnv` for `TZ=${CLUSTER_TIME_ZONE}`.
   - Ingress enabled, `ingressClassName: nginx`, existing media host, `/` with `pathType: Prefix`, and existing `internal-ingress-cert` TLS reference.
   - Forecastle name `Seerr`, group `Media`, exposed flag, and existing same-host icon URL.
   - Chart non-root UID/GID 1000 and restricted container security defaults. Explicitly null `podSecurityContext.fsGroup` and `fsGroupChangePolicy` so Helm removes the chart defaults. Render must contain no volume-wide group ownership setting. An empty map alone does not remove merged defaults.
   - `serviceAccount.automount: false`; the application needs no Kubernetes API credentials.
   - HTTP startup probe at `/api/v1/settings/public`, named port `http`, period 10 seconds, failure threshold 60, timeout 3 seconds. Keep the chart HTTP readiness/liveness probes. Migration gets up to ten minutes before startup failures cause a restart; an overrun requires inspection.
   - `spec.suspend: true` for the preparation stage only. Both cluster app lists add this resource while retaining Overseerr. Existing apps remain unchanged after this stage is reconciled.

3. **The operator runbook defines a safe, executable cutover and restore path.** Include commands with explicit context/namespace placeholders, how to find the actual old workload, and checks at every gate. Backups contain the complete stopped config directory, including SQLite sidecars and settings, preserve numeric ownership, and have restricted access. Check archive contents and a checksum; test extraction and SQLite integrity on an isolated copy where applicable. If the installed database is external, include its consistent dump/restore or stop for a revised procedure. Do not assume existing backup CronJobs cover YASR. Restore must use the pre-migration data and recorded old runtime, not just a Git revert.

4. **Each cluster completes this sequence without concurrent writers.** Publish/reconcile the suspended preparation stage only after user confirmation. Then process gandazgul and rafag separately:
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
   Suspension is not shutdown. Account for any higher-level reconciler that could undo the temporary suspension. The backup gate precedes permission changes and Seerr startup. Do not recursively change `/media/yasr`, follow symlinks into other apps, or use pod-level fsGroup on the shared PVC. If uninstall fails, do not bypass finalizers or start Seerr. Keep the parent suspended until final Git state is published; otherwise it could recreate Overseerr or suspend Seerr. Do not start rafag's outage until gandazgul passes its checks.

5. **Final Git desired state and live state agree on both clusters.** After both migrations pass, both app lists reference only `apps/Seerr.yaml`; `apps/Overseerr.yaml` is removed and Seerr is no longer suspended. Publish the final revision with user confirmation, then reconcile and verify both clusters. Restore only reconciliation states changed for this migration; do not blindly resume resources already suspended for unrelated work. Keep pre-migration backups until the user accepts the result. If any live step is unavailable or fails, report the exact completed stage and remaining work rather than publishing an unsafe final state or claiming completion.

## Approval Confirmation

No Work Records are superseded. Scope is both clusters, as confirmed by the user. The plan preserves existing data and addresses rather than setting up fresh instances. Brief per-cluster downtime and live checkpoints are part of this migration.

## Verification Plan

- **Static validation:** `kustomize build clusters/gandazgul/apps`, `kustomize build clusters/rafag/apps`, and `kustomize build clusters/renepor/apps`. Run `yamllint` on changed YAML if available and `node scripts/pre-commit.js` on staged files. Report pre-existing failures separately.
- **Actual chart output:** extract values from the implemented HelmRelease to a temporary file, substitute a safe sample domain/time zone, then run `helm template seerr oci://ghcr.io/seerr-team/seerr/seerr-chart --version 3.9.1 --namespace default -f <extracted-values.yaml>`. Inspect parsed resources, not merely source text. Verify official image/version, singleton StatefulSet, exact config mount, no new PVC, absent fsGroup, UID/GID 1000, disabled API-token mount, startup/readiness checks, and complete Ingress -> Service -> port 5055 routing. Repeat substitution for both cluster configurations without exposing secrets. Check that the final cluster builds include the new source/release and no old HelmRelease, while renepor is unchanged.
- **Cluster validation:** run context-explicit client dry-runs against the relevant substituted resources; use server dry-runs where available to validate installed Flux APIs. Do not apply a full rendered chart outside Helm. `kustomize build` alone does not render Helm workloads.
- **Backup evidence, separately for both clusters:** old pods absent before backup; readable archive and checksum; successful isolated extraction; database integrity where applicable; settings present. Prove the restore path on the isolated copy. Never point old software at Seerr's migrated database.
- **Cutover evidence:** old workload and ingress absent before new startup; exactly one Seerr pod uses this config; logs show no failed migration or permission errors; health endpoint returns success; StatefulSet is ready. Record deployed image ID and source/chart revision for each cluster.
- **Preservation and functional checks, separately for both users:** open the existing HTTPS media address, verify valid TLS and Seerr identity, log in with an existing account, compare users/permissions and request history with the baseline, and check existing Plex and Radarr/Sonarr connections. Test a notification if configured. Submit one user-approved test request and confirm it reaches the correct configured request service; avoid unwanted downloads by agreeing on the test item first. No setup wizard or empty history is acceptable when the old instance had data. Confirm the Forecastle entry is Seerr.
- **Persistence and reconciliation:** restart the Seerr pod after successful migration and confirm login, settings, and history still exist. Reconcile final Git state and verify old resources do not return, both Seerr releases are healthy, and unrelated applications/storage are unchanged.
- The data-baseline comparison and existing-account login reject a fresh empty install. The end-to-end request and restart checks prove that the migrated app works and retains data. Source/chart and rendered-resource checks reject an image-only replacement that retains the old chart. Keep timestamped, secret-free evidence of the shutdown, backup, uninstall, and startup gates; final healthy state alone cannot prove safe ordering. There is no existing automated app test suite to retire. Existing media request, account, integration, persistence, and HTTPS behavior must remain; only the old application/chart identity is retired.

## Edge Cases & Considerations

- `ReadWriteOnce` does not prevent two pods on the same node from opening SQLite. Explicit old-pod termination is required.
- The new chart uses a StatefulSet; the old chart's exact installed workload and naming must be inspected. New names avoid adoption conflicts but do not establish startup order.
- The old data may already be damaged. Preserve the backup and failure evidence; do not repair or discard user data without approval.
- Rollback after migration requires stopping Seerr, restoring the full pre-migration config with old ownership, and restoring the old release/image while reconciliation is controlled. Requests made after migration are not present in that backup; obtain user approval before discarding them.
- Current release/chart versions are verified planning targets. Recheck release status before implementation. If a newer stable release changes migration or chart requirements, report the difference for review rather than silently adopting it. Do not use rolling `latest` or `develop` tags.
- Keep each cluster's settings and backups separate. Never copy one user's configuration to the other cluster.
- The reported malfunction is not yet reproduced. The migration must pass the defined request workflow; unrelated upstream or integration faults found during verification must be reported explicitly.
