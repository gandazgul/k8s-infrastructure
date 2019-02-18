# Grafana Configs

This chart installs the datasource for prometheus, a custom dashboard for kubernetes capacity and the username and 
password for grafana. 

Username: admin
Password: The value of the environment variable: `ADMIN_PASSWORD`. Set it on secrets.sh.

## Kubernetes config

To install the plugin for kubenetes clone this repo: `https://github.com/grafana/kubernetes-app.git` in 
`yasr-volume` in this path: `/configs/grafana/plugins`. 

### Enabling the plugin after install:

To enable the plugin after install see this: https://github.com/grafana/kubernetes-app/issues/35

All the needed data is stored in your .kube/config YAML:

1. Run this `kubectl config view -o jsonpath='{.clusters[0].cluster.server}'` and paste that into HTTP URL
2. Select `Server (Default)` from Access
3. Check the boxes "TLS Client Auth" and "With CA Cert"
4. Fill out the "CA Cert", "Client Cert", and "Client Key" fields like so:
    * Fill the CA Cert value with this command 
        `kubectl config view --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -D`
    * Fill the Client Cert with this:
        `kubectl config view --raw -o jsonpath='{.users[0].user.client-certificate-data}' | base64 -D` 
    * Fill the Client Key with this:
        `kubectl config view --raw -o jsonpath='{.users[0].user.client-key-data}' | base64 -D`
5. Select Prometheus-server from the Datasource field

FYI to Grafana people: it would probably be good if somebody documents this somewhere!
