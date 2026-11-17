# Cinephage

Cinephage 0.18.1 is enabled only for the `gandazgul` Cluster config.
After Flux applies the change, open <https://cinema.dumbhome.uk>.
The first start can take several minutes while the image downloads Camoufox.
The startup probe allows 15 minutes.

## Storage and secrets

| Container path | PVC | subPath | Access |
|---|---|---|---|
| `/config` | `yasr-volume` | `configs/cinephage/` | Read/write |
| `/data/downloads` | `yasr-volume` | `configs/transmission/downloads/` | Read/write |
| `/media/movies` | `main-volume` | `public/Movies/` | Read/write |
| `/media/tv` | `main-volume` | `public/TV/` | Read/write |

SQLite, credentials, and browser cache persist under `/config`.
The upstream entrypoint prepares this directory, then runs as UID/GID 1000.
Only browser shared memory at `/dev/shm` uses a temporary memory volume.
One replica and the `Recreate` strategy prevent overlapping SQLite writers during updates.

`BETTER_AUTH_SECRET` comes from the reflected `secrets` Secret, key
`CINEPHAGE_AUTH_SECRET`. Its original value is in the ignored
`clusters/gandazgul/secrets.env`; its encrypted value is in the cluster's
Sealed Secret. Keep a secure backup. Changing this value invalidates sessions
and can make stored credentials unrecoverable. Do not generate a new value on restart.

## First-run setup

1. Open the HTTPS address and create the first administrator account promptly.
2. Supply your own [TMDB API key](https://www.themoviedb.org/settings/api).
3. Add movie root `/media/movies` and TV root `/media/tv`.
4. Set the External URL to `https://cinema.dumbhome.uk`.
5. Configure indexers and quality profiles in Cinephage.

Cinephage can change files in both shared libraries. Sonarr, Radarr, Prowlarr,
and Seerr remain unchanged. Do not enable duplicate searches, upgrades, or
imports for the same titles in multiple managers. Review task settings before
turning on automation.

## Connect Transmission

Under **Settings > Integrations > Download Clients**, add Transmission:

- Host: `transmission.default.svc.cluster.local`
- Port: `9091`
- SSL: off for this internal cluster connection
- URL Base: leave blank; Cinephage uses `/transmission/rpc`
- Credentials: use the existing RPC credentials if required
- Category: use a separate category such as `cinephage`

Click **Test**, then save. Completed downloads under `/data/downloads` are
visible at the same path in both applications. No remote path mapping is needed
for this folder. Existing category folders `/data/movies`, `/data/tv`, and
`/data/books` are not mounted. Do not adopt their jobs without first reviewing
storage access and ownership by the existing managers.

Downloads are on YASR; libraries are on `main-volume`. Use **Copy** for imports
to preserve torrent seeding. Hardlinks cannot cross these filesystems.
Do not enable automatic torrent removal during the initial test.
This deployment does not change Transmission settings or connect it automatically.

## Connect Overseerr or Seerr

Cinephage has a Radarr/Sonarr compatibility API. Upstream marks it as WIP.
Your cluster uses Seerr; its existing server connections are not changed here.

1. Enable **Radarr/Sonarr Compatibility** under **Settings > System > General**.
2. Generate or copy the **Main API Key** from that page.
3. Add test Radarr and Sonarr servers in Seerr using the connection URLs shown
   by Cinephage. The URL bases are `/api/radarr` and `/api/sonarr` respectively.
   Use the Cinephage Main API Key, not the streaming key.
4. Select the matching root folder and quality profile. Test the connection
   and one request before changing any default server.

See the [upstream compatibility guide](https://docs.cinephage.net/guides/configure/system/arr-compat)
and [Transmission guide](https://docs.cinephage.net/guides/configure/download-clients/transmission).

## Check after Flux reconciliation

```bash
kubectl --context home -n default rollout status deployment/cinephage --timeout=15m
curl --fail https://cinema.dumbhome.uk/api/health
```

Confirm that HTTPS has a valid certificate and login works. After initial setup,
restart the Deployment once and confirm that the account and settings remain.
Test one download and copy import before enabling unattended operation.

To remove Cinephage, remove its entry from the gandazgul app list and let Flux
prune its resources. Do not delete shared PVCs, media files, Transmission data,
or the permanent auth secret as part of removal.
