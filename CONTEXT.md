# k8s-infrastructure — Context Overview

A GitOps repository for a home-lab Kubernetes cluster on Fedora server managed
with [Flux v2](https://toolkit.fluxcd.io/). The cluster is a single-node
control-plane+worker running on a small business server. Storage uses local
host-path PVs mapped to three HDD mount points (`/media/main`, `/media/backup`,
`/media/yasr`). The domain `dumbhome.uk` routes to the cluster via Cloudflare
DNS and NGINX Ingress with cert-manager (Let's Encrypt + Cloudflare DNS-01).

**Node version (build scripts):** v24 (.nvmrc)

## Language

### Key Concepts

| Term                     | Definition                                                                                                                    | Aliases to avoid |
| ------------------------ | ----------------------------------------------------------------------------------------------------------------------------- | ---------------- |
| **YASR**                 | Yet Another Storage Repository — the `/media/yasr` volume where all application configs are stored via subPaths               |                  |
| **main-volume**          | The 4Ti HDD at `/media/main` housing user data (photos, media, documents)                                                     |                  |
| **backup-volume**        | The 4Ti HDD at `/media/backup` used as rdiff-backup destination for incremental backups                                       |                  |
| **Flux Kustomization**   | A `kustomize.toolkit.fluxcd.io/v1.Kustomization` that tells Flux which directory to sync and apply                            | Kustomization    |
| **HelmRelease**          | A `helm.toolkit.fluxcd.io/v2.HelmRelease` wrapping a Helm chart installation via Flux                                         |                  |
| **Generic overlay**      | The `apps/generic/base/` + `apps/generic/overlays/<app>/patches/` Kustomize pattern for custom (non-Helm) apps                |                  |
| **Sealed Secret**        | A `SealedSecret` resource encrypted by kubeseal; the cluster's SealedSecretsController decrypts it to a plain Secret          |                  |
| **Reflector**            | The emberstack/reflector add-on that auto-mirrors Secrets across namespaces via annotations                                   |                  |
| **Cluster config**       | A per-user directory under `clusters/<username>/` containing `ClusterKustomization.yaml`, `secrets.env`, and `sealed-secret/` |                  |
| **Hostpath Provisioner** | kubevirt/hostpath-provisioner DaemonSet that dynamically provisions local PVs from `StorageClass: hostpath`                   |                  |
| **CNPG**                 | CloudNative PostgreSQL operator — manages PostgreSQL clusters via `postgresql.cnpg.io/v1.Cluster` resources                   |                  |
| **Forecastle**           | Service discovery dashboard (stakater/Forecastle) that lists apps via ingress annotations                                     |                  |
| **ACME**                 | Let's Encrypt certificate issuance; this cluster uses DNS-01 via Cloudflare API                                               |                  |

## Key Files

### Entry Points

| File                                        | Purpose                                                                                                             |
| ------------------------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| `clusters/<user>/ClusterKustomization.yaml` | Root Flux Kustomization per cluster; pulls everything else via `path:`                                              |
| `infrastructure/kube-system/`               | Bulk of core infra Flux Kustomization manifests (Storage, Monitoring, IngressNginx, CertManagerKustomization, etc.) |
| `infrastructure/setup/install-flux.sh`      | Bootstraps a new cluster: installs Flux, Sealed Secrets, GitRepo source, and runs configure-cluster                 |
| `infrastructure/setup/configure-cluster.sh` | Encrypts secrets.env → SealedSecret and generates per-app value secrets                                             |
| `containers/container-build.js`             | Orchestrates podman multi-arch builds for all custom containers                                                     |
| `apps/generic/base/`                        | Reusable base Deployment + Service + Ingress for custom apps                                                        |

### Config Files

| File                    | Purpose                                                                                      |
| ----------------------- | -------------------------------------------------------------------------------------------- |
| `AGENTS.md`             | Master agent instructions for AI coding assistants                                           |
| `_config.yml`           | Jekyll config for GitHub Pages documentation site                                            |
| `.husky/pre-commit`     | Husky git hook that runs `scripts/pre-commit.js` on every commit                             |
| `scripts/pre-commit.js` | JS-native pre-commit checks: trailing-whitespace, end-of-file-fixer, check-added-large-files |
| `package.json`          | Node project metadata; dependencies: `minimist`, `husky` (dev)                               |

### Documentation

| File                                                    | Purpose                                                                              |
| ------------------------------------------------------- | ------------------------------------------------------------------------------------ |
| `index.md`                                              | GitHub Pages landing page — getting-started guide, service table, cluster setup docs |
| `README.md`                                             | Overview, YASR explanation, license, contributing guide                              |
| `infrastructure/storage/hostpath-provisioner/README.md` | Docs for the kubevirt hostpath-provisioner setup                                     |

## Patterns & Conventions

### Application Deployment (Two Patterns)

1. **HelmRelease pattern** — For apps with official Helm charts (Plex,
   Forecastle, Headlamp, ActualBudget, Harbor, etc.):
   - Place a single `PascalCase.yaml` in `apps/` containing `HelmRepository` (if
     not global) + `HelmRelease`
   - Reference global `HelmRepository` resources in
     `infrastructure/kube-system/repos/`
   - Use `${VAR}` substitution via Flux `postBuild.substituteFrom` (from Sealed
     Secrets)

2. **Generic Kustomize overlay pattern** — For custom or non-Helm apps (Goaly,
   Gotify, Jellyfin, Mealie, etc.):
   - Base template at `apps/generic/base/` (Deployment + Service + Ingress)
   - Per-app overlay at `apps/generic/overlays/<app>/` with patches in
     `patches/`
   - Patches use `allowNameChange: true` to rename the resources from
     `deployment` → `<app>`
   - App definition in `apps/<App>.yaml` is a Flux `Kustomization` pointing to
     the overlay path

### CronJob Deployment

- Template base at `infrastructure/cronjob/` (cronjob.yaml + kustomization.yaml)
- A Flux Kustomization in `infrastructure/kube-system/` or
  `clusters/<user>/apps/` instantiates it with:
  - `postBuild.substitute` for `CRONJOB_NAME`, `SCHEDULE`, `IMAGE`, `NAMESPACE`
  - Strategic merge patches to add volumes, volumeMounts, env vars, and args
- Examples: `BackupCronJobs.yaml` (rdiff-backup), `CloudflareDDNS.yaml`,
  `ImmichBackupCronJob.yaml`, `PlexBackupCronJob.yaml`

### Storage Convention

- All app configs use the `yasr-volume` PVC (`/media/yasr`) with a unique
  `subPath: configs/<app>/`
- User data uses `main-volume` PVC (`/media/main`) with appropriate `subPath`
- Backup targets use `backup-volume` PVC (`/media/backup`)
- PVs are declared in `infrastructure/storage/pv/pv.yaml` (templated via Flux
  substitution)
- PVCs in `infrastructure/storage/pvc/pvc.yaml` (same template)
- `StorageClass: hdd` maps to the hostpath-provisioner

### Secrets Management

- Raw secrets in `clusters/<user>/secrets.env` — **gitignored**
- Run `infrastructure/setup/configure-cluster.sh` to regenerate
  `SealedSecret.yaml` from `secrets.env`
- SealedSecrets use reflector annotations to auto-mirror to `default` and
  `monitoring` namespaces
- App-specific value files go in `clusters/<user>/apps/values/*.yaml` and are
  converted to Secrets
- Apps reference secrets via `valuesFrom` (HelmRelease) or
  `postBuild.substituteFrom` (Kustomization)

### Code Style

| Aspect                | Convention                                                                                           |
| --------------------- | ---------------------------------------------------------------------------------------------------- |
| YAML indentation      | Strictly 2 spaces, no tabs                                                                           |
| YAML document sep     | Always `---` between K8s objects in a file                                                           |
| App file naming       | `PascalCase.yaml` (e.g., `HomeAssistant.yaml`, `Paperless.yaml`)                                     |
| K8s resource naming   | `lower-kebab-case` (deployments, services, PVCs, namespaces)                                         |
| Infrastructure naming | `PascalCase` for new files, some legacy kebab-case tolerated                                         |
| JS (build scripts)    | ESM (`import`), 4-space indent, `try-catch` with `process.exit(1)`, `else/catch/finally` on new line |
| JS (container apps)   | ESM (`type: module`, `import`), same formatting otherwise                                            |
| Shell scripts         | `#!/bin/bash`, `set -e`, curly braces on vars (`${VAR}`), fail fast                                  |

### Containers

- Custom containers live in `containers/<name>/` with a `Containerfile` or
  `Dockerfile`
- Build: `node containers/container-build.js --image=<name>`
- Run: `node containers/container-run.js --image=<name>`
- Uses podman multi-arch builds (linux/amd64, linux/arm64) pushed as manifests
- Image tagging: `docker.io/<user>/<name>:v<githash>` + `:latest`
- Existing containers: plex-backup (bash), immich-backup (JS+K8s API),
  rdiff-backup (alpine+rdiff-backup), ddns-cloudflare (JS+Cloudflare SDK),
  transmission-pia-port-forward (bash+cron)

### Linting & Validation

- Pre-commit hooks (JS-native via husky): `trailing-whitespace`,
  `end-of-file-fixer`, `check-added-large-files` — see `scripts/pre-commit.js`
- `yamllint` for manual YAML validation
- `kubectl apply --dry-run=client -f <file>` for manifest validation
- `kustomize build <dir>` for overlay validation
- No automated unit/integration test suite exists

### Multi-Cluster Support

- Three cluster configs: `gandazgul` (primary), `rafag` (family), `renepor`
  (family)
- Each has its own `secrets.env`, `SealedSecret`, and
  `ClusterKustomization.yaml` with per-cluster substitutions (PHOTOS_PATH,
  PHOTOS_UID/GID, BITWARDEN_SUBDOMAIN, etc.)
- Shared infrastructure in `infrastructure/` is cluster-agnostic

### Domain Terminology Conventions

- `CLUSTER_DOMAIN_NAME` — the base domain (typically `dumbhome.uk`)
- `CLUSTER_NAME` — the name of this specific K8s cluster (e.g., `gandazgul`)
- `CONTROL_PLANE_IP` / `CONTROL_PLANE_NAME` — auto-detected during
  `install-flux.sh`
- `KUBECTX_NAME` — kubectx context name for the cluster (e.g., `home`)
- `DYN_DNS_NAME` — the dynamic DNS hostname for external access
