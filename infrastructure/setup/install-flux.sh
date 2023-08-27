#!/usr/bin/env bash

# check if have the cluster name
if [ -z ${1+x} ]; then
  echo "Make sure to pass in a cluster name like this: install-flux.sh [name here]"
  exit 1
fi

CLUSTER_NAME=$1
REPO_ROOT=$(git rev-parse --show-toplevel)

# Check that all required binaries are installed
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "$SCRIPT_DIR/requirements.sh"

######################## Install Flux ###################################

# Control plane node information
CONTROL_PLANE_IP=$(kubectl get nodes --selector=node-role.kubernetes.io/control-plane -o=jsonpath='{.items[0].metadata.annotations.flannel\.alpha\.coreos\.com\/public-ip}')
CONTROL_PLANE_NAME=$(kubectl get nodes --selector=node-role.kubernetes.io/control-plane -o=jsonpath='{.items[0].metadata.labels.kubernetes\.io/hostname}')

# Confirm information
echo "Using CONTROL_PLANE_IP=$CONTROL_PLANE_IP"
echo "Using CONTROL_PLANE_NAME=$CONTROL_PLANE_NAME"
echo "Using CLUSTER_NAME=$CLUSTER_NAME"
pause

# Update secrets file
secretFile="$REPO_ROOT/clusters/$CLUSTER_NAME/secrets.env"
sed -i '' "s/\(CONTROL_PLANE_IP=*\).*/\1$CONTROL_PLANE_IP/" "$secretFile" || exit 1
sed -i '' "s/\(CONTROL_PLANE_NAME=*\).*/\1$CONTROL_PLANE_NAME/" "$secretFile" || exit 1

message "Installing Flux v2"

if ! flux check --pre; then
  echo -e "Flux pre-reqs not met see above..."
  exit 1
fi

if ! flux install --components-extra=image-reflector-controller,image-automation-controller; then
  echo -e "Flux did not install correctly, aborting!"
  exit 1
fi

message "Installing the Git Repo Source"
if ! kubectl apply -f "$REPO_ROOT"/infrastructure/setup/GitRepoSync.yaml; then
  echo -e "Flux did not install correctly, aborting!"
  exit 1
fi

message "Installing Sealed Secrets"
if ! kubectl apply -f "$REPO_ROOT"/infrastructure/kube-system/SealedSecretsController.yaml; then
  echo -e "Sealed secrets didn't install correctly, aborting!"
  exit 1
fi

message "Waiting for secrets controller to be available..."
while :; do
  kubectl get svc sealed-secrets-controller -n kube-system && break
  sleep 15
done

# Creating/Updating Sealed Secrets -------------------
"$SCRIPT_DIR/configure-cluster.sh" "$CLUSTER_NAME"

message "all done!"
