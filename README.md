# K8s Infrastructure Config

This is a collection of scripts to deploy kubernetes on Fedora. Tested on Fedora 28. 

It's also a collection of helm charts that I developed or customized, as well as [helmfiles](https://github.com/roboll/helmfile/) 
to deploy all of the supported applications.

My setup right now is a pretty good small business server running as a master node. I plan to add at least one other 
node to learn to manager a "cluster" and to try and automate node onboarding.

Each service has its own container with the exception of the seedbox which is flexget and transmission running together 
with OpenVPN.

The storage right now is local PersistenceVolumes mapped to the mount points on the host and pre-existing claims 
created that pods can use as volumes. I have a k8s cron job to make a differential backup to another HDD.

[Documentation](https://gandazgul.github.io/k8s-infrastructure/)

---

## Helm repo

I publish my charts as a helm repo here: [Helm Repo](https://gandazgul.github.io/k8s-infrastructure/helmrepo/).

## License

Everything in this repo is distributed by an [MIT license](LICENSE.md).

## Contributing

Contributions are more than welcome. Please open a PR with a good title and description of the change you are making. 
Links to docs or examples are great.
