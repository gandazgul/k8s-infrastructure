#!/usr/bin/env bash

set -e

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

# make sure all required binaries are installed
need "kubectl"
need "flux"
need "git"
need "kubeseal"
need "jq"

# check if have the cluster name, otherwise set it to the current user
if [ -z ${1+x} ]; then
  echo -e "Cluster Name was not specified. Assuming \e[1;32m$(whoami)\e[0m as the cluster name."
  CLUSTER_NAME=$(whoami)
else
  CLUSTER_NAME=$1
fi

# The root of the git repo
REPO_ROOT=$(git rev-parse --show-toplevel)

if [ ! -f "$REPO_ROOT/clusters/$CLUSTER_NAME/secrets.env" ]; then
  echo "The secrets.env file for $CLUSTER_NAME does not exist. Please create it."
  exit 1
fi
