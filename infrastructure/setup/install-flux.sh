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
  flux check --pre >/dev/null
  FLUX_PRE=$?
  if [ $FLUX_PRE != 0 ]; then
    echo -e "Flux prereqs not met:\n"
    flux check --pre
    exit 1
  fi

  message "Bootstrapping cluster with Flex components..."
  kubectl apply -k "$REPO_ROOT"/infrastructure/flux-system/components/

  FLUX_INSTALLED=$?
  if [ $FLUX_INSTALLED != 0 ]; then
    echo -e "Flux did not install correctly, aborting!"
    exit 1
  fi
}

configureCluster() {
  message "Installing $CLUSTER_NAME configs..."

  echo "Generating $CLUSTER_NAME secret..."
  # Seal main secrets file
  rm -rf "./clusters/$CLUSTER_NAME/sealed-secret/SealedSecret.yaml"
  kubectl create secret generic secrets --dry-run=client --namespace=flux-system --from-env-file="./clusters/$CLUSTER_NAME/secrets.env" -o json |
    kubeseal -o yaml >"./clusters/$CLUSTER_NAME/sealed-secret/SealedSecret.yaml"

  # apply it
  template=$(sed "s/{{CLUSTER_NAME}}/$CLUSTER_NAME/g" <"$REPO_ROOT"/infrastructure/setup/SealedSecretsKustomization.yaml.templ)
  # apply the yml with the substituted value
  echo "$template" | kubectl apply -f - || exit 1

  # Create value/yaml secrets
  echo "Generating $CLUSTER_NAME app secrets from values..."
  rm -rf "./clusters/$CLUSTER_NAME/apps/secrets/"
  mkdir "./clusters/$CLUSTER_NAME/apps/secrets/"
  cat <<EOT >> "./clusters/$CLUSTER_NAME/apps/secrets/kustomization.yaml"
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
EOT

  for f in ./clusters/"$CLUSTER_NAME"/apps/values/*.yaml; do
    echo "Generating secrets from values file: $f..."
    basename=$(basename "$f" .yaml)
    kubectl create secret generic "${basename}" --dry-run=client --from-file=values.yaml="${f}" -o yaml >"./clusters/$CLUSTER_NAME/apps/secrets/${basename}.yaml"
    echo "- ${basename}.yaml" >> "./clusters/$CLUSTER_NAME/apps/secrets/kustomization.yaml"
  done

  kubectl apply -f "./clusters/$CLUSTER_NAME/ClusterKustomization.yaml"

  echo "Done configuring $CLUSTER_NAME's cluster"
}

if [ -z ${1+x} ]; then
  echo "Make sure to pass in a cluster name as install-flux.sh [name here]"
  exit 1
fi

need "kubectl"
need "helm"
need "flux"
need "git"

CLUSTER_NAME=$1

installFlux
# wait for secrets controller to be available
while :; do
  kubectl get svc sealed-secrets-controller -n kube-system && break
  sleep 5
done

configureCluster

message "all done!"
