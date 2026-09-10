# K7 trial

K7 runs at `https://k7.dumbhome.uk` as a trial media server. It does not replace Plex.

## Runtime

- Release: `ghcr.io/kaybi-gh/k7:1.10.0`
- HTTP port in the container: `7080`
- Database: `k7-db`, managed by CloudNativePG
- Public URL: `https://k7.${CLUSTER_DOMAIN_NAME}`
- Required secret key: `K7_APIKEYS_HASH_SECRET` in the reflected `secrets` Secret

## Secret preparation

Before first run, make sure `K7_APIKEYS_HASH_SECRET` exists in `clusters/gandazgul/secrets.env`. This file is
ignored by Git. Keep the same value for the life of the trial so existing API keys stay valid. If the key is missing,
add a stable random value with at least 32 random bytes. Do not print the value in logs, issues, or reports.

After you add or change the value, run the existing sealing workflow:

```bash
./infrastructure/setup/configure-cluster.sh gandazgul
```

Review the generated `clusters/gandazgul/sealed-secret/SealedSecret.yaml` before commit. Do not commit
`clusters/gandazgul/secrets.env`.

K7 uses YASR for app-owned files:

| Purpose | PVC | SubPath | Mount path | Access |
|---|---|---|---|---|
| Server state | `yasr-volume` | `configs/k7/` | `/data` | Read/write |
| TV | `main-volume` | `public/TV` | `/media/tv` | Read-only |
| Movies | `main-volume` | `public/Movies` | `/media/movies` | Read-only |
| Music | `main-volume` | `public/Music` | `/media/music` | Read-only |

The read-only media mounts stop K7 from changing the shared Plex media files. K7 stores configuration, metadata,
logs, and transcode work files under `/data` on YASR.

## First-run setup

1. Wait for Flux, CNPG, and the K7 Deployment to become ready.
2. Get the setup token from the pod logs. Do not paste the token into issues or reports:

   ```bash
   kubectl -n default logs deployment/k7 | grep K7_SETUP_TOKEN
   ```

3. Open `https://k7.dumbhome.uk`.
4. Create the first administrator account with the setup token.
5. In the K7 admin UI, add these libraries:

   | Library | Content type | Path |
   |---|---|---|
   | TV | TV | `/media/tv` |
   | Movies | Movies | `/media/movies` |
   | Music | Music | `/media/music` |

6. Scan the libraries.
7. Test one TV episode, one movie, and one music track.

K7 stores library definitions in its database. This overlay does not create them automatically.

## Checks

Use these commands after Flux reconciles the app:

```bash
kubectl -n default get clusters.postgresql.cnpg.io k7-db
kubectl -n default get kustomizations.kustomize.toolkit.fluxcd.io k7
kubectl -n default rollout status deployment/k7 --timeout=10m
curl -fsS https://k7.dumbhome.uk/alive
curl -fsS https://k7.dumbhome.uk/health
```

Restart the Deployment after setup and confirm that the account, libraries, and scanned state remain.

## Safe removal

Before you remove this trial, review what Flux will prune. Do not delete `main-volume`, `yasr-volume`, Plex data,
or shared media. CNPG and local PVC reclaim policy can keep database storage after resource removal, so review the
retained volumes before you delete app state.
