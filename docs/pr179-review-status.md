# PR 179 review follow-up

The migration, shared ingress change, bootstrap fixes, and rafag GPU configuration stay in PR 179. No second PR is required.

## Addressed in code

- Arr/Mealie image pins: the proposed overrides were removed; shared definitions retain main's image choices.
- Shared application divergence: rafag-only Audiobookshelf, Immich, SFTPGo and app-source copies/patch blocks were removed. Shared main definitions are used; storage settings remain cluster-specific values.
- Cloudflare DDNS: the additional CronJob and generator changes were removed; the implementation matches main.
- cert-manager: main's concurrent-challenge and DNS01 settings are retained unchanged.
- Traefik scope: the controller replacement is intentionally shared, with the nginx IngressClass retained through Traefik's ingress-nginx provider.
- Flux: the controller-version pin occurs only in infrastructure/setup/install-flux.sh; README documents it.
- Bootstrap paths: the control-plane script locates its config and node setup relative to itself.
- Fedora 44 package detection: installed packages are checked with RPM queries, not DNF available-package listings; a partial installation can retry even if its repository file already exists. DNF5-compatible exclusion handling is used.
- Bootstrap versions: the Kubernetes/CRI-O minor is selected once; package patch/build pins are removed. The installed kubeadm version is supplied consistently to validate, image pull and init. Flannel uses the upstream latest manifest.
- Host firewall: the install script retains main's active-firewalld stop/disable/mask policy, documented in README. Networking prerequisites no longer depend on firewalld being active. These are bootstrap-script changes, not changes to any running firewall.
- GPU: rafag selects its NVIDIA manifest again. The restored HelmRelease configuration matches the live release.

## Open before merge

- Flower Shop: Traefik 3.7.16 does not implement satisfy:any. Its nginx compatibility provider chains BasicAuth and IPAllowList (AND), while this app requires LAN OR valid credentials. A native LAN bypass with authenticated external ingress can preserve access; preserving the shared custom error pages needs additional routing/backend configuration. Do not merge the controller swap with the existing unsupported policy unchanged.
- BookOrbit: the misspelled proxy-buffers-size annotation is not recognized by either controller; the valid proxy-buffer-size/proxy-buffers-number annotations are supported. Real Kobo sync/large-header acceptance on gandazgul is not yet verified. No speculative BookOrbit changes were made.
- Audiobookshelf to BookOrbit: the duplicate custom overlay is removed, but switching rafag's existing app/data is a separate migration and has not been performed.
- Reviewer threads and the changes-requested review are not dismissed automatically.

## Verification

- Ten isolated bootstrap command tests cover package names, firewall states, unconditional networking, installed-version selection, failure handling and temporary cleanup. No installation script was run against a real node.
- Bash syntax, YAML parsing and whitespace/pre-commit checks passed. The generated kubeadm configuration also passed the installed v1.36.5 kubeadm configuration validator on cerebro; no cluster initialization was run.
- The selected inner app overlays for gandazgul and renepor render identically to main before the required Flower Shop compatibility follow-up; checking only the outer Flux objects is insufficient.
- Restored GPU objects passed Kubernetes server-side dry-run and configuration comparison against the running release.
- The running rafag cluster still tracks the previously verified final branch; updating this PR does not deploy these follow-up changes.

## Primary references

- [Traefik 3.7.16 nginx-provider annotations](https://github.com/traefik/traefik/blob/v3.7.16/docs/content/reference/routing-configuration/kubernetes/ingress-nginx.md)
- [Annotation parser](https://github.com/traefik/traefik/blob/v3.7.16/pkg/provider/kubernetes/ingress-nginx/annotations.go)
- [Authentication/allowlist translation](https://github.com/traefik/traefik/blob/v3.7.16/pkg/provider/kubernetes/ingress-nginx/translator.go)
- [ClientIP matching](https://github.com/traefik/traefik/blob/v3.7.16/docs/content/reference/routing-configuration/http/routing/rules-and-priority.md#clientip)

- [DNF5 changes from DNF4](https://github.com/rpm-software-management/dnf5/blob/main/doc/changes_from_dnf4.7.rst)
- [DNF5 repository-constrained installs](https://github.com/rpm-software-management/dnf5/blob/main/doc/_shared/options/from-repo.rst)
