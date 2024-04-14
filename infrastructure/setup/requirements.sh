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
need "flux"
need "git"
need "kubeseal"
need "jq"
