#!/bin/bash

# required
# A username used in several places
export REPOSITORY_USERNAME=""
# A password used for a couple of services
export ADMIN_PASSWORD=""
# An email address for notifications, its also used as the login for SMTP at gmail
export MAIL_TO=""
# The smtp password to authenticate with gmail for sending notifications (application passwords on your google account)
export SMTP_PASSWORD=""
# VPN User name
export VPN_USER=""
# VPN Password
export VPN_PASSWORD=""

# required - ingress config
# Services will use this name for their ingresses (get a free name at freenom.com)
# set the DNS for a wildcard *.example.sytes.net -> your k8s host internal IP.
export CLUSTER_DOMAIN_NAME="example.sytes.net"

# to secure the gogs install
export GOGS_SECRET_KEY="changeme"

# Control Plane node information, these secrets are automatically obtained from k8s
CONTROL_PLANE_IP=`kubectl get nodes --selector=node-role.kubernetes.io/control-plane -o=jsonpath='{.items[0].metadata.annotations.flannel\.alpha\.coreos\.com\/public-ip}'`
export CONTROL_PLANE_IP
CONTROL_PLANE_NAME=`kubectl get nodes --selector=node-role.kubernetes.io/control-plane -o=jsonpath='{.items[0].metadata.labels.kubernetes\.io/hostname}'`
export CONTROL_PLANE_NAME

echo "Using CONTROL_PLANE_IP=$CONTROL_PLANE_IP"
echo "Using CONTROL_PLANE_NAME=$CONTROL_PLANE_NAME"
echo "Using CLUSTER_DOMAIN_NAME=$CLUSTER_DOMAIN_NAME"
