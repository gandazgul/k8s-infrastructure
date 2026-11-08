# K8s Infrastructure Config

This is a collection of scripts to deploy Kubernetes on Fedora 44.

Bootstrap version sources:

- `KUBERNETES_MINOR` in [install-k8s/configNode.sh](install-k8s/configNode.sh) selects the Kubernetes and CRI-O repositories; package patch versions are not pinned.
- The Flux controller version is pinned only in [infrastructure/setup/install-flux.sh](infrastructure/setup/install-flux.sh). Flannel uses its latest release manifest.

The homelab bootstrap stops, disables, and masks active firewalld, preserving its existing policy rather than configuring host-firewall rules. Kernel modules and forwarding settings are applied regardless of firewalld state. This setup relies on the homelab's router/Cloudflare boundary and permits NodePorts 1025–32767.

Run the numbered bootstrap scripts from inside `install-k8s/`; their paths are relative to that directory.

It's also a collection of [flux v2](https://toolkit.fluxcd.io/) objects to deploy all the supported applications.

We handled storage with PersistenceVolumes mapped to mount points on the host and pre-existing claims created that pods
can use as volumes. There's a k8s cron job included to make differential backups between the main mount point and the
backup one.

[Documentation](https://gandazgul.github.io/k8s-infrastructure/)

---

## My Home Setup

A small business server running the control plane node and worker. I plan to add at least one other node to learn to manage
a "cluster" and to try to automate node on-boarding. I've tested the manual node on-boarding with VMs, and it works
well. Look at this script [https://github.com/gandazgul/k8s-infrastructure/blob/main/install-k8s/2-configK8SNode.sh]()



## What is YASR? I see it mentioned everywhere

YASR is an in-joke, it stands for Yet Another Storage
Repository (https://encyclopedia.thefreedictionary.com/Yet+Another) - SR is the name of storage volumes in Xenserver
which we migrated from. YASR is the volume we use, to store all application settings. MAIN and BACKUP have all the app
data and personal files, backed up to back up with rdiff-backup.

## License

Unless specifically noted, all parts of this project are licensed under
the [MIT license](https://github.com/gandazgul/k8s-infrastructure/blob/main/LICENSE.md).

## Contributing

Contributions are more than welcome. Please open a PR with a good title and description of the change you are making.
Links to docs or examples are great.
