#!/usr/bin/env bash

rm -rf ./clusters/gandazgul/flux-system/SealedSecrets.json
kubectl create secret generic secrets --dry-run=client --from-env-file=./clusters/gandazgul/setup/secrets.env -o json \
 | kubeseal > ./clusters/gandazgul/flux-system/SealedSecrets.json
