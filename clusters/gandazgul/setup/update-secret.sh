#!/usr/bin/env bash

# Seal main secrets file
rm -rf ./clusters/gandazgul/sealed-secrets/SealedSecret.yaml
kubectl create secret generic secrets --dry-run=client --namespace=flux-system --from-env-file=./clusters/gandazgul/setup/secrets.env -o json \
 | kubeseal -o yaml > ./clusters/gandazgul/sealed-secrets/SealedSecret.yaml
# apply it
kubectl apply -f ./clusters/gandazgul/sealed-secrets/SealedSecret.yaml
flux reconcile kustomization kube-system
flux reconcile kustomization apps

# Create value/yaml secrets
rm -rf ./clusters/gandazgul/apps/secrets/
mkdir ./clusters/gandazgul/apps/secrets/

for f in ./clusters/gandazgul/apps/values/*.yaml
do
  echo "Processing $f file..."
  basename=$(basename "$f" .yaml)
  kubectl create secret generic "${basename}" --dry-run=client --from-file=values.yaml="${f}" -o yaml > "./clusters/gandazgul/apps/secrets/${basename}.yaml"
done
