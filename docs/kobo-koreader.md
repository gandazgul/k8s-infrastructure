# Restore KOReader on a Kobo

Use this when a Kobo update removes KOReader, or when the BookOrbit plugin is missing from KOReader.

## What the restore does

`scripts/restore-kobo-koreader.sh` does these changes on the mounted Kobo:

- installs the NickelMenu launcher update into `.kobo/KoboRoot.tgz`;
- installs the latest KOReader Kobo build into `.adds/koreader`;
- adds a NickelMenu entry named `KOReader`;
- sets `ExcludeSyncFolders` so Nickel does not index hidden app folders;
- installs the BookOrbit KOReader plugin into
  `.adds/koreader/plugins/bookorbit.koplugin`.

The script does not store BookOrbit credentials in this repository.

## Restore with a preconfigured BookOrbit plugin

Use this for a one-command restore. The preconfigured plugin zip is the KOReader plugin zip that BookOrbit creates from
**Settings > KOReader**. It contains:

- `bookorbit.koplugin`;
- the BookOrbit server URL;
- the KOReader sync credentials that you created in BookOrbit.

Keep this zip private because it has sync credentials.

1. In BookOrbit, open **Settings > KOReader**.
2. Create sync credentials.
3. Download the preconfigured plugin zip.
4. Put this in `.env.bookorbit`:

   ```bash
   BOOKORBIT_KOBO_VOLUME=/Volumes/KOBOeReader
   BOOKORBIT_URL=https://read.dumbhome.uk
   BOOKORBIT_PLUGIN_ZIP=$HOME/Downloads/bookorbit-koreader-plugin.zip
   ```

5. Connect the Kobo by USB.
6. Tap **Connect** on the Kobo.
7. Run:

   ```bash
   scripts/restore-kobo-koreader.sh
   ```

8. Eject the Kobo.
9. Unplug it and wait for the NickelMenu update to finish.
10. Start KOReader. The plugin applies its embedded server and credentials on startup.

## Restore with the standard BookOrbit plugin

Use this if you do not have the preconfigured plugin zip. You must enter the server and sync credentials on the Kobo.

1. Connect the Kobo by USB.
2. Tap **Connect** on the Kobo.
3. Find the mount path, or set `BOOKORBIT_KOBO_VOLUME` in `.env.bookorbit`.
4. Run:

   ```bash
   scripts/restore-kobo-koreader.sh /Volumes/KOBOeReader
   ```

5. Eject the Kobo.
6. Unplug it and wait for the NickelMenu update to finish.
7. Start KOReader from the main menu.
8. In KOReader, open **Tools > BookOrbit** and use the server from
   `BOOKORBIT_URL` in `.env.bookorbit`, or use:

   ```text
   https://read.dumbhome.uk
   ```

9. Sign in with KOReader sync credentials from BookOrbit.

## Notes

- Leave the stock KOReader progress sync plugin unconfigured. The BookOrbit plugin does the sync.
- If the Kobo mounts at a different path, replace `/Volumes/KOBOeReader` with that path.
- If KOReader starts but BookOrbit is not visible, restart KOReader one more time.

## Put a DRM-free audiobook on the Kobo

The Clara Colour can play audiobooks through Bluetooth. Kobo's normal audiobook sync is for Kobo-purchased audiobooks.
For DRM-free local files, create a
`.mp3z` file and copy it to the Kobo.

Use `scripts/create-kobo-audiobook.sh` for this.

### Create a `.mp3z` file

Put the audiobook files in one folder, or pass one audiobook file. The script accepts `mp3`, `m4a`, `m4b`, `aac`,
`flac`, `ogg`, `opus`, and `wav` files. If files are not already MP3, install `ffmpeg` first.

```bash
scripts/create-kobo-audiobook.sh \
    "/path/to/Audiobook Folder" \
    "$HOME/Desktop/Audiobook Name.mp3z"

scripts/create-kobo-audiobook.sh \
    "$HOME/Downloads/In Stormy Weather - Chelsea Curto.m4b" \
    "$HOME/Desktop/In Stormy Weather - Chelsea Curto.mp3z"
```

For one `.m4b` file, the script splits by embedded chapter markers when they exist. For a folder, the script sorts files
by path. Name chapter files with leading numbers, for example `001.mp3`, `002.mp3`, and `003.mp3`.

### Create and copy to the Kobo

Connect the Kobo by USB, tap **Connect**, then run:

```bash
KOBO_MOUNT_PATH=/Volumes/KOBOeReader \
    scripts/create-kobo-audiobook.sh \
    "$HOME/Downloads/In Stormy Weather - Chelsea Curto.m4b" \
    "$HOME/Desktop/In Stormy Weather - Chelsea Curto.mp3z"
```

Then eject the Kobo, unplug it, and open **My Books > Audiobooks**.

### If playback is too quiet

The Kobo Bluetooth output can be quiet with some headphones. You can build a louder file with a safe limiter:

```bash
AUDIO_GAIN_DB=8 \
    KOBO_MOUNT_PATH=/Volumes/KOBOeReader \
    scripts/create-kobo-audiobook.sh \
    "$HOME/Downloads/In Stormy Weather - Chelsea Curto.m4b" \
    "$HOME/Desktop/In Stormy Weather - Chelsea Curto.mp3z"
```

Try `AUDIO_GAIN_DB=6` if `8` sounds distorted.

### Sync a BookOrbit collection

Use `scripts/sync-kobo-audiobooks.sh` to sync one BookOrbit manual collection to root `.mp3z` files. The script uses
`.bookorbit-sync.json` to track which files it manages. See `docs/bookorbit-kobo-audiobook-sync.md`.

Start with a dry run:

```bash
scripts/sync-kobo-audiobooks.sh --dry-run
```

Then run the sync:

```bash
scripts/sync-kobo-audiobooks.sh
```

### Limits

- Use only DRM-free audiobook files that you are allowed to copy.
- Kobo can show weak metadata for sideloaded `.mp3z` files. The title can come from the filename, with unknown author
  and no cover.
- One MP3 file becomes one Kobo audiobook chapter.
