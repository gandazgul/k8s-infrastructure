# K8s Infrastructure Config

install-k8s/ - This is a collection of scripts to deploy kubernetes v1.24.x on Fedora. Tested on Fedora 33.
charts/ - Is a collection of helm charts that I developed or customized.

The rest is a GitOps setup using [Flex CD](https://fluxcd.io/flux/get-started/) to deploy all infra and the supported applications.

We handled storage with PersistenceVolumes mapped to mount points on the host and pre-existing claims
created that pods can use as volumes. There's a k8s cron job included to make differential backups
between the main mount point and the backup one.

[Get started now](#getting-started){: .btn .btn-primary }
[View it on GitHub](https://github.com/gandazgul/k8s-infrastructure){: .btn }

---

## My Home Setup

A small business server running as control plane node and worker. I plan to add at least one other
node to learn to manage a "cluster" and to try to automate node on-boarding. I've tested the
manual node on-boarding with VMs, and it works well.
Look at this script [https://github.com/gandazgul/k8s-infrastructure/blob/main/install-k8s/2-configK8SNode.sh]()

# [Helm](https://helm.sh) Charts

Most of these I created because I couldn't find them or were super specific. Some are based on official charts I needed to modify.

I publish my charts as a helm repo. To use them add this url to helm and run update.

```bash
helm repo add gandazgul https://gandazgul.github.io/k8s-infrastructure/
```

Here is the [index.yaml](https://gandazgul.github.io/k8s-infrastructure/index.yaml)

---

## Getting started

By following these steps you will install a fully functioning kubernetes control plane/worker where you can run all of your applications.

1. Install Fedora 33
    1. During install set the hostname, this will be the name of this node, you can do this after install
    2. Create a user, kubectl doesn't like running as root for good reason
    3. Remove the swap, kubernetes is not compatible with swap at the moment and will complain about it.
2. Check out this repo on another machine
3. Customize this file: `~/install-k8s/1-fedoraPostInstall.sh` - it will install some packages and setup the mount
points as I like them
4. Copy the scripts over `scp -r ./install-k8s fedora-ip:~/`
5. `ssh fedora-ip`
6. Run your modified `~/install-k8s/1-fedoraPostInstall.sh`
7. Then run `~/install-k8s/2-configK8SControlPlane.sh` - This will install K8s and configure the server to run pods, it will also install
Flannel network plugin
    * Wait for the flannel for your architecture to show `1` in all columns then press ctrl+c
8. If something fails, you can reset with `sudo kubeadm reset`, delete kubeadminit.lock and try again, all the
scripts are safe to re-run.
9. Verify Kubelet that is running with `sudo systemctl status kubelet`
Once Flannel is working, and you verified kubelet:
10. This step is optional if you want to enable running VMs with KVM and useing Cockpit as the UI
11. Verify kubectl works: (NOTE: Kubectl does not need sudo, it will fail with sudo)
    * `kubectl get nodes` ← gets all nodes, you should see your node listed and `Ready`
    * `kubectl get all --all-namespaces` ← shows everything that’s running in kubernetes

### Setting up your local machine for using k8s

On your local machine (NOTE: Only works on your local network):
1. Install kubectl (`brew install kubernetes-cli` or find the package for your linux distro that install kubectl,
kubernetes-client in Fedora)
2. `scp fedora-ip:~/.kube/config ~/.kube/config` <-- configuration file for connecting to the cluster
3. Test with `kubectl get nodes` you should see your node listed, if not check the permissions on the config file
(should be owned by your user/group).
4. Install Flux CLI with `brew install fluxcd/tap/flux`

### To install the applications

1. On the root of project create a directory under clusters/ and copy the ClusterKustomization.yaml from another cluster
2. Modify ClusterKustomization to change the name and the path, you can also here add variables to replace that are unique to your deployment under postBuild:
3. run `cp ./infrastructure/setup/secrets.env.example ./clusters/[YOUR NAME HERE]/secrets.env`
4. Fill in secrets with your passwords and other settings
5. make a directory in your cluster folder called apps and create a kustomization.yaml inside, look at the clusters in this repo 
    1. Add in each app you'd like to deploy
    2. You can create other HelmRealeases, Kustomizations, or plain k8s files in this folder they will all be synced up to your k8s cluster   
6. Install flux and configure your cluster by running `./infrastructure/setup/install-flux.sh [your folder name here]` 
7. A SealedSecret.yaml file will be created in your folder, you can commit this file, your secrets.env should be ignored. The values haven been encrypted with a cert stored in your cluster.
8. Finally add the GitRepo with `kubectl apply -f ./infrastructure/setup/GitRepoSync.yaml`

### To delete all applications

1. Comment the file references from your apps/kustomization.yaml file and reconcile.

## Services Included:

All URLs are the service's url as a subdomain of the CLUSTER_DOMAIN_NAME secret
(See `secrets.example.sh`). e.g. dashboard.example.com. All of these are defaults they can be customized per release
by copying the original file and changing the values to suit your needs.

| Service Name                                                    | URL                                    | Port               | Docs                                                   |
|:----------------------------------------------------------------|:---------------------------------------|:-------------------|--------------------------------------------------------|
| Cert Manager                                                    | -                                      | -                  | [README](https://github.com/jetstack/cert-manager)     |
| Cronjobs (rdiff-backup)                                         | -                                      | -                  | [Docs](https://www.nongnu.org/rdiff-backup/docs.html)  |
| NGINX Ingress                                                   | -                                      | 80, 443            | [README](https://kubernetes.github.io/ingress-nginx/)  |
| K8s Dashboard                                                   | dashboard                              | -                  | [README](https://github.com/kubernetes/dashboard)      |
| Plex                                                            | plex                                   | -                  | [README](https://github.com/munnerz/kube-plex)         |
| Torrents (Transmission, OpenVPN, Prowlarr,<br />Radarr, Sonarr) | transmission,<br />movies, tv, seedbox | -                  | -                                                      |
| Gogs                                                            | gogs                                   | -                  | [README](https://hub.helm.sh/charts/incubator/gogs)    |
| Resilio Sync                                                    | resilio                                | -                  | -                                                      |
| Prometheus                                                      | prometheus                             | -                  | [README](https://hub.helm.sh/charts/stable/prometheus) |
| AlertManager (Prometheus)                                       | alerts                                 | -                  | Same                                                   |
| Grafana                                                         | grafana                                | -                  | [README](https://hub.helm.sh/charts/stable/grafana)    |
| No-ip                                                           | -                                      | -                  | [README](https://hub.helm.sh/charts/stabl)             |

## Node maintenance

### How to reboot a node

1. Run this to stop all pods, delete-local-data doesnt actually delete anything, if any pods are using emptyDir as a
volume it gets deleted, is just a warning.

    `kubectl drain [node-name] --ignore-daemonsets --delete-local-data`

2. Do any maintenance needed and reboot
3. Run this to allow pods to be started on this node again.

    `kubectl uncordon [node-name]`

### How to upgrade the kubernetes control plane and nodes

It's fairly easy and I've done it before successfully.

1. `yum list --showduplicates kubeadm --disableexcludes=kubernetes` find the latest of the next version in the list it should look like 1.XY.x-0, where x is the latest patch
2. Install kubeadm replace x in 1.21.x-0 with the latest patch version `yum install -y kubeadm-1.XY.x-0 --disableexcludes=kubernetes`
   1. Verify that the download works and has the expected version: `kubeadm version`
   2. Verify the upgrade plan: `kubeadm upgrade plan` This command checks that your cluster can be upgraded, and fetches the versions you can upgrade to. It also shows a table with the component config version states.
3. Choose a version to upgrade to, and run the appropriate command. For example:
`sudo kubeadm upgrade apply v1.XY.x`
Once the command finishes you should see:
`[upgrade/successful] SUCCESS! Your cluster was upgraded to "v1.21.x". Enjoy!`
4. Drain the node `kubectl drain k8s-master --ignore-daemonsets --delete-emptydir-data`
5. Upgrade kubelet and kubectl
`yum install -y kubelet-1.XY.x-0 kubectl-1.XY.x-0 --disableexcludes=kubernetes`
6. Restart the kubelet:
   1. `sudo systemctl daemon-reload`
   2. `sudo systemctl restart kubelet`
7. Uncordon the node `kubectl uncordon k8s-master`
8. Full instructions here https://v1-21.docs.kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade/

## License

Unless specifically noted, all parts of this project are licensed under the [MIT license](https://github.com/gandazgul/k8s-infrastructure/blob/main/LICENSE.md).

## Contributing

Contributions are more than welcome. Please open a PR with a good title and description of the change you are making.
Links to docs or examples are great.
