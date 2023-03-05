# K8s Infrastructure Config

This is a collection of scripts to deploy kubernetes v1.20.x on Fedora. Tested on Fedora 33.

It's also a collection of helm charts that I developed or customized, as well as
[flux v2](https://toolkit.fluxcd.io/) objects to deploy all the supported applications.

We handled storage with PersistenceVolumes mapped to mount points on the host and pre-existing claims created that pods
can use as volumes. There's a k8s cron job included to make differential backups between the main mount point and the
backup one.

[Documentation](https://gandazgul.github.io/k8s-infrastructure/)

---

## My Home Setup

A small business server running the control plane node and worker. I plan to add at least one other node to learn to manage
a "cluster" and to try to automate node on-boarding. I've tested the manual node on-boarding with VMs, and it works
well. Look at this script [https://github.com/gandazgul/k8s-infrastructure/blob/main/install-k8s/2-configK8SNode.sh]()

# [Helm](https://helm.sh) Charts

I publish my charts as a helm repo. Most of these I created because I couldn't find them or were super specific. Some
are based on official charts I needed to modify. To use them add this url to helm as a repo and run update.

```bash
helm repo add gandazgul https://gandazgul.github.io/k8s-infrastructure/
```

Here is the [index.yaml](https://gandazgul.github.io/k8s-infrastructure/index.yaml)

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
