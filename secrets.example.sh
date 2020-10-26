#!/bin/bash

# required
# A username used in several places
export REPOSITORY_USERNAME=""
# A password used for a couple of services
export ADMIN_PASSWORD=""
# An email address for notifications
export MAIL_TO=""
# The smtp password to authenticate with gmail for sending notifications (application passwords on your google account)
export SMTP_PASSWORD=""
# VPN User name
export VPN_USER=""
# VPN Password
export VPN_PASSWORD=""

# required - ingress config
# Services will use this name for their ingresses (get one free at https://noip.com)
export INGRESS_INTERNAL_NAME="example.sytes.net"
# Gogs and any other services exposed to the outside world will use this name
export INGRESS_EXTERNAL_NAME="example.com"

# to secure the gogs install
export GOGS_SECRET_KEY="changeme"

# Master node information
MASTER_IP=`kubectl get nodes --selector=node-role.kubernetes.io/master -o=jsonpath='{.items[0].metadata.annotations.flannel\.alpha\.coreos\.com\/public-ip}'`
export MASTER_IP
MASTER_NODE_NAME=`kubectl get nodes --selector=node-role.kubernetes.io/master -o=jsonpath='{.items[0].metadata.labels.kubernetes\.io/hostname}'`
export MASTER_NODE_NAME

echo "Using MASTER_IP=$MASTER_IP"
echo "Using MASTER_NODE_NAME=$MASTER_NODE_NAME"
echo "Using INGRESS_INTERNAL_NAME=$INGRESS_INTERNAL_NAME"
echo "Using INGRESS_EXTERNAL_NAME=$INGRESS_EXTERNAL_NAME"
