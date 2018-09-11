# My Infrastructure Config

My architecture when I finish this will be an old machine running the k8s control stuff and a pretty good small business server running as a node, with other nodes being added as needed.

Mostly each service will have its own container with the exception of the seedbox which is flexget and transmission running together with OpenVPN.

## Getting started

1. Install Fedora 28
2. Copy k8s-config/ to the Fedora machine
3. `cd k8s-config/ && chmod +x *.sh && ./configMaster.sh`

This will install a fully functioning kubernetes master where you can run all of the apps.

Use helmfile to sync up the helmfile.yaml file to get all of the services up and running. Customize for your needs. 

## Services I plan to run:

* K8s Dashboard
* Plex
* Resilio Sync
* File Browser
* Samba
* Seedbox (transmission, flexget, OpenVPN)
* Gogs
* Custom web apps as containerized apps
* And others

## Access

Each service will be accessed a little different depending on what it is. The dashboard, plex and transmission will probably just open their ports on the machine they are on.
For others I'll use an ingress controller and path (http://server_name/app_name) config. If I end up adding more nodes this will probably have to change.

DNS?
