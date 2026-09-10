---
planId: "e7716ac7-ac22-40fa-88e2-e96f1ee7b94e"
classification: "PLANNED_CHANGE"
workKind: "FEATURE"
complexity: "MEDIUM"
affectedPaths:
  - "apps/K7.yaml"
  - "apps/generic/overlays/k7/"
  - "clusters/gandazgul/apps/kustomization.yaml"
  - "clusters/gandazgul/sealed-secret/SealedSecret.yaml"
executionAgent: "engineer"
collaborationRecommendation: "autonomous"
createdAt: "2026-09-10"
status: "implemented"
origin: "internal"
userVerifiedAt: null
targetBranch: "main"
---

# Add K7 Media Trial

## Context

The user wants to test [K7](https://github.com/kaybi-gh/K7) alongside Plex at `https://k7.dumbhome.uk`. They requested a Generic overlay and approved PostgreSQL through the existing CNPG operator, read-only media mounts, separate YASR state, and K7's first-run local account wizard. Enable it only in the `gandazgul` Cluster config. Do not replace Plex or import its database.

Plex mounts `main-volume` subPath `public` at `/data`. The existing TV, Movies, and Music folders are `public/TV`, `public/Movies`, and `public/Music`. K7 reserves `/data` for its own state, so mount these libraries under `/media` instead.

Upstream evidence:
- [Install](https://github.com/kaybi-gh/K7/blob/v1.10.0/docs/admin/install.md) and [Compose](https://github.com/kaybi-gh/K7/blob/v1.10.0/docker-compose.yaml): published image, port 7080, persistent paths, first-run wizard.
- [Configuration](https://github.com/kaybi-gh/K7/blob/v1.10.0/docs/admin/configuration.md): PostgreSQL settings, required API-key hash secret, TLS proxy settings, and database-owned library definitions.
- [Entrypoint](https://github.com/kaybi-gh/K7/blob/v1.10.0/entrypoint.sh): starts as root, prepares `/data`, then runs as the configured user; does not change media ownership.
- Latest stable GitHub release at planning time: `v1.10.0`. Confirm the published image tag before use; do not use the chart's stale source `appVersion` as the image version.

## Objective

K7 runs as a separate, persistent media server. The user can create an administrator, add all three existing libraries, scan them, and test playback through HTTPS. K7 cannot write to the shared media folders. Plex and the other Cluster configs remain unchanged.

## Approach

```text
clusters/gandazgul/apps/kustomization.yaml
  -> apps/K7.yaml
       -> CNPG Cluster k7-db -> generated Secret k7-db-app
       -> Flux Kustomization k7
            -> apps/generic/overlays/k7 -> generic base
                 -> Ingress k7 -> Service k7:7080 -> Deployment k7
```

Use the existing Generic overlay structure, including resource rename patches and matching selectors. Keep one K7 replica and use `Recreate` to avoid two server processes sharing writable state during an update. The app uses CNPG-generated application credentials, not database superuser access.

| Purpose | PVC and subPath | K7 path | Access |
|---|---|---|---|
| Server state | `yasr-volume`, `configs/k7/` | `/data` | Read/write |
| TV | `main-volume`, `public/TV` | `/media/tv` | Read-only |
| Movies | `main-volume`, `public/Movies` | `/media/movies` | Read-only |
| Music | `main-volume`, `public/Music` | `/media/music` | Read-only |

Library definitions are stored in K7's database, not supplied through environment variables. The user adds these three paths in the admin UI after first-run setup. Do not add a bootstrap script or invent library environment variables.

K7 also has an official Helm chart, but the user explicitly requested a Generic overlay. SQLite would reduce resource use; the user approved CNPG instead. GPU passthrough, Plex metadata migration, federation, and optional integrations are outside this trial.

## Expected Change Surface

The boundaries this change is expected to touch. This list is guidance, not an allowlist: verify the real footprint
during implementation and change whatever the Implementation Steps need, including files not named here. Stop and report
only when discovery changes approved intent — the change reaches another subsystem, public behavior or architecture
shifts, migration or compatibility risk grows, or the Verification Plan no longer proves the objective.

- `apps/K7.yaml` — CNPG Cluster and app Flux Kustomization.
- `apps/generic/overlays/k7/` — overlay, Deployment/Service/Ingress patches, and a short trial setup README.
- `clusters/gandazgul/apps/kustomization.yaml` — activate this app only in the user's cluster.
- `clusters/gandazgul/secrets.env` (ignored) and `clusters/gandazgul/sealed-secret/SealedSecret.yaml` — persist K7's required hash secret through the existing secret process.
- No shared base, PostgreSQL operator, Plex, global ingress, or storage resource changes are expected. This app uses existing domain terms; no glossary changes are needed.

## Reuse Opportunities

- `apps/generic/base/` and `apps/generic/overlays/jellyfin/` — standard Deployment, Service, Ingress, labels, rename patches, and hostname substitution.
- `apps/BookOrbit.yaml` — combined database and Flux wrapper shape. Do not copy its vector extensions or superuser credentials.
- `apps/Paperless.yaml` — simple CNPG database/owner bootstrap and generated application credentials.
- `apps/generic/overlays/bookorbit/patches/deployment.yaml` — YASR state, UID/GID 1000, and Secret references.
- `infrastructure/setup/configure-cluster.sh` — existing Sealed Secret generation and application. It changes the live cluster; it is not a dry-run check.

## Implementation Steps

1. **K7 has a private, persistent PostgreSQL database.** `apps/K7.yaml` declares `default/k7-db`, one instance, database and owner `k7`, and a 10Gi dynamically provisioned volume using the existing default storage class. Follow the operator's existing default PostgreSQL image policy. No superuser access, custom extensions, external database port, or new operator is introduced. Its Flux Kustomization points to `./apps/generic/overlays/k7/`, uses the existing GitRepository in `kube-system`, interval `1h`, prune, a `default/k7` Deployment health check, and `Secret/secrets` substitutions.

2. **The overlay produces a working K7 server, not just renamed base resources.** It renders one Deployment, one ClusterIP Service, and one Ingress named `k7` in `default`. Labels and selectors match. Use `ghcr.io/kaybi-gh/k7:1.10.0` with `IfNotPresent` after confirming that tag exists for the node architecture. If that exact tag is unavailable, identify the immutable image for release v1.10.0; do not silently switch to `latest`. The Service exposes named port `http`, TCP 7080, targeting the container's named port `http` at 7080. The Deployment has one replica and `Recreate` strategy.

   Set these environment values:
   - `Database__Provider=Postgres`, `Database__Port=5432`.
   - `Database__Server`, `Database__UserID`, `Database__Password`, `Database__Name` from `k7-db-app` keys `host`, `username`, `password`, `dbname` respectively.
   - `Security__ApiKeys__HashSecret` from `Secret/secrets`, key `K7_APIKEYS_HASH_SECRET`, using `valueFrom.secretKeyRef` with no optional or fallback value.
   - `BaseUrl=https://k7.${CLUSTER_DOMAIN_NAME}` and `Security__ForceHttps=true`.
   - `Paths__Config=/data/config`, `Paths__Metadatas=/data/metadatas`, `Paths__Logs=/data/logs`, `Paths__Transcoding=/data/transcoding`.
   - `PUID=1000`, `PGID=1000`, and `TZ=${CLUSTER_TIME_ZONE}`, following existing local app ownership conventions.

   Install the four mounts in the table, with explicit `readOnly: true` on all three media mounts. Do not mount all of `public`, Plex configuration, a GPU, or unrelated host directories. Keep the upstream entrypoint; do not force a non-root startup that prevents its user remapping. Set `allowPrivilegeEscalation: false`. Suggested trial resources: requests 250m CPU/512Mi memory, limits 2 CPU/2Gi memory. Use `/alive` on port `http` for startup and liveness, and `/health` for readiness. Allow at least five minutes for startup before liveness begins; database unavailability must not be treated as a liveness failure.

3. **HTTPS reaches K7 with its own authentication intact.** The Ingress backend is `k7`, and both rule host and TLS host are `k7.${CLUSTER_DOMAIN_NAME}`. Reuse nginx and `internal-ingress-cert`. Include standard Forecastle name `K7`, group `Media`, and expose annotations. Do not copy BookOrbit's Kobo-specific buffers. Check inherited ingress error handling: preserve K7's own authentication/API responses with app-local settings if necessary; do not change global ingress configuration. Keep local login enabled, public registration disabled, and guest access disabled. Do not add SSO or unattended administrator credentials.

4. **The required secret and activation are complete.** Generate a stable random hash secret (at least 32 random bytes) only if `K7_APIKEYS_HASH_SECRET` does not exist. Store it in the ignored cluster env file without printing it. Use `./infrastructure/setup/configure-cluster.sh gandazgul` with the verified intended cluster context to produce the Sealed Secret. Review unrelated generated changes before committing. Never commit plaintext credentials, generated Secret manifests, or setup tokens. Enable `../../../apps/K7.yaml` only in `clusters/gandazgul/apps/kustomization.yaml`. If cluster access or sealing tools are unavailable, report that prerequisite as incomplete rather than substitute a placeholder secret.

5. **The trial has an accurate setup guide.** The overlay README identifies the URL, release, PostgreSQL dependency, all storage paths, secret preparation, and how the user obtains the first-run token privately from `kubectl -n default logs deployment/k7`. It instructs the user to create the first administrator, add TV/Movies/Music libraries at the paths above with the matching content types, scan, and test one item from each. Explain that read-only mounts prevent media edits and that scan/transcode state uses YASR. No automatic library registration is claimed. Include restart checks and safe removal guidance: review Flux pruning and CNPG/PVC retention before removing the app; never delete shared PVCs or Plex data.

## Approval Confirmation

No Work Records are superseded. The user approved PostgreSQL, read-only libraries, and the trial scope in this conversation.

## Verification Plan

### Static and rendered checks

Run from the repository root:

```bash
kustomize build apps/generic/overlays/k7
kustomize build --load-restrictor LoadRestrictionsNone clusters/gandazgul/apps
kustomize build --load-restrictor LoadRestrictionsNone clusters/rafag/apps
kustomize build --load-restrictor LoadRestrictionsNone clusters/renepor/apps
kustomize build apps/generic/overlays/k7 | \
  CLUSTER_DOMAIN_NAME=dumbhome.uk CLUSTER_TIME_ZONE=America/New_York \
  flux envsubst --strict > /tmp/k7-rendered.yaml
kubectl apply --dry-run=client -f /tmp/k7-rendered.yaml
kubectl apply --dry-run=client -f apps/K7.yaml
git diff --check
node scripts/pre-commit.js
```

The pre-commit script checks staged files and can fix/restage them; run after staging only the intended changes. It does not implement the documented `--all` flag. `kustomize`, `kubectl`, and `flux` were available during planning; `yamllint` was not. Run `yamllint` on the changed YAML if available. Kubernetes custom-resource validation requires the relevant cluster schemas; report unavailable checks precisely.

Inspect parsed rendered resources, not only source text:
- Exactly the three app resources have name `k7`; selectors, Service target port, and Ingress backend form a connected route to port 7080.
- Rendered URL, `BaseUrl`, and TLS host resolve to `k7.dumbhome.uk`; no unresolved variables or `changeme` image remain.
- All four mounts have the exact PVC/subPath/path/access mapping above. Three separate read-only media mounts are required.
- All database Secret keys and the required hash-secret reference are present; persistent `Paths__*` values and process/database-specific probes are correct.
- The gandazgul app build includes `k7-db` and Flux Kustomization `k7`; family cluster builds contain neither. Compare output with the pre-change build to detect unintended changes to existing apps.
- Verify image availability using `podman manifest inspect ghcr.io/kaybi-gh/k7:1.10.0`. No container build is required.

### Runtime and user checks

After the approved change is reconciled by Flux, verify the intended cluster context and run:

```bash
kubectl -n default get clusters.postgresql.cnpg.io k7-db
kubectl -n default get kustomizations.kustomize.toolkit.fluxcd.io k7
kubectl -n default rollout status deployment/k7 --timeout=10m
curl -fsS https://k7.dumbhome.uk/alive
curl -fsS https://k7.dumbhome.uk/health
```

- CNPG is ready, K7 connects with application credentials, migrations complete, and the Deployment becomes ready. Review logs privately; do not paste setup tokens into reports.
- Inspect container mount information to confirm all three media mounts are read-only. As the runtime app user, list and read an existing sample file in each library. Do not test by modifying existing media or changing host ownership.
- User opens HTTPS, gets a valid certificate, completes token-protected setup, and signs in without a redirect loop or cookie error. Signed-out access must not expose media.
- User adds all three libraries, scans them, and plays one TV episode, movie, and music track. Confirm byte-range seeking and that ingress does not replace app responses with an unrelated error page. Record codec-specific limitations instead of expanding scope to GPU support.
- Restart the K7 Deployment once after setup. The account, libraries, and scanned state remain. `/health` returns success and the setup wizard does not return. Plex still reads and plays the same shared media.

These route, media-read, scan/playback, and restart checks fail for a renamed placeholder deployment or an overlay that only exposes an empty application. Builds alone do not prove the trial works. If runtime access is unavailable or the user has not completed setup, clearly separate validated manifests from pending runtime acceptance.

## Edge Cases & Considerations

- **Startup order:** The database, generated credentials, and reflected secret can appear after the Deployment. Kubernetes and Flux retry. Do not replace missing credentials with defaults or tie liveness to PostgreSQL health.
- **Permissions:** UID/GID 1000 matches neighboring apps, but verify readability on the actual media. Do not recursively chown shared media or set a pod-wide filesystem group that could change shared volume ownership.
- **Persistent storage:** Use only `configs/k7/` for K7-owned state. Metadata and transcodes can consume substantial YASR space; monitor the first scan. Database storage size and resource limits are initial trial settings, not capacity guarantees.
- **Public setup:** Keep the token-protected wizard and do not enable guest access or registration. Let the user retrieve the token and enter their own administrator password.
- **DNS/TLS:** Existing wildcard DNS/certificate coverage is an assumption to verify. If missing, report the required K7 DNS/certificate change; do not alter unrelated routing.
- **Updates/removal:** Pin the release to avoid unplanned migrations. K7 applies database migrations on startup; image rollback alone is not a database rollback. Do not remove state during the trial or promise automatic CNPG backup coverage.
