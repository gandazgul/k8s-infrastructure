#!/usr/bin/env bash

if [ -z ${1+x} ]; then
  echo "Make sure to pass in a cluster name as install-flux.sh [name here]"
  exit 1
fi

CLUSTER_NAME=$1

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "$SCRIPT_DIR/requirements.sh"

installFlux() {
  REPO_ROOT=$(git rev-parse --show-toplevel)

  # Control plane node information
  CONTROL_PLANE_ID=$(kubectl get nodes --selector=node-role.kubernetes.io/control-plane -o=jsonpath='{.items[0].metadata.annotations.flannel\.alpha\.coreos\.com\/public-ip}')
  CONTROL_PLANE_NAME=$(kubectl get nodes --selector=node-role.kubernetes.io/control-plane -o=jsonpath='{.items[0].metadata.labels.kubernetes\.io/hostname}')

  # Confirm information
  echo "Using CONTROL_PLANE_ID=$CONTROL_PLANE_ID"
  echo "Using CONTROL_PLANE_NAME=$CONTROL_PLANE_NAME"
  echo "Using CLUSTER_NAME=$CLUSTER_NAME"
  pause

  # Update secrets file
  secretFile="$REPO_ROOT/clusters/$CLUSTER_NAME/secrets.env"
  sed -i '' "s/\(CONTROL_PLANE_ID=*\).*/\1$CONTROL_PLANE_ID/" "$secretFile" || exit 1
  sed -i '' "s/\(CONTROL_PLANE_NAME=*\).*/\1$CONTROL_PLANE_NAME/" "$secretFile" || exit 1

  message "installing Flux v2"

  if ! flux check --pre; then
    echo -e "Flux prereqs not met see above..."
    exit 1
  fi

  if ! flux install; then
    echo -e "Flux did not install correctly, aborting!"
    exit 1
  fi

  if ! kubectl apply -f "$REPO_ROOT"/infrastructure/setup/GitRepoSync.yaml; then
    echo -e "Flux did not install correctly, aborting!"
    exit 1
  fi
}

######################## Install Flux ###################################
installFlux
# wait for secrets controller to be available
while :; do
  kubectl get svc sealed-secrets-controller -n kube-system && break
  sleep 15
done

"$SCRIPT_DIR/configure-cluster.sh" "$CLUSTER_NAME"

kubectl apply -f "./clusters/$CLUSTER_NAME/ClusterKustomization.yaml"

message "all done!"
