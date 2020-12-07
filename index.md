# K8s Infrastructure Config

This is a collection of scripts to deploy kubernetes on Fedora. Tested on Fedora 31. 

It's also a collection of helm charts that I developed or customized (See [Repo](#helm-repo)), as well as [helmfiles](https://github.com/roboll/helmfile/) 
to deploy all the supported applications.

The storage is handled with PersistenceVolumes mapped to mount points on the host and pre-existing claims 
created that pods can use as volumes. There's a k8s cron job included to make differential backups between the main mount point and the backup one.

[Get started now](#getting-started){: .btn .btn-primary } 
[View it on GitHub](https://github.com/gandazgul/k8s-infrastructure){: .btn }

---

## My Home Setup

A small business server running as a master node and worker. I plan to add at least one other 
node to learn to manage a "cluster" and to try to automate node on-boarding. I've tested the 
manual node on-boarding with VMs, and it works well. 
Look at this script [https://github.com/gandazgul/k8s-infrastructure/blob/master/k8s-config/2-configK8SNode.sh]()

# [Helm](https://helm.sh) Charts

I publish my charts as a helm repo here: [Helm Repo](https://gandazgul.github.io/k8s-infrastructure/).

Most of these I created because I couldn't find them or were super specific. Some are based on official charts I need to modify.

To use them add this url to helm as a repo and run update. 

```bash
helm repo add gandazgul https://gandazgul.github.io/k8s-infrastructure/
``` 

Here is the [index.yaml](./index.yaml)

---

## Getting started

By following these steps you will install a fully functioning kubernetes master where you can run all of your applications.

1. Install Fedora 31
    1. During install set the hostname, this will be the name of this node, you can do this after install
    2. Create a user, kubectl doesn't like running as root
    3. Remove the swap, kubernetes is not compatible with swap at the moment and will complain about it. 
2. Check out this repo on another machine
3. Customize this file: `~/k8s-config/1-fedoraPostInstall.sh` - it will install some packages and setup the mount 
points as I like them
4. Copy the scripts over `scp -r ./k8s-config fedora-ip:~/`
5. `ssh fedora-ip`
6. Run your modified `~/k8s-config/1-fedoraPostInstall.sh`
7. Then run `~/k8s-config/2-configK8SMaster` - This will install K8s and configure the master to run pods, it will also install 
Flannel network plugin
    * Wait for the flannel for your architecture to show `1` in all columns then press ctrl+c
8. If something fails, you can reset with `sudo kubeadm reset`, delete kubeadminit.lock and try again, all the 
scripts are safe to re-run.
9. Verify Kubelet that is running with `sudo systemctl status kubelet`
Once Flannel is working, and you verified kubelet:
10. Install Storage, Helm, etc. run `3-installStorageAndHelm.sh`
This will install a hostpath auto provisioner for quick testing of new pod configs, it will also install the helm 
client with the plugins.
9. Verify kubectl works: (NOTE: Kubectl does not need sudo, it will fail with sudo)
    * `kubectl get nodes` ← gets all nodes, you should see your node listed and `Ready`
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
    2. `helm tiller start` <-- Installs Tiller locally the first time then starts it
    3. `helm list` <-- You should see no output, if error then something went wrong
5. Install helmfile. For the most up to date version download from the [helmfile's releases](https://github.com/roboll/helmfile/releases))
6. Set default namespace for kubectl `kubectl config set-context $(kubectl config current-context) --namespace=default`
    * Check that the namespace was set: `kubectl config view | grep namespace:`

### To install the applications

1. On the root of project run `cp ./secrets.example.sh ./secrets.sh`
2. Fill in secrets with your passwords and other settings
3. Run `helm tiller start`
4. Run `source ./secrets.sh` to set up the passwords/settings
5. Now you have 2 options, 
    * You can run `helmfile -f helmfile.d sync` to install everything I have setup.
    
    OR
    
    1. You can create a new folder like I've done with my other setups (see gandazgul.d and secondary-master.d)
    2. Then symlink the files that you want to include or copy them and customize them
    3. Then run `helmfile -f your-dir.d sync` 
5. Afterwards when you make changes run `helmfile -f helmfile.d apply`
6. You can also run individual files with: `helmfile -f helmfile.d/00-storage.yaml apply`
8. Run `helm list` to see what is installed
9. Run `helm delete --purge [NAME]` to remove one particular service if you need to retry/stop it 

### To delete all applications

`helm ls --all --short | xargs -L1 helm delete --purge`

## Services Included:

All URLs are the service's url as a subdomain of the INGRESS_INTERNAL_NAME or INGRESS_EXTERNAL_NAME secrets 
(See `secrets.example.sh`). e.g. dashboard.example.com. All of these are defaults they can be customized per release 
by copying the original file and changing the values to suit your needs. 

| Service Name                              | URL          | Port               | Docs                                                   |
|:------------------------------------------|:-------------|:-------------------|--------------------------------------------------------|
| Cert Manager                              | -            | -                  | [README](https://github.com/jetstack/cert-manager)     |  
| Cronjobs (rdiff-backup)                   | -            | -                  | [Docs](https://www.nongnu.org/rdiff-backup/docs.html)  |
| NGINX Ingress                             | -            | 80, 443            | [README](https://kubernetes.github.io/ingress-nginx/)  |
| K8s Dashboard                             | dashboard    | -                  | [README](https://github.com/kubernetes/dashboard)      |
| FileBrowser                               | files        | -                  | [README](https://github.com/filebrowser/filebrowser/)  |
| Plex                                      | plex         | -                  | [README](https://github.com/munnerz/kube-plex)         |
| Torrents (Transmission, OpenVPN, Flexget) | transmission | -                  | [README](/charts/seedbox/README.md)                    |
| SSHD                                      | -            | 22222              | [README](/docker/sshd/README.md)                       |
| Gogs                                      | gogs         | -                  | [README](https://hub.helm.sh/charts/incubator/gogs)    |
| Resilio Sync                              | resilio      | -                  | -                                                      |
| Samba                                     | -            | 139, 445, 137, 138 | [README](/charts/samba/README.md)                      |
| Prometheus                                | prometheus   | -                  | [README](https://hub.helm.sh/charts/stable/prometheus) |
| AlertManager (Prometheus)                 | alerts       | -                  | Same                                                   |
| Grafana                                   | grafana      | -                  | [README](https://hub.helm.sh/charts/stable/grafana)    | 

## Node maintenance

### How to reboot a node

1. Run this to stop all pods, delete-local-data doesnt actually delete anything, if any pods are using emptyDir as a 
volume it gets deleted, is just a warning.

    `kubectl drain [node-name] --ignore-daemonsets --delete-local-data`

2. Do any maintenance needed and reboot
3. Run this to allow pods to be started on this node again.

    `kubectl uncordon [node-name]`
    
### How to upgrade the kubernetes master and nodes

It's fairly easy and I've done it before successfully.

Follow these [instructions](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade-1-13/)

## License

Unless specifically noted, all parts of this project are licensed under the [MIT license](https://github.com/gandazgul/k8s-infrastructure/blob/master/LICENSE.md).

## Contributing

Contributions are more than welcome. Please open a PR with a good title and description of the change you are making. 
Links to docs or examples are great.
