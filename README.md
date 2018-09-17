# My Infrastructure Config

My architecture when I finish this will be an old machine running the k8s control stuff and a pretty good small business server running as a node, with other nodes being added as needed.

Mostly each service will have its own container with the exception of the seedbox which is flexget and transmission running together with OpenVPN.

## Getting started

This will install a fully functioning kubernetes master where you can run all of your services.

1. Install Fedora 28
2. Check out this repo on local machine
3. `scp -r ./k8s-config fedora-ip:~/`
4. `ssh fedora-ip`
5. `cd k8s-config/ && chmod +x *.sh && ./configMaster.sh`
6. If something fails, reset with `sudo kubeadm reset` and try again, the other commands are repeatable

Verify Kubelet that is running with `sudo systemctl status kubelet`

If you see this: `failed to run Kubelet: failed to create kubelet: misconfiguration: kubelet cgroup driver: "systemd" is different from docker cgroup driver: "cgroupfs"` 
Look up how to change docker's cgroup from cgroupfs to systemd. Restart the machine.

### Verify kubectl works:

NOTE: Kubectl does not need sudo, it will fail with sudo

* `kubectl get nodes` ← gets all nodes
* `kubectl get all --all-namespaces` ← shows everything that’s running in kubernetes

### Setting up your local machine for using k8s

On your local machine (NOTE: Only works on your local network):
1. Install kubectl (`brew install kubernetes-client` or find the package for your linux distro that install kubectl)
2. `scp fedora-ip:~/.kube/config ~/.kube/config` <-- configuration file for connecting to the cluster
3. Test with `kubectl get nodes` you should see your node listed, if not check the permissions on the config file (should be owned by your user/group).
4. Install helm with ./k8s-config/installHelm.sh. This installs helm without tiller, instead it uses the tiller plugin to run tiller locally :)
    1. Test helm with:
    2. `helm tiller start` <-- starts bash with tiller enabled
    3. `helm list` <-- Should see no output, if error then something went wrong
    4. `exit`
5. Install helmfile: `brew install helmfile` (for linux see helmfile's releases: https://github.com/roboll/helmfile/releases)

### To Install the services

1. Customize helmfile.yaml to your needs
2. On the root of infrastructure `cp ./secrets.example.sh ./secrets.sh`
3. Fill in secrets with your passwords and other settings
4. run `source ./secrets.sh` to set up the passwords/settings
5. run `helmfile sync` - to setup the rest of the services (`helmfile charts` to retry/update after)
6. `helm list` to see what is installed
6. `helm delete --purge [NAME]` to remove one particular service if you need to retry 

## Services Included:

* Volumes for service configs and data
* K8s Dashboard
* Plex
* Resilio Sync
* FileBrowser
* Seedbox (transmission, flexget, OpenVPN)
* NFS Shares Server
* SSHD - for tunneling, etc
* Gogs
* Samba

## Access

Each service will be accessed a little different depending on what it is. The dashboard, plex and transmission will 
probably just open their ports on the machine they are on. If I end up adding more nodes this will probably have to 
change.

DNS?
