# Flower Shop

Source: https://github.com/gandazgul/flower-shop (MIT).
Play: https://flowers.dumbhome.uk.

The generic overlay runs one Deno server with Recreate updates. JSON saves live
in `configs/flower-shop` on `yasr-volume`; back up this directory. The init
container prepares only this app directory; the server runs as UID/GID 1000
with a read-only root filesystem and no service-account token.

Publish an AMD64 image with Podman to `harbor.dumbhome.uk/library/flower-shop`,
then update the tag and digest in `patches/deployment.yaml`.

## Invitations

`FLOWER_SHOP_AUTH` in `clusters/gandazgul/secrets.env` is the base64 encoding of
an htpasswd file containing the `flowers` user. Run the standard
`infrastructure/setup/configure-cluster.sh gandazgul` workflow after changing it.
The sealed main secret is reflected into default; Flux substitutes the hash
into `flower-shop-auth`. Never commit the plaintext invite or an unsealed hash.

NGINX combines Basic auth, `satisfy: any`, and the `10.1.1.0/24` allowlist.
The controller Service uses `externalTrafficPolicy: Local` to preserve client
addresses. Do not trust arbitrary forwarded headers or enable a broad real-IP
proxy range. External Cloudflare requests retain a non-LAN peer address and
must authenticate. Internal DNS must resolve flowers.dumbhome.uk to 10.1.1.2
for the password-free LAN route. External DNS uses a proxied CNAME to
`gandazgul.clusters.dumbhome.uk`, matching the other public games.

The app overrides custom error handling to keep HTTP 401 and its
WWW-Authenticate header intact. Verify LAN requests return 200, non-LAN
requests return 401, and valid credentials return 200. Supplying a fake
X-Forwarded-For LAN address must not bypass the challenge.
