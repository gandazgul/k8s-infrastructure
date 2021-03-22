#!/usr/bin/env bash

need() {
    if ! command -v "$1" &> /dev/null
    then
        echo "Binary '$1' is missing but required"
        exit 1
    fi
}

need "kubectl"
need "helm"
need "flux"
need "git"

REPO_ROOT=$(git rev-parse --show-toplevel)
# shellcheck source=clusters/gandazgul/setup/secrets.env
. "$REPO_ROOT"clusters/gandazgul/setup/secrets.env

# Master node information
MASTER_IP=`kubectl get nodes --selector=node-role.kubernetes.io/master -o=jsonpath='{.items[0].metadata.annotations.flannel\.alpha\.coreos\.com\/public-ip}'`
# TODO: automatically update secrets.env?
MASTER_NODE_NAME=`kubectl get nodes --selector=node-role.kubernetes.io/master -o=jsonpath='{.items[0].metadata.labels.kubernetes\.io/hostname}'`
# TODO: automatically update secrets.env?

echo "Using MASTER_IP=$MASTER_IP"
echo "Using MASTER_NODE_NAME=$MASTER_NODE_NAME"
echo "Using INGRESS_INTERNAL_NAME=$INGRESS_INTERNAL_NAME"
echo "Using INGRESS_EXTERNAL_NAME=$INGRESS_EXTERNAL_NAME"
pause

message() {
  echo -e "\n######################################################################"
  echo "# $1"
  echo "######################################################################"
}

installFlux() {
  message "installing fluxv2"
  flux check --pre > /dev/null
  FLUX_PRE=$?
  if [ $FLUX_PRE != 0 ]; then
    echo -e "flux prereqs not met:\n"
    flux check --pre
    exit 1
  fi
  if [ -z "$GITHUB_TOKEN" ]; then
    echo "GITHUB_TOKEN is not set! Check $REPO_ROOT/setup/secrets.env"
    exit 1
  fi
  flux bootstrap github \
    --owner="$GITHUB_USER" \
    --repository=k8s-infrastructure \
    --branch=feature/gitops \
    --path=./clusters/gandazgul \
    --personal

  FLUX_INSTALLED=$?
  if [ $FLUX_INSTALLED != 0 ]; then
    echo -e "flux did not install correctly, aborting!"
    exit 1
  fi
}

installFlux
call ./update-secret.sh

message "all done!"
kubectl get nodes -o=wide
