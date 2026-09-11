# Seerr Migration Runbook

This runbook migrates gandazgul from Overseerr to Seerr. Use it with the
approved plan `docs/plans/migrate-overseerr-to-seerr.md`. Rafag is out of
scope for this run because it is unreachable.

Seerr automatically migrates Overseerr data on first start. Do not start Seerr
until Overseerr is stopped and the data backup is complete.

## Facts

- New chart: `oci://ghcr.io/seerr-team/seerr/seerr-chart`, tag `3.9.1`.
- New app image: `ghcr.io/seerr-team/seerr:v3.4.1`.
- Existing data stays on `yasr-volume`, subPath `configs/overseerr`.
- Existing URL stays `https://media.${CLUSTER_DOMAIN_NAME}`.
- Seerr runs as UID/GID `1000` and writes to `/app/config`.
- `ReadWriteOnce` does not stop two pods on the same node from writing to the
  same SQLite database. Stop the old pod before Seerr starts.

## Required Inputs

Set these values for gandazgul:

```bash
export CTX="home"
export CLUSTER="gandazgul"
export NS="default"
export BACKUP_DIR="${HOME}/seerr-migration-${CLUSTER}-$(date +%Y%m%d-%H%M%S)"
```

Confirm the context before you continue:

```bash
kubectl --context "${CTX}" config current-context
kubectl --context "${CTX}" get kustomization "${CLUSTER}" -n kube-system
kubectl --context "${CTX}" get helmrelease overseerr -n "${NS}"
```

Stop if the context does not match the cluster.

## Baseline Before Outage

Create a private working directory. Do not commit files from this directory.

```bash
mkdir -p "${BACKUP_DIR}"
chmod 700 "${BACKUP_DIR}"
```

Record the old release and workload data:

```bash
kubectl --context "${CTX}" get helmrelease overseerr -n "${NS}" -o yaml \
  > "${BACKUP_DIR}/overseerr-helmrelease.yaml"
helm --kube-context "${CTX}" get values overseerr -n "${NS}" --all \
  > "${BACKUP_DIR}/overseerr-helm-values.yaml"
helm --kube-context "${CTX}" get manifest overseerr -n "${NS}" \
  > "${BACKUP_DIR}/overseerr-helm-manifest.yaml"
kubectl --context "${CTX}" get deploy,statefulset,svc,ingress -n "${NS}" \
  | grep -Ei 'overseerr|seerr' | tee "${BACKUP_DIR}/old-resources.txt"
kubectl --context "${CTX}" get pods -n "${NS}" \
  -l app.kubernetes.io/instance=overseerr -o wide \
  | tee "${BACKUP_DIR}/old-pods.txt"
```

Record the running image ID:

```bash
kubectl --context "${CTX}" get pod -n "${NS}" \
  -l app.kubernetes.io/instance=overseerr \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{range .status.containerStatuses[*]}{.image}{"\t"}{.imageID}{"\n"}{end}{end}' \
  | tee "${BACKUP_DIR}/old-image-id.txt"
```

Inspect data layout and ownership without printing secrets:

```bash
POD="$(kubectl --context "${CTX}" get pod -n "${NS}" \
  -l app.kubernetes.io/instance=overseerr \
  -o jsonpath='{.items[0].metadata.name}')"

kubectl --context "${CTX}" exec -n "${NS}" "${POD}" -- \
  sh -c 'id; find /app/config -maxdepth 3 -exec stat -c "%u:%g %a %n" {} \\; | sed -n "1,80p"' \
  | tee "${BACKUP_DIR}/config-ownership-sample.txt"

kubectl --context "${CTX}" exec -n "${NS}" "${POD}" -- \
  sh -c 'find /app/config -maxdepth 3 -type f | sed -n "1,80p"' \
  | tee "${BACKUP_DIR}/config-file-sample.txt"
```

If the app uses SQLite, the database is usually under `/app/config/db`. Record
counts only. Do not export tokens or passwords.

```bash
kubectl --context "${CTX}" exec -n "${NS}" "${POD}" -- \
  sh -c 'find /app/config -maxdepth 4 -name "*.sqlite*" -o -name "*.db*"'
```

If `sqlite3` is present in the pod, record a small baseline:

```bash
kubectl --context "${CTX}" exec -n "${NS}" "${POD}" -- sh -c '
  DB="/app/config/db/db.sqlite3"
  test -f "${DB}" || exit 0
  command -v sqlite3 >/dev/null || exit 0
  sqlite3 "${DB}" "PRAGMA integrity_check;"
  sqlite3 "${DB}" "SELECT count(*) AS users FROM user;" 2>/dev/null || true
  sqlite3 "${DB}" "SELECT count(*) AS media_requests FROM media_request;" 2>/dev/null || true
'
```

Also collect a manual, secret-free baseline from the UI:

- Login works for an existing admin account.
- User count and a sample of user IDs or names.
- Request count and a sample of request IDs and statuses.
- Plex, Radarr, Sonarr, and Jellyfin integration names or URLs, with tokens
  hidden.
- Notification provider names, with tokens hidden.

## Prepare Git State

The preparation state adds `apps/Seerr.yaml` to the gandazgul app list with
`spec.suspend: true`. This lets Flux create the suspended HelmRelease without
starting Seerr.

After that state is committed and pushed, reconcile only after user approval:

```bash
flux --context "${CTX}" reconcile source git k8s-infrastructure -n kube-system
flux --context "${CTX}" reconcile kustomization "${CLUSTER}" -n kube-system
kubectl --context "${CTX}" get helmrelease seerr -n "${NS}" -o jsonpath='{.spec.suspend}{"\n"}'
kubectl --context "${CTX}" get pods -n "${NS}" \
  -l app.kubernetes.io/instance=seerr
```

Expected result: `spec.suspend` is `true` and there are no Seerr pods.

## Cut Over One Cluster

Run this section for **gandazgul** only. Rafag is intentionally not changed in
this run.

Suspend the parent Flux Kustomization and the old release:

```bash
flux --context "${CTX}" suspend kustomization "${CLUSTER}" -n kube-system
flux --context "${CTX}" suspend helmrelease overseerr -n "${NS}"
```

Stop the old workload. Find its kind first:

```bash
kubectl --context "${CTX}" get deploy,statefulset -n "${NS}" \
  -l app.kubernetes.io/instance=overseerr
```

If it is a Deployment:

```bash
kubectl --context "${CTX}" scale deployment overseerr -n "${NS}" --replicas=0
kubectl --context "${CTX}" wait -n "${NS}" --for=delete pod \
  -l app.kubernetes.io/instance=overseerr --timeout=5m
```

If it is a StatefulSet:

```bash
kubectl --context "${CTX}" scale statefulset overseerr -n "${NS}" --replicas=0
kubectl --context "${CTX}" wait -n "${NS}" --for=delete pod \
  -l app.kubernetes.io/instance=overseerr --timeout=5m
```

Confirm no old pod remains:

```bash
kubectl --context "${CTX}" get pods -n "${NS}" \
  -l app.kubernetes.io/instance=overseerr
```

## Back Up Stopped Data

Create a helper pod that mounts only `yasr-volume`. This pod does not run the
application.

```bash
cat > "${BACKUP_DIR}/backup-pod.yaml" <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: seerr-backup
  namespace: ${NS}
spec:
  restartPolicy: Never
  containers:
    - name: backup
      image: alpine:3.20
      command: ["sleep", "3600"]
      volumeMounts:
        - name: config
          mountPath: /data
          subPath: configs/overseerr
  volumes:
    - name: config
      persistentVolumeClaim:
        claimName: yasr-volume
EOF
kubectl --context "${CTX}" apply -f "${BACKUP_DIR}/backup-pod.yaml"
kubectl --context "${CTX}" wait -n "${NS}" --for=condition=Ready pod/seerr-backup --timeout=2m
```

Archive with numeric ownership:

```bash
kubectl --context "${CTX}" exec -n "${NS}" seerr-backup -- \
  tar --numeric-owner -czf /tmp/overseerr-config.tgz -C /data .
kubectl --context "${CTX}" cp \
  "${NS}/seerr-backup:/tmp/overseerr-config.tgz" \
  "${BACKUP_DIR}/overseerr-config.tgz"
shasum -a 256 "${BACKUP_DIR}/overseerr-config.tgz" \
  | tee "${BACKUP_DIR}/overseerr-config.tgz.sha256"
tar -tzf "${BACKUP_DIR}/overseerr-config.tgz" | sed -n '1,80p' \
  | tee "${BACKUP_DIR}/archive-contents.txt"
```

Test extraction on a copy:

```bash
mkdir -p "${BACKUP_DIR}/restore-test"
tar -xzf "${BACKUP_DIR}/overseerr-config.tgz" -C "${BACKUP_DIR}/restore-test"
find "${BACKUP_DIR}/restore-test" -maxdepth 3 -type f | sed -n '1,80p'
```

If SQLite is present and local `sqlite3` is available, run integrity check:

```bash
DB="${BACKUP_DIR}/restore-test/db/db.sqlite3"
if [ -f "${DB}" ] && command -v sqlite3 >/dev/null; then
  sqlite3 "${DB}" 'PRAGMA integrity_check;'
fi
```

## Correct Scoped Permissions

If ownership is not UID/GID 1000, fix only this mounted config directory. Do not
change `/media/yasr` or other app directories. Do not follow symlinks.

```bash
kubectl --context "${CTX}" exec -n "${NS}" seerr-backup -- \
  find -P /data -xdev -exec chown -h 1000:1000 {} +
```

Remove the helper pod after the backup and permission check:

```bash
kubectl --context "${CTX}" delete pod seerr-backup -n "${NS}" --wait=true
```

## Remove Old Release Before Starting Seerr

Delete the old HelmRelease while the parent Flux Kustomization stays suspended:

```bash
kubectl --context "${CTX}" delete helmrelease overseerr -n "${NS}" --wait=true
```

Wait until Helm removes the old resources:

```bash
kubectl --context "${CTX}" get deploy,statefulset,svc,ingress -n "${NS}" \
  | grep -Ei 'overseerr|seerr' || true
kubectl --context "${CTX}" get pods -n "${NS}" \
  -l app.kubernetes.io/instance=overseerr
```

Expected result: no Overseerr pod, Service, or Ingress remains. Do not continue
if any old writer remains.

## Start Seerr

Resume only the new HelmRelease. Keep the parent Flux Kustomization suspended
until the final Git state is ready.

```bash
flux --context "${CTX}" resume helmrelease seerr -n "${NS}"
flux --context "${CTX}" reconcile helmrelease seerr -n "${NS}"
kubectl --context "${CTX}" rollout status statefulset seerr -n "${NS}" --timeout=10m
kubectl --context "${CTX}" get pods -n "${NS}" \
  -l app.kubernetes.io/instance=seerr -o wide
kubectl --context "${CTX}" logs -n "${NS}" statefulset/seerr --tail=200 \
  | tee "${BACKUP_DIR}/seerr-startup.log"
```

Check the health endpoint from inside the cluster:

```bash
kubectl --context "${CTX}" run seerr-healthcheck -n "${NS}" \
  --rm -i --restart=Never --image=curlimages/curl:8.10.1 -- \
  curl -fsS http://seerr/api/v1/settings/public
```

## Functional Checks

For gandazgul:

1. Open the existing HTTPS media URL.
2. Confirm the page identifies as Seerr, not the old app name.
3. Log in with an existing account.
4. Compare users, permissions, and request history with the baseline.
5. Check Plex, Radarr, Sonarr, and Jellyfin connections that exist on that
   cluster.
6. If notifications are configured, send a test notification.
7. Agree on one harmless test request with the user, submit it, and confirm it
   reaches the correct configured service.
8. Delete the Seerr pod and confirm login, settings, and history persist after
   restart.

## Final Git State

After gandazgul passes functional checks:

1. Keep `apps/Overseerr.yaml` in Git because rafag still uses it.
2. Remove the `../../../apps/Overseerr.yaml` reference from gandazgul only.
3. Set `apps/Seerr.yaml` `spec.suspend: false`.
4. Commit and push the final state.
5. Reconcile each parent Flux Kustomization.
6. Resume only Flux resources that this migration suspended.

Verify final live state:

```bash
kubectl --context "${CTX}" get helmrelease overseerr -n "${NS}"
kubectl --context "${CTX}" get helmrelease seerr -n "${NS}"
flux --context "${CTX}" get kustomization "${CLUSTER}" -n kube-system
```

Expected result: Overseerr is absent. Seerr is ready. The parent Flux
Kustomization is ready.

## Rollback

Rollback discards requests made after the backup. Get user approval before you
restore.

1. Suspend the parent Flux Kustomization and Seerr HelmRelease.
2. Stop Seerr and wait for its pod to terminate.
3. Restore the full pre-migration `overseerr-config.tgz` to `configs/overseerr`
   with numeric ownership.
4. Restore the old HelmRelease values and old Git desired state.
5. Reconcile the old Overseerr release.
6. Verify login, settings, and request history from the restored backup.

Do not point old Overseerr at a database that Seerr already migrated.
