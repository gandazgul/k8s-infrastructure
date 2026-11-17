# Plex on the Mac

## Scope

Plex moves from the `gandazgul` cluster to the Mac at `10.1.1.6`.
The `rafag` and `renepor` cluster definitions and the shared
[`apps/Plex.yaml`](../apps/Plex.yaml) are unchanged.

Only the Plex resource in
[`clusters/gandazgul/apps/kustomization.yaml`](../clusters/gandazgul/apps/kustomization.yaml)
is disabled. Flux removes that Helm release. The existing `yasr-volume` and
`main-volume` claims are retained.

## Storage

| Data | Location |
| --- | --- |
| Original Plex data, retained for rollback | `10.1.1.2:/media/yasr/configs/plex/Library/Application Support/Plex Media Server` |
| Mac Plex data | `~/Library/Application Support/Plex Media Server` |
| Mac Plex preferences | `~/Library/Preferences/com.plexapp.plexmediaserver.plist` |
| Protected migration settings and database baseline | `~/Library/Application Support/Plex Migration/2026-11-16` |
| Movies, TV, music, and YouTube media | `/Volumes/media`, from `smb://10.1.1.2/media` |
| Personal pictures and videos | `/Volumes/pictures`, from `smb://10.1.1.2/pictures` |
| Local transcode files | `~/Library/Caches/PlexMediaServer/Transcode` |

Both SMB shares are read-only. Their launch agents are
`~/Library/LaunchAgents/local.plex-media-mount.plist` and
`~/Library/LaunchAgents/local.plex-pictures-mount.plist`. They use the saved
Keychain login and check for a missing mount every 60 seconds.

The server launch agent is `~/Library/LaunchAgents/local.plex-server.plist`.
It starts Plex at user login and runs `caffeinate` while Plex runs. This prevents
idle system sleep without changing display sleep. The user must stay logged in.
Allow Plex access to **Network Volumes** and **Local Network** in macOS privacy
settings.

The source `Cache` directory is excluded from the transfer. Plex can rebuild
it. The server identity and account settings are mapped from Linux's
`Preferences.xml` to macOS preferences. Keep the protected settings out of Git:
they contain the Plex account token.

Keep automatic trash emptying disabled. An unavailable network share must not
remove library entries. Rene's photo library is retained in the database, but
its media share is not mounted on this Mac. The `My Home Movies` library is
also retained: its old `/data/Pictures` source folder is absent from the media
share. Do not empty either library's trash to remove these entries.

External subtitles can retain Linux `file:///data/` URLs after a library scan.
The migration corrected 54 such URLs in `media_streams.url` while Plex was
stopped. The database backup before that change is
`before-subtitle-path-fix.db` in the protected migration directory. The change
did not modify playback-history tables. The original source database is
unchanged.

## Library verification

The Movies, TV Shows, YouTube Shows, Music, My Photos, and My Videos scans
completed against the new `/Volumes` paths. Their old Linux locations remain
in the library settings to retain unavailable entries during verification.
Automatic filesystem and scheduled scans remain disabled. Use a manual scan
on an available library when you add media; do not scan the two unavailable
libraries.

All 11,324 original watch-state records retain their accounts and ratings,
with no decrease in view counts. All 10,414 original history records retain their accounts,
playback timestamps, and episode details. Plex refreshed some metadata GUIDs,
artwork references, and show-title accents during scanning. The comparison
report is `final-history-verification.json` in the protected migration
directory. A final database integrity check returned `ok`.

## Playback checks

HEVC/MKV playback passed with an external English SRT subtitle. A forced
lower-quality conversion also passed. Plex reported Apple VideoToolbox for
both hardware decoding and hardware encoding. Evidence is in the protected
migration directory as `hevc-forced-transcode-subtitles.png`.

Plex recognizes the original server identity, signed-in account, and active
Plex Pass subscription.

## Network access

Open `http://10.1.1.6:32400/web` on the LAN. If the router forwards TCP 32400
to `10.1.1.2`, change that forwarding rule to `10.1.1.6` for remote access.
Keep the Mac's address stable. Do not expose SMB port 445 to the internet.
Clients and integrations with a fixed old Plex address must use the Mac's
address. Plex account discovery uses the retained server identity.

## Rollback

1. Stop Plex Media Server on the Mac. Do not run two servers with the same
   identity at the same time.
2. Re-enable `../../../apps/Plex.yaml` only in the `gandazgul` app list.
3. Commit and push the change through the normal GitOps process.
4. Verify the original Plex release is running before using it.
5. Restore any router forwarding or fixed client addresses to `10.1.1.2`.

The source data represents the cutover state. Playback history and other changes
made on the Mac after cutover are not automatically copied back.

Plex's [migration guide](https://support.plex.tv/articles/201370363-move-an-install-to-another-system/)
states that cross-operating-system moves are not officially supported. Verify
library access for shared users after the move.
