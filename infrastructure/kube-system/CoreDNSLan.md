# Home-network DNS

`CoreDNSLan.yaml` installs a separate `coredns-lan` Helm release in `kube-system`.
It does not change kubeadm's `coredns` deployment, `kube-dns` Service, or cluster
DNS configuration. Two replicas serve DNS over UDP and TCP on the control-plane
LAN address, port 53. The pods listen on unprivileged port 1053.

The parent kube-system Flux Kustomization substitutes these existing/new keys
from the `secrets` Secret:

- `CLUSTER_DOMAIN_NAME`: domain used by the flowers and bears overrides.
- `CONTROL_PLANE_IP`: local destination and DNS Service external address.
- `LAN_DNS_ALLOWED_CIDR`: home subnet allowed to query the resolver.

Raw values stay in the ignored cluster `secrets.env`; regenerate sealed secrets
with `infrastructure/setup/configure-cluster.sh` when changing them. Public
Cloudflare records remain unchanged.

Only the two game hostnames are overridden. Their A records use the LAN address;
AAAA and HTTPS/SVCB queries receive empty local answers, preventing clients from
using Cloudflare IPv6 addresses or service hints. Other names are forwarded to
1.1.1.1 or 1.0.0.1. Explicit upstreams prevent forwarding back into eero or the
cluster resolver. The recursion-available response flag is set for client
compatibility, including local answers.

The Service preserves source addresses with `externalTrafficPolicy: Local`.
CoreDNS ACLs allow the secret-defined LAN subnet and loopback, and refuse other
sources. Do not forward port 53 from the internet. Response caching is omitted
because CoreDNS executes its cache plugin before the ACL plugin; every request
must reach the ACL. Eero/client/upstream caches still operate normally.

## Eero setup

After verifying the resolver, use Settings > Advanced networking > DNS > Custom
DNS. Set IPv4 Primary to the control-plane LAN address. Leave Secondary blank
unless adding another local resolver with the same overrides; a public secondary
may be selected even while the primary is healthy and bypass the local answers.
Remove public IPv6 DNS entries as well. Save; eero restarts the network.
Eero Plus DNS filtering must be disabled to allow custom DNS. Browsers and devices
must use the network resolver rather than a separately configured public secure
DNS service. Cloudflare's public records and the URLs/certificates stay the same.

Test both game names with A, AAAA and HTTPS queries; test a public hostname over
UDP and TCP; verify outside-subnet requests return REFUSED. From the LAN, opening
flowers through the returned address should return HTTP 200 without credentials.
The existing Kubernetes resolver should still resolve kubernetes.default.

Both replicas currently run on the same physical server. If it is unavailable,
home DNS will be unavailable too. To roll back, restore eero's previous DNS
setting before removing this release.
