# Recovered Helm ownership and credential-preserving values migration

Scope: adopt existing `default/{bitwarden,forecastle,mosquitto,plex,sftpgo}`
HelmReleases, not their chart-created children. SFTPGo stays suspended. No chart,
image, release name, storage namespace, target namespace, credential, Deployment
type, controller, or Pod-template change is part of this migration.

## Repository ownership

- `apps/RecoveredAppSecrets.yaml` owns the encrypted values root. It waits for
  the existing sealed-secret root and explicitly checks all eight SealedSecrets
  for current-generation `Synced=True` before becoming Ready.
- `clusters/rafag/recovered-app-secrets/EncryptedValues.yaml` contains five
  dedicated `<release>-gitops-values` Secrets and byte-preserving encrypted
  copies of existing `plex-values`, `mealie-recovery-env` and
  `n8n-private-existing-key`. Sealing uses the current controller's public
  certificate, strict name/namespace scope and in-memory plaintext only.
- `CredentialAdoption.yaml` contains metadata-only `Secret` objects with SSA
  Merge, managed adoption and prune protection. Their annotations/labels match
  the encrypted templates, preserving existing bytes/UIDs and avoiding owner
  metadata fights. These are not empty replacement Secret payloads.
- `AdoptionBaseline.json` records existing object UIDs and whole-input hashes,
  never raw values. It is a one-time migration drift guard, not a secret store.
- `apps/RecoveredHelm.yaml` depends on the secret root plus existing real
  infrastructure/storage roots. Its four active HRs are explicit health checks;
  held SFTPGo is intentionally excluded from active readiness checks.
- `clusters/rafag/recovered-helm/` keeps each full current HR spec except moving
  inline values into its final dedicated values reference. Existing prefix
  references retain exact order/options. Held SFTPGo remains suspended and all
  HRs are prune-protected. Both roots use prune=false, Orphan and force=false.

The existing reflected `default/secrets` remains owned through its existing
parent/controller; this migration does not duplicate or rotate it. Restore the
SealedSecrets decryption key through the established private recovery procedure;
never put a private key or plaintext Secret in this repository.

## Why a guarded one-time patch is necessary

Actual server-side-apply dry-runs with field-manager `kustomize-controller`
showed that `{}`, null and omission all preserve inline fields owned by prior
kubectl managers. Committed YAML alone does not remove these live values.
Never use force/recreation to remove them: deleting an HR can uninstall its
release.

`scripts/adopt-recovered-helm-values.py` uses JSONPatch with UID/resourceVersion
tests to atomically change valuesFrom and remove inline values. It also removes
legacy last-applied annotations on these HRs, which can retain plaintext inline
credentials. The patch payload contains references and identity tests only,
never credential values. All five HRs prevalidate and server-dry-run before the
first write. A concurrent edit causes a stop, not an unconditional retry.

## Execute and verify

1. Review and commit the encrypted sources, HR sources, script, root declarations
   and normal parent ownership path. Activate the secret root first; do not
   activate legacy app collections, unsuspend held releases or reconcile child
   Deployments separately.
2. Require secret-root Ready at the reviewed Git revision and all eight current
   SealedSecrets Synced. Verify existing three Secret UIDs and whole-data hashes
   against `AdoptionBaseline.json`; raw bytes stay only in process memory.
3. Run the offline guard checks and then the default non-mutating server dry-run:

   ```bash
   python3 scripts/adopt-recovered-helm-values.py --self-test
   python3 scripts/adopt-recovered-helm-values.py
   ```

   Requires Python 3, PyYAML and the configured kubectl/kubeconfig. Do not use
   shell tracing or commands that print full Secret/HR bodies, annotations,
   resolved Helm values or kubectl debug output.
4. After review, execute the same validated transition:

   ```bash
   python3 scripts/adopt-recovered-helm-values.py --execute
   ```

   The script requires the dedicated decrypted JSON map to equal both captured
   and current inline inputs, exact existing valuesFrom prefix, unchanged
   remaining spec, expected HR UID/controller config digest, preserved existing
   Secret bytes/identities and SFTPGo suspension. It accepts an already-adopted
   state only when inline values are absent and references exactly match.
5. Reconcile the committed HR root through normal Git ownership. Require both
   roots Ready at the reviewed SHA; active HRs must observe current generation.
   Run the default script again for idempotent verification.
6. Compare before/after controller config digests, release history revisions,
   chart identities, HR/Secret UIDs, rendered Deployment templates and original
   Pod UIDs/restart counts. Require no upgrade, uninstall, credential change or
   rollout. Held SFTPGo's suspension must remain true; its retained status is not
   evidence of fresh reconciliation.

## Hash and precedence semantics

Verified controller v1.7.1 uses chartutil v1.35.0. References without targetPath
merge at the root in order, with inline values last. Appending the exact old
inline JSON map last and removing inline values therefore preserves the merged
input when existing references and their bytes remain unchanged. These five
declarations have no targetPath references; the script rejects such a reference
instead of guessing its precedence.

The script's `inline-input-sha256` and existing-Secret data hashes use sorted,
compact JSON. They prove exact captured-input identity, **not** the controller's
config digest. Flux computes its own config digest by sorted YAML encoding of
merged values. Keep the recorded `controller-config-digest` unchanged and verify
it after reconciliation. In the controller, unchanged chart name/version and
merged-value digest select the InSync path instead of a Helm upgrade; independent
force requests, tests or other concurrent changes still require investigation.

## Stop/recovery boundaries

On any prevalidation failure, perform no migration write. On a UID/resourceVersion
conflict or failure partway through a batch, stop and inspect the exact source of
drift. Each successful HR transition is individually atomic; rerunning is safe
after the discrepancy is understood because completed transitions are detected.
Do not automatically restore plaintext inline values, delete/recreate releases,
rotate credentials, clear holds or weaken guards. Preserve the already-created
encrypted Secrets and running workloads while investigating. These encrypted
sources preserve configuration but do not substitute for application-data or
private decryption-key backups.

Primary implementation references:

- <https://github.com/fluxcd/helm-controller/blob/v1.7.1/internal/controller/helmrelease_controller.go>
- <https://github.com/fluxcd/helm-controller/blob/v1.7.1/internal/action/verify.go>
- <https://github.com/fluxcd/pkg/blob/chartutil/v1.35.0/chartutil/values.go>
- <https://github.com/fluxcd/pkg/blob/chartutil/v1.35.0/chartutil/digest.go>
- <https://github.com/bitnami-labs/sealed-secrets#managing-existing-secrets>
