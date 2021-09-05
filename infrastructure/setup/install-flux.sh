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

  message "installing Flux v2"
  flux check --pre >/dev/null
  FLUX_PRE=$?
  if [ $FLUX_PRE != 0 ]; then
    echo -e "Flux prereqs not met:\n"
    flux check --pre
    exit 1
  fi

  kubectl apply -k "$REPO_ROOT"/infrastructure/flux-system/components/

  FLUX_INSTALLED=$?
  if [ $FLUX_INSTALLED != 0 ]; then
    echo -e "Flux did not install correctly, aborting!"
    exit 1
  fi
}

if [ -z ${1+x} ]; then
  echo "Make sure to pass in a cluster name as install-flux.sh [name here]"
  exit 1
fi;

installFlux
# wait for secrets controller to be available
while : ; do
  kubectl get svc sealed-secrets-controller -n kube-system && break
  sleep 5
done

"$REPO_ROOT"/infrastructure/setup/bootstrap-cluster.sh "$1"

message "all done!"
