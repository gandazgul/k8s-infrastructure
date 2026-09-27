# BookOrbit to Kobo audiobook sync design

This design keeps the Kobo audiobook workflow local. It uses BookOrbit as the source of the desired set, then writes
Kobo-ready `.mp3z` files to a connected Kobo.

## Local configuration

Create this file in the repository root:

```bash
.env.bookorbit
```

The file is ignored by git. Put private values there. Values can be plain
`KEY=value` lines. Quotes are optional for values with spaces.

```bash
BOOKORBIT_URL=https://read.dumbhome.uk
BOOKORBIT_USERNAME=your-username
BOOKORBIT_PASSWORD=your-password
BOOKORBIT_KOBO_VOLUME=/Volumes/KOBOeReader
BOOKORBIT_COLLECTION=Kobo Audiobooks
BOOKORBIT_AUDIO_GAIN_DB=8
BOOKORBIT_AUDIO_BITRATE=96k
```

You can also use `BOOKORBIT_TOKEN` instead of username and password, but normal login tokens expire quickly. If you have
a BookOrbit magic-link token, set
`BOOKORBIT_MAGIC_LINK_TOKEN` instead.

Keep the env file private:

```bash
chmod 600 .env.bookorbit
```

## Run the sync

Connect the Kobo by USB and tap **Connect** on the Kobo. Then run:

```bash
scripts/sync-kobo-audiobooks.sh --dry-run
```

Check the plan. If it looks correct, run:

```bash
scripts/sync-kobo-audiobooks.sh
```

To move old synced audiobooks to `.trash` without another prompt, run:

```bash
scripts/sync-kobo-audiobooks.sh --yes-delete
```

To eject the Kobo at the end, run:

```bash
scripts/sync-kobo-audiobooks.sh --eject
```

## BookOrbit API facts

BookOrbit uses JWT bearer auth for normal `/api/v1/*` API calls. The login endpoint is:

```http
POST /api/v1/auth/login
```

It returns an `accessToken`. Use it as:

```http
Authorization: Bearer <accessToken>
```

The default access token lifetime is short: `JWT_EXPIRES_IN=15m`. For a script that you run by hand, the script should
either:

1. use a fresh `BOOKORBIT_TOKEN` value from a current browser/login session; or
2. exchange a magic-link token for a fresh access token at the start of each run.

Collection endpoints found in BookOrbit source:

```http
GET /api/v1/collections
GET /api/v1/collections/:id/books?page=0&size=100
```

Book download endpoints found in BookOrbit source:

```http
GET /api/v1/books/files/:fileId/download
GET /api/v1/books/export/download?bookIds=1,2,3&scope=audio
```

For the sync script, prefer single-file downloads. Use each book card's `files`
array to select audio formats: `m4b`, `m4a`, `mp3`, `opus`, `ogg`, or `flac`. Then download with
`/api/v1/books/files/:fileId/download`.

## Token options

### Option A: short-lived login token

Use this for early testing. Log in through the API and copy the returned
`accessToken` into `.env.bookorbit`.

```bash
curl -sS https://read.dumbhome.uk/api/v1/auth/login \
    -H 'content-type: application/json' \
    -d '{"username":"YOUR_USERNAME","password":"YOUR_PASSWORD"}'
```

This is easy but expires quickly.

### Option B: magic-link token

Use this for automation if BookOrbit has a shared automation user that can see the collection. The source shows these
endpoints:

```http
POST /api/v1/auth/magic-links
POST /api/v1/auth/magic-links/login
```

Important limits from source:

- Only superusers can create magic links.
- Magic links can only target shared accounts.
- A magic-link login returns a normal short-lived `accessToken`.

The sync script can store the magic-link token in `.env.bookorbit`, call
`/api/v1/auth/magic-links/login` at startup, and use the returned access token for that run.

## Sync algorithm

1. Load `.env.bookorbit`.
2. Verify the Kobo is mounted at `BOOKORBIT_KOBO_VOLUME`.
3. Use the Kobo root as the default audiobook folder because Kobo Nickel only discovers sideloaded `.mp3z` audiobooks
   there:

   ```text
   $BOOKORBIT_KOBO_VOLUME/*.mp3z
   ```

4. Store sync state in the Kobo root:

   ```text
   $BOOKORBIT_KOBO_VOLUME/.bookorbit-sync.json
   ```

5. Fetch `/api/v1/collections` and find `BOOKORBIT_COLLECTION` by name.
6. Fetch all pages from `/api/v1/collections/:id/books?page=N&size=100`.
7. Keep only books that have an audio file.
8. Compare the desired set to the sync manifest and root `.mp3z` files. The manifest controls ownership, so unrelated
   root audiobooks are left alone.
9. For missing or changed books:
    - download the source audio file;
    - encode with `scripts/create-kobo-audiobook.sh`;
    - copy the `.mp3z` to the Kobo root;
    - update `.bookorbit-sync.json`.
10. For managed files that are no longer in the collection:
- show the list;
- ask before delete;
- move confirmed removals to `$BOOKORBIT_KOBO_VOLUME/.bookorbit-trash/`
  first.
11. Ask to eject the Kobo when done.

## Safe defaults

Use these defaults for the Clara Colour:

```bash
BOOKORBIT_AUDIO_GAIN_DB=8
BOOKORBIT_AUDIO_BITRATE=96k
```

If an audiobook sounds distorted, rebuild it with:

```bash
BOOKORBIT_AUDIO_GAIN_DB=6
```
