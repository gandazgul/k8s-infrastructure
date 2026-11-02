# GitOps ownership audit

Run from a checkout of the intended source revision:

```bash
python3 scripts/audit-gitops-ownership.py \
  --kubectl /home/cybervoid/.local/bin/kubectl > /tmp/gitops-ownership.json
# Require complete adoption, including elimination of explicit recovery holds:
python3 scripts/audit-gitops-ownership.py --strict \
  --kubectl /home/cybervoid/.local/bin/kubectl > /tmp/gitops-ownership-strict.json
```

The expected commit defaults to repository `HEAD`; use `--expected-sha` with a
full commit ID when auditing a different published revision. The expected source
is `kube-system/k8s-infrastructure` (`--expected-source NAMESPACE/NAME`). A local
commit that has not been published/reconciled is intentionally not accepted.

## Safety and scope

Python 3.9+ standard library only. The helper performs `kubectl get` and, unless an
explicit SHA is supplied, `git rev-parse HEAD`. It never applies, patches,
reconciles, restarts, stages or commits anything. No Secret resource is requested.
Resource responses are parsed in memory; only allowlisted identity, inventory,
readiness, revision and ownership fields reach the JSON report. Raw bodies,
container environment, values, annotations, credentials and kubectl error output
are never emitted. A failed query makes the audit incomplete and exits 2 rather
than silently skipping a resource type. Reports may be kept outside the repo.

The census reports Deployments, DaemonSets, StatefulSets, ReplicationControllers,
CronJobs, Jobs, standalone/orphan Pods, CNPG Clusters, PVs and PVCs. ReplicaSets
are ancestry-only. Pods with a UID-verified owner are excluded from workload
counts to avoid counting a Deployment and its Pods twice; Nodes are fetched to
verify static control-plane Pod owners. Query counts disclose these exclusions.
HelmRelease declaration and controller states are reported separately.

This is a sequential, non-atomic ownership snapshot. It is **not** a Pod health,
application acceptance, rendered-spec equality, data-integrity, backup or
rebuild-success audit. For example, a failed recovery Pod remains a disclosed
hold, not a successful recovery. Reconciliation may advance mid-snapshot: rerun
a pending report after normal reconciliation; never force a reconcile merely to
make the audit green. Local source paths and installer references must exist,
but this helper does not render manifests or prove installer idempotency.

## Evidence and classifications

Ownership comes from Flux Kustomization `status.inventory`, HelmRelease
`status.inventory`, and UID-verified `ownerReferences`, **not labels or name
prefixes**. This includes Helm children without Flux labels, CronJob-generated
Jobs, and CNPG-generated PVCs. Inventory IDs are decoded from their namespace,
name, group and kind components, including encoded colons in RBAC names.
The graph distinguishes ownership edges from `sourceRef` and `dependsOn` edges;
a dependency is not mistaken for a parent owner.

- **ActiveGitOps:** inventory ancestry reaches a documented self-owned bootstrap
  seed. Every Kustomization on that ownership path is unsuspended, Ready at its
  current generation, and applied at the expected commit; its expected
  GitRepository must likewise be Ready/current at that artifact revision. Leaf
  path, source, applied SHA and complete parent chain are included. Traversing a
  HelmRelease also requires it unsuspended and Ready/current. Direct native
  inventory ownership can still be active when an old HelmRelease is held.
- **BootstrapManaged:** exact named CoreDNS Deployment, kube-proxy DaemonSet and
  kube-flannel DaemonSet reference `install-k8s/2-configK8SControlPlane.sh`
  (`kubeadm init` supplies CoreDNS/kube-proxy; the script installs Flannel).
  The four existing Flux controller Deployments reference
  `infrastructure/setup/install-flux.sh`. These are installer-managed boundaries,
  deliberately **not** advertised as active Flux-owned workloads. The bootstrap
  script's extra-component options do not exempt additional live controllers.
- **ExplicitRecoveryHold:** only the exact observed names listed below, plus
  PVCs with UID-verified owner ancestry to the held CNPG Clusters. This category
  takes precedence over Git ownership so holds cannot disappear from the report.
- **GitOpsNotCurrent:** inventory ancestry exists but is not currently active at
  the expected source commit, including an unavailable, suspended or stale owner.
- **UnexpectedUnowned:** no valid inventory, explicit bootstrap or hold path;
  this always fails the audit. A label or familiar prefix alone never exempts it.

The self-owned normal bootstrap seeds are `kube-system/kube-system`,
`kube-system/sealed-secret`, and `kube-system/rafag`. Their exact source paths,
committed seed entrypoint files and self-inventory membership are checked. See
[rafag-gitops-recovery.md](rafag-gitops-recovery.md) for bootstrap order, encrypted
credentials/private-key prerequisites and unchanged installer/source selection.

## Current explicit recovery policy

Names verified against the cluster on 2026-11-02:

- `default/Pod/immich-private-api`: restricted recovery, local database and
  read-only photos; no migration or fresh onboarding implied.
- `default/Pod/runwield-paperless-web`: failed RunWield recovery Pod; no repair
  or successful application acceptance implied.
- `default/Job/sonarr-transmission-private`: long-running combined recovery Job;
  changing to separate Deployments requires a reviewed migration.
- `default/Cluster/recovery-immich`: deliberately hibernated CNPG cluster;
  preserve hibernation. The report exposes the observed hibernation condition.
- `default/Cluster/recovery-paperless`: recovery database pending its own
  reviewed adoption/repair scope.
- Their currently generated PVCs `recovery-immich-1` and
  `recovery-paperless-1` derive the hold through verified Cluster owner UIDs,
  not a hardcoded PVC name or label. The two retained backing PVs can separately
  be actively inventoried by the repo; that does not adopt the database.

The report includes every named hold policy with a `present` flag, and every
observed derived hold. Policy is rafag-specific: it does not blanket-exempt
future `recovery-*`, `runwield-*` or bootstrap-like resources. Never remove a hold
or classify it active solely to improve a total. Adoption requires a separately
reviewed Git change that preserves data and the accepted runtime restrictions.

The suspended Home Assistant and SFTPGo HelmRelease **declarations** must still
have active Git ownership, but their held Helm controller state is explicitly
reported and is not required Ready to pass the declaration audit. Unexpected
release suspension or resuming either intentional hold fails the policy check. Their live
native workload must have a separate active inventory path; a suspended release
cannot confer active ownership on its chart children by itself.

## Exit status and interpreting completion

- `0`: no unexpected ownership or Flux currency failures; explicit recovery
  holds may remain. `fullGitOpsCompletion` stays false while any hold remains.
- `1`: unexpected unowned/noncurrent objects, invalid source or Kustomization
  status/revision, untracked Helm declaration, unsuspended nonready HelmRelease,
  malformed inventory, or (with `--strict`) any explicit recovery hold.
- `2`: command/query/argument failure; no complete census is claimed.

Even a strict pass would mean the stated ownership scope is complete, not that
all application/data/rebuild acceptance tests passed. Review `issues`,
`counts.classified`, `resources`, `kustomizations`, `helmReleases` and
`dependencyGraph`, not the exit status alone. BootstrapManaged remains a separate
installer boundary in both modes.

## Validation snapshot (2026-11-02)

At source/applied commit `a9d762638ae8cd4bec01dca32609f4f5b4b2ec33`,
the live census classified 58 objects: 44 ActiveGitOps, 7 BootstrapManaged and
7 ExplicitRecoveryHold; zero unexpected or noncurrent objects. All 13 Flux
Kustomizations were Ready/current at that revision. The 12 HelmRelease
declarations were tracked; Home Assistant and SFTPGo remained suspended.
Default mode exited 0 with `fullGitOpsCompletion: false`. Strict mode exited 1
solely because the seven recovery holds remain. These are point-in-time
observations, not a promise about later revisions.

Inline fixture checks additionally exercised chart children without Flux labels,
CronJob-to-Job ancestry, CNPG PVC hold inheritance, mismatched owner UIDs, stale
root SHA, stale Helm generation and strict hold failure. No cluster changes were
made by validation. Repository hook reported no staged files; targeted syntax,
whitespace, final-newline and size checks passed without staging anything.
