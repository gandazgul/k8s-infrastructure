#!/usr/bin/env bash

#for cluster in ./clusters/*/ ; do
if [ -z ${1+x} ]; then
  echo "Make sure to pass in a cluster name as install-flux.sh [name here]"
  exit 1
fi

clusterName=$1
echo "Installing $clusterName configs..."
echo "Generating $clusterName secret..."
# Seal main secrets file
rm -rf "./clusters/$clusterName/SealedSecret.yaml"
kubectl create secret generic secrets --dry-run=client --namespace=flux-system --from-env-file="./clusters/$clusterName/secrets.env" -o json |
  kubeseal -o yaml >"./clusters/$clusterName/SealedSecret.yaml"

# apply it
kubectl apply -f "./clusters/$clusterName/SealedSecret.yaml"

# Create value/yaml secrets
echo "Generating $clusterName app secrets from values..."
rm -rf "./clusters/$clusterName/apps/secrets/"
mkdir "./clusters/$clusterName/apps/secrets/"

for f in ./clusters/"$clusterName"/apps/values/*.yaml; do
  echo "Generating secrets from values file: $f..."
  basename=$(basename "$f" .yaml)
  kubectl create secret generic "${basename}" --dry-run=client --from-file=values.yaml="${f}" -o yaml > "./clusters/$clusterName/apps/secrets/${basename}.yaml"
done

kubectl apply -f "./clusters/$clusterName/ClusterKustomization.yaml"

echo "Done configuring $clusterName's cluster"
