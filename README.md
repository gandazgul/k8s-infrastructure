# K8s Infrastructure Config

This is a collection of scripts to deploy kubernetes on Fedora. Tested on Fedora 28. 

It's also a collection of helm charts that I developed or customized 
(See the [Helm Repo](https://gandazgul.github.io/k8s-infrastructure/helmrepo/)), as well as 
[helmfiles](https://github.com/roboll/helmfile/) to deploy all of the supported applications.

The storage is handled with PersistenceVolumes mapped to mount points on the host and pre-existing claims 
created that pods can use as volumes. There's a k8s cron job included to make differential backups between the main mount point and the backup one.

[Documentation](https://gandazgul.github.io/k8s-infrastructure/)

---

## My Home Setup

A small business server running as a master node and worker. I plan to add at least one other 
node to learn to manage a "cluster" and to try and automate node onboarding. I've tested the manual node onboarding with VMs and it works well. Look at this script [https://github.com/gandazgul/k8s-infrastructure/blob/master/k8s-config/2-configK8SNode.sh]()

## Helm repo

I publish my charts as a helm repo here: [Helm Repo](https://gandazgul.github.io/k8s-infrastructure/helmrepo/).

## License

Unless specifically noted, all parts of this project are licensed under the [MIT license](https://github.com/gandazgul/k8s-infrastructure/blob/master/LICENSE.md).

## Contributing

Contributions are more than welcome. Please open a PR with a good title and description of the change you are making. 
Links to docs or examples are great.
