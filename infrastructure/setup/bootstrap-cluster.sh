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

need "kubectl"
need "helm"
need "flux"
need "git"

installFlux() {
  REPO_ROOT=$(git rev-parse --show-toplevel)
  # shellcheck source=clusters/gandazgul/setup/secrets.env
  export $(cat "$REPO_ROOT"/infrastructure/setup/secrets.env | sed 's/#.*//g' | xargs)

  # Master node information
  # TODO: automatically update secrets.env?
  MASTER_IP=$(kubectl get nodes --selector=node-role.kubernetes.io/master -o=jsonpath='{.items[0].metadata.annotations.flannel\.alpha\.coreos\.com\/public-ip}')
  MASTER_NODE_NAME=$(kubectl get nodes --selector=node-role.kubernetes.io/master -o=jsonpath='{.items[0].metadata.labels.kubernetes\.io/hostname}')

  echo "Using MASTER_IP=$MASTER_IP"
  echo "Using MASTER_NODE_NAME=$MASTER_NODE_NAME"
  echo "Using INGRESS_INTERNAL_NAME=$INGRESS_INTERNAL_NAME"
  echo "Using INGRESS_EXTERNAL_NAME=$INGRESS_EXTERNAL_NAME"
  pause

  message "installing fluxv2"
  flux check --pre >/dev/null
  FLUX_PRE=$?
  if [ $FLUX_PRE != 0 ]; then
    echo -e "flux prereqs not met:\n"
    flux check --pre
    exit 1
  fi
#  if [ -z "$GITHUB_TOKEN" ]; then
#    echo "GITHUB_TOKEN is not set! Check $REPO_ROOT/clusters/gandazgul/setup/secrets.env"
#    exit 1
#  fi
#  flux bootstrap github \
#    --owner="$GITHUB_USER" \
#    --repository=k8s-infrastructure \
#    --branch=feature/gitops \
#    --path=./clusters/gandazgul/flux-system/ \
#    --personal
  kubectl apply -k ./clusters/gandazgul/flux-system/components/

  FLUX_INSTALLED=$?
  if [ $FLUX_INSTALLED != 0 ]; then
    echo -e "flux did not install correctly, aborting!"
    exit 1
  fi
}

installFlux
# wait for secrets controller to be available
while : ; do
  kubectl get svc sealed-secrets-controller -n kube-system && break
  sleep 5
done
"$REPO_ROOT"/clusters/gandazgul/setup/update-secret.sh

message "all done!"
kubectl get nodes -o=wide
