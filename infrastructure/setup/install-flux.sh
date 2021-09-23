#!/usr/bin/env bash

need() {
  if ! command -v "$1" &>/dev/null; then
    echo "Binary '$1' is missing but required"
    exit 1
  fi
}

message() {
  echo -e "\n######################################################################"
  echo "# $1"
  echo "######################################################################"
}

pause() {
  read -r -s -n 1 -p "Check these values. If anything looks wrong stop now and check the secrets.env file. Press any key to continue . . ."
  echo ""
}

installFlux() {
  REPO_ROOT=$(git rev-parse --show-toplevel)

  # Master node information
  MASTER_IP=$(kubectl get nodes --selector=node-role.kubernetes.io/master -o=jsonpath='{.items[0].metadata.annotations.flannel\.alpha\.coreos\.com\/public-ip}')
  MASTER_NODE_NAME=$(kubectl get nodes --selector=node-role.kubernetes.io/master -o=jsonpath='{.items[0].metadata.labels.kubernetes\.io/hostname}')

  # Confirm information
  echo "Using MASTER_IP=$MASTER_IP"
  echo "Using MASTER_NODE_NAME=$MASTER_NODE_NAME"
  echo "Using CLUSTER_NAME=$CLUSTER_NAME"
  pause

  # Update secrets file
  secretFile="$REPO_ROOT/clusters/$CLUSTER_NAME/secrets.env"
  sed -i '' "s/\(MASTER_IP=*\).*/\1$MASTER_IP/" "$secretFile" || exit 1
  sed -i '' "s/\(MASTER_NODE_NAME=*\).*/\1$MASTER_NODE_NAME/" "$secretFile" || exit 1

  message "installing Flux v2"

  if ! flux check --pre; then
    echo -e "Flux prereqs not met see above..."
    exit 1
  fi

  if ! flux install; then
    echo -e "Flux did not install correctly, aborting!"
    exit 1
  fi

  if ! kubectl apply -f "$REPO_ROOT"/infrastructure/flux-system/GitRepoSync.yaml; then
    echo -e "Flux did not install correctly, aborting!"
    exit 1
  fi
}

if [ -z ${1+x} ]; then
  echo "Make sure to pass in a cluster name as install-flux.sh [name here]"
  exit 1
fi

need "kubectl"
need "helm"
need "flux"
need "git"
need kubeseal

CLUSTER_NAME=$1

installFlux
# wait for secrets controller to be available
while :; do
  kubectl get svc sealed-secrets-controller -n kube-system && break
  sleep 5
done

call ./configure-cluster.sh "$CLUSTER_NAME"

message "all done!"
