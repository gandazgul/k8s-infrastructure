# Samba media share

The `gandazgul` cluster enables [Samba](../apps/Samba.yaml) through the
[generic overlay](../apps/generic/overlays/samba/kustomization.yaml).

## Connect from macOS

In Finder, select **Go > Connect to Server** and enter:

```text
smb://10.1.1.2/media
```

Use the `gandazgul` account and its existing Samba password. The Samba password
can differ from the SSH password. Save the password in Keychain if required.

The `media` share exposes `/media/main/public` from `main-volume`. The
`pictures` share exposes `/media/main/gandazgul/Pictures` at
`smb://10.1.1.2/pictures`. Both shares and their container mounts are read-only.
Guest access is disabled.
Only TCP port 445 is exposed, through a Service on `${CONTROL_PLANE_IP}`.
There is no HTTP ingress or network discovery service. Keep port 445 on the
trusted LAN; do not forward it from the internet.

## Configuration and state

- `/media/yasr/configs/samba/smbpasswd` supplies the existing `gandazgul`
  password hash. The container reads this file at startup. It is not stored in
  Git or printed in startup logs.
- `/media/yasr/configs/samba/state` stores Samba state through `yasr-volume`.
  The startup command creates the private state directory on first use.
- Share settings are defined in the deployment patch. The container generates
  its runtime `smb.conf` from these settings.
- The old `/media/yasr/configs/samba/smb.conf` is retained but is not used. Its
  anonymous writable shares are not enabled.

This deployment requires the existing password file on the host. Other clusters
must provision their credentials before enabling this app. To change the
password, update the host password file through a secure channel and restart
the deployment. Do not commit password hashes to Git.

## Plex migration

See [Plex on the Mac](plex-migration.md) for the storage layout and rollback
steps. Keep the Plex database and transcode files on the Mac's local disk.
Keep automatic trash emptying disabled so a disconnected share does not remove
library entries.
