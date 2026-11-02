# Rafag GitOps recovery and ownership

This branch adopts the **recovered runtime**, not the legacy application tree.
The repository is the desired-configuration source of truth. Committed YAML is
not sufficient: its Flux owner must be reachable from bootstrap and Ready at the
expected source revision. Application data and private key material are separate
restore prerequisites, never plaintext Git content.

## Bootstrap and dependency chain

The existing `infrastructure/setup/install-flux.sh`, GitRepository template and
branch-selection script remain unchanged. The installer seeds the source and
Sealed Secrets controller, installs `setup/KubeSystem.yaml`, then runs
`configure-cluster.sh` to seed the encrypted Secret, `sealed-secret` and cluster
root. Do not run the whole installer/configurator to adopt an existing cluster:
that can regenerate secrets from stale local env/values.

The new safe chain is:

- Existing source: runtime branch selection, not a competing committed source.
- `sealed-secret`: exact current encrypted cluster credentials; self-declaration.
- `kube-system`: explicit two-object allowlist (itself and cluster dispatcher).
- `cluster-infrastructure`: `clusters/<CLUSTER_NAME>/infrastructure`, selected
  from the existing kube-system Secret. This contains exact current HelmRelease
  and HelmRepository boundaries, native default backend, the ordered TLS child, encrypted ACME DNS
  credentials, and main/YASR storage-root declarations.
- `cert-manager-certificates`: real Certificate/ClusterIssuer objects only after
  cluster-infrastructure is Ready (cert-manager CRDs installed). kube-system
  waits for both children; cluster-infrastructure does not wait for TLS.
- `main-volume`, `yasr-volume`: exact bound PV/PVC identities, Retain, no prune or
  forced recreation. Claim UID/resourceVersion remain binding-controller state.
- `rafag`: waits for real sealed-secret, kube-system, main-volume and yasr-volume;
  self-owned, with its reviewed GPU/YouTube/DDNS scope and subsequent explicitly
  adopted app declarations.
- `cloudflare-ddns`: declared by rafag, code and hourly CronJob reconciled by its
  own leaf owner. No additional permanent manual bootstrap exception.

There is no Flux dependency cycle: kube-system waits for its infrastructure
child; that child does not wait for kube-system. The sealed controller's initial
seed is an intentional installer prerequisite, not a pretend ready dependency.

The generic dispatcher fails closed for clusters without an explicit reviewed
`clusters/<name>/infrastructure` overlay. It must not silently load rafag's
identities for another cluster. Historical files elsewhere under
`infrastructure/kube-system` are deliberately not scanned.

## One-time existing-cluster adoption

After validation, review, commit and normal push to the already selected branch:

1. Verify Flux source has fetched that exact commit; do not retarget source.
2. Seed **only the exact committed**
   `clusters/rafag/sealed-secret/Reconciliation.yaml` and
   `infrastructure/setup/KubeSystem.yaml` with server-side apply using the Flux
   field manager. They are normal bootstrap seeds and subsequently self-owned.
3. Wait for sealed-secret, cluster-infrastructure, kube-system and both storage
   roots to be Ready; verify current UIDs/specs/data hashes remain unchanged.
4. Seed **only the exact committed** `clusters/rafag/ClusterKustomization.yaml`.
   The old dependency-blocked root cannot apply its own dependency correction.
5. Verify all roots report Ready at the committed revision; verify rafag now
   inventories the DDNS declaration and DDNS still inventories its two resources.
6. Require no template changes, no original Pod UID/restart changes, unchanged
   PV/PVC binding identities, held HelmReleases still suspended, and no backup
   claim/jobs created. Metadata/ownership adoption is expected.

The metadata-only Cloudflare Secret declaration uses Flux SSA `Merge` to preserve
existing credential bytes while permitting the matching encrypted SealedSecret
owner to adopt it. The encrypted template retains the same annotations/labels to
avoid controller fights. No raw credential values belong in this repository.
Verify decryptability before activation and exact credential hashes afterwards.

## HA and editor ownership

`home-assistant-native` adopts the current Deployment, public Service/Ingress and
held HelmRelease. Keep the full existing Pod template, digest, Recreate strategy,
USB mapping and saved-state guard; adoption must not restart HA. The held release
remains suspended and prune-protected even though its inert old chart values
remain for history. Never unsuspend it to deploy the native editor.

`home-assistant-editor` depends on native HA adoption. Its separate pinned
code-server container mounts only `configs/hass` from the existing YASR claim,
runs as UID/GID1000 without chown/fsGroup, has no API token and uses the existing
reflected `ADMIN_PASSWORD` key through secretKeyRef. No password value belongs in
Git or logs. Config/auth checks must pass before publishing its TLS-only route.
Readiness `/healthz` is process health only; require login, IDE/WebSocket and a
disposable-file round-trip before claiming editor recovery. HA runtime/data
identity must stay unchanged.

CEL health checks use field selectors such as `has(status.conditions)`.
`has(status)` is not a valid root presence macro in this controller and is
rejected before apply; schema/server dry-run does not compile those expressions.

## Explicit holds and non-goals

- No backup-volume PV/PVC or backup jobs until the actual backup disk is mounted
  and verified. Missing backup hardware gates backups, **not unrelated apps**.
- Do not resume the legacy home-assistant or sftpgo HelmRelease. Native adoption
  preserves their current runtime and held release boundaries.
- Preserve Immich's restricted recovery and deliberately hibernated separate
  CNPG cluster. Do not introduce database bootstrap or fresh app onboarding.
- Do not enable old ingress-nginx or downgrade recovered operators.
- Historical missing apps, monitoring and Paperless web are separate reviewed
  repair batches, not a reason to include the old whole apps tree.
- No main merge or automatic PR creation; owner review/integration is separate.

## Rebuild prerequisites and rollback

Preserve/restore the existing Sealed Secrets **private key** through the private
backup process before unsealing committed ciphertext on a rebuilt cluster. Do
not rotate/generate a replacement key and call the old ciphertext recoverable.
No private key is exported or committed by this adoption. Restore and verify
real local filesystems (main/YASR UUIDs), app data, databases and USB identity
before admitting workloads; Git cannot recreate their contents.

If adoption unexpectedly changes effective specs or data bindings, stop that
leaf and investigate. Prefer a reviewed Git revert to the known baseline;
prune:false, Orphan and Retain prevent removal from deleting persistent state.
Reverting the global dependency change intentionally re-blocks rafag; it does
not restore missing backup hardware. Do not delete HelmRelease objects as a
rollback: that can uninstall workloads. Never force immutable storage changes.

Evidence sources: fresh server-side dry runs; Flux current observed generation,
Ready/health/inventory/applied SHA; source remote SHA; retained scheduled DDNS
Job logs; pre/post effective spec/template/data hashes and runtime UIDs.
