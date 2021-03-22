#!/usr/bin/env bash

# Seal main secrets file
rm -rf ./clusters/gandazgul/sealed-secrets/SealedSecrets.json
kubectl create secret generic secrets --dry-run=client --from-env-file=./clusters/gandazgul/setup/secrets.env -o json \
 | kubeseal > ./clusters/gandazgul/sealed-secrets/SealedSecrets.json

# Create value/yaml secrets
rm -rf ./clusters/gandazgul/apps/secrets/
mkdir ./clusters/gandazgul/apps/secrets/

for f in ./clusters/gandazgul/apps/values/*.yaml
do
  echo "Processing $f file..."
  basename=$(basename "$f" .yaml)
  kubectl create secret generic "${basename}" --dry-run=client --from-file=values.yaml="${f}" -o json > "./clusters/gandazgul/apps/secrets/${basename}.json"
done
