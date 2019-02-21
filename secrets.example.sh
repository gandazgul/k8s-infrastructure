#!/bin/bash

# optional: Instead you can create yasr-volume/configs/openvpn/credentials.conf
export OPENVPN_USERNAME=""
export OPENVPN_PASSWORD=""

# required
export TRANSMISSION_RPC_PASSWORD=""
export ADMIN_PASSWORD=""
export MAIL_TO=""
export SMTP_PASSWORD=""

# required - ingress config
# Services will use this name for their ingresses
export INGRESS_INTERNAL_NAME="example.org"
# Gogs and any other services exposed to the outside world will use this name
export INGRESS_EXTERNAL_NAME="example.com"

# to secure the gogs install
export GOGS_SECRET_KEY="changeme"

#docker repositories
export REPOSITORY_USERNAME=""

# Master node information
MASTER_SERVER=`kubectl config view -o jsonpath='{.clusters[0].cluster.server}'`;
export MASTER_IP=`printf "${MASTER_SERVER}" | awk -F: '{print $2}' | awk -F/ '{print $3}'`
export MASTER_NODE_NAME=`kubectl get nodes --selector=node-role.kubernetes.io/master -o=jsonpath='{.items[0].metadata.labels.kubernetes\.io/hostname}'`

echo "Using MASTER_IP=$MASTER_IP"
echo "Using MASTER_NODE_NAME=$MASTER_NODE_NAME"
echo "Using INGRESS_INTERNAL_NAME=$INGRESS_INTERNAL_NAME"
echo "Using INGRESS_EXTERNAL_NAME=$INGRESS_EXTERNAL_NAME"
