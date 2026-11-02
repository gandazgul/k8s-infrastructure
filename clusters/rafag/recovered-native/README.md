# Recovered native ownership boundaries

These are identity-preserving definitions of the running recovery workloads. Keep
all startup/network/mount guards, restart annotations and persisted-data subpaths.
Do not replace recovery storage with empty directories or fresh application setup.

## Held SFTPGo Helm boundary

The existing `default/sftpgo` HelmRelease remains suspended and is adopted
separately. Its current native Deployment, Services, configuration and routes
deliberately differ from that held release. Their direct Flux adoption is an
explicit exception; do not resume Helm or copy these objects into an active chart.
The exported ConfigMaps were scanned in memory: no private-key material or
nonempty credential strings were found. The `prefer_database_credentials` field
is a boolean setting, not credential material. No Secret values were read.

The existing `sftpgo-working` PV/PVC is retained, prune-protected and kept at its
real `/media/yasr` path with the original node affinity and explicit claim binding.
Binding-controller UID/resourceVersion fields are runtime state, not Git values.
Do not force-recreate or resize this storage, or overwrite the existing database,
credentials, host keys or data. Restore those private files through the separate
data/key recovery process, never plaintext Git.

Mealie and n8n retain their existing Secret references. This leaf depends on the
real sibling `default/recovered-app-secrets` root for encrypted credential restore,
not a placeholder dependency. Publication requires that sibling to be reachable
from the approved parent and Ready with matching existing credential bytes.

`RetainedVolumes.yaml` preserves the existing read-only Plex legacy-media PV/PVC
and the two static database-recovery PVs. All are Retain/prune-protected; claim
binding identities and local paths are unchanged. The CNPG-generated PVCs remain
owned by their existing Cluster controllers, not duplicated as native claims.
The recovery Cluster CRs and standalone app Pods/Job remain explicitly held for
a separate guarded adoption/controller review; adopting storage does not resume
or initialize a database. Git does not restore the underlying data or mounts.
