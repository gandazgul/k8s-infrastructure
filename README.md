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

[Get started now](#getting-started){: .btn .btn-primary } 
[View it on GitHub](https://github.com/gandazgul/k8s-infrastructure){: .btn }

---

## Helm repo

I publish my charts as a helm repo here: [Helm Repo](https://gandazgul.github.io/k8s-infrastructure/helmrepo/).

---

## Getting started

This will install a fully functioning kubernetes master where you can run all of your services.

1. Install Fedora 28
    1. During install set the hostname, this will be the name of this node, you can do this after install
    2. Create a user, kubectl doesn't like running as root
    3. Remove the swap, kubernetes is not compatible with swap at the moment and will complain about it. 
2. Check out this repo on another machine
3. Customize this file: `~/k8s-config/1-fedoraPostInstall.sh` - it will install some packages and setup the mount 
points as I like them
4. Copy the scripts over `scp -r ./k8s-config fedora-ip:~/`
5. `ssh fedora-ip`
6. `~/k8s-config/2-configK8SMaster` - This will install K8s and configure the master to run pods, it will also install 
Flannel network plugin
7. If something fails, you can reset with `sudo kubeadm reset`, delete kubeadminit.lock and try again, the other 
commands are repeatable

Verify Kubelet that is running with `sudo systemctl status kubelet`

Verify that Flannel is finished setting up with: `kubectl get ds --namespace=kube-system`, look for the flannel for 
your architecture and it should have `1` in all the columns.

Once flannel is working:

### Install Storage, Helm, etc

This will install a hostpath auto provisioner for quick testing of new pod configs, it will also install the helm 
client with the tiller and diff plugins.

1. Run `3-installStorageAndHelm.sh`

### Verify kubectl works:

NOTE: Kubectl does not need sudo, it will fail with sudo

* `kubectl get nodes` ← gets all nodes
* `kubectl get all --all-namespaces` ← shows everything that’s running in kubernetes

### Setting up your local machine for using k8s

On your local machine (NOTE: Only works on your local network):
1. Install kubectl (`brew install kubernetes-cli` or find the package for your linux distro that install kubectl, 
kubernetes-client in Fedora)
2. `scp fedora-ip:~/.kube/config ~/.kube/config` <-- configuration file for connecting to the cluster
3. Test with `kubectl get nodes` you should see your node listed, if not check the permissions on the config file 
(should be owned by your user/group).
4. Install helm with ./k8s-config/installHelm.sh. This installs helm without tiller, instead it uses the tiller plugin 
to run tiller locally :)
    1. Test helm with:
    2. `helm tiller start` <-- starts bash with tiller enabled
    3. `helm list` <-- You should see no output, if error then something went wrong
    4. `exit`
5. Install helmfile: `brew install helmfile` (for linux see [helmfile's releases](https://github.com/roboll/helmfile/releases))
6. Set default namespace for kubectl `kubectl config set-context $(kubectl config current-context) --namespace=services`
    * Check that the namespace was set: `kubectl config view | grep namespace:`

### To Install the services

1. On the root of infrastructure `cp ./secrets.example.sh ./secrets.sh`
2. Fill in secrets with your passwords and other settings
3. Run `helm tiller start`
4. Run `source ./secrets.sh` to set up the passwords/settings
5. Now you have 2 options, 
    * You can run `helmfile -f helmfile.d sync` to install everything I have setup.
    
    OR
    
    1. You can create a new folder like I've done with my other setups (see gandazgul.d and secondary-master.d)
    2. Then symlink the files that you want to include or copy them and customize them
    3. Then run `helmfile -f your-dir.d sync` 
5. Afterwards when you make changes run `helmfile apply`
6. You can also run individual files with: `helmfile apply -f helmfile.d/00-storage.yaml`
8. Run `helm list` to see what is installed
9. Run `helm delete --purge [NAME]` to remove one particular service if you need to retry/stop it 

## Services Included:

* Volumes for service configs and data
* K8s Dashboard (Port 8443, https required)
* Ingress with TLS enabled
* cert-manager with cluster cert issuers for the CA setup by kubeadmn and letsencrypt (staging and prod)
* FileBrowser (default credentials admin:admin, port 8080)
* Plex (Port 32400, needs extra configuration, see the [README](https://github.com/munnerz/kube-plex))
* Seedbox  - transmission - 9091, flexget, OpenVPN - [README](/charts/seedbox/README.md)
* SSHD - for tunneling, etc - Port 22222 - [README](/docker/sshd/README.md)
* Gogs - Port 3000
* Resilio Sync (Port 8888)
* Samba - Opens the default ports on the node directly - [README](/charts/samba/README.md)
* CronJob to take a differential backup of main-volume into backup-volume - [Docs](https://www.nongnu.org/rdiff-backup/docs.html)

## Access

Each service will be accessed a little different depending on what it is. The dashboard sets up an ingress to 
https://dashboard.[node-name]/ other just open their ports on the machine they are on.

## How to reboot a node

1. Run this to stop all pods, delete-local-data doesnt actually delete anything, if any pods are using emptyDir as a 
volume it gets deleted, is just a warning.

    `kubectl drain [node-name] --ignore-daemonsets --delete-local-data`

2. Do any maintenance needed and reboot
3. Run this to allow pods to be started on this node again.

    `kubectl uncordon [node-name]`
    
## How to upgrade the kubernetes master and nodes

It's fairly easy and I've done it before successfully.

Follow these instructions https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade-1-13/

### License

Everything in this repo is distributed by an [MIT license](LICENSE.md).

### Contributing

Contributions are more than welcome. Please open a PR with a good title and description of the change you are making. 
Links to docs or examples are great.
