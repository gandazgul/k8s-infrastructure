#!/usr/bin/env bash

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
CLUSTER_NAME=$1
REPO_ROOT=$(git rev-parse --show-toplevel)

source "$SCRIPT_DIR/requirements.sh"

# Seal main secrets file
message "Generating $CLUSTER_NAME secret..."
rm -rf "./clusters/$CLUSTER_NAME/sealed-secret/SealedSecret.yaml"
kubectl create secret generic secrets --dry-run=client --namespace=kube-system --from-env-file="./clusters/$CLUSTER_NAME/secrets.env" -o json |
  kubeseal -o yaml > "./clusters/$CLUSTER_NAME/sealed-secret/SealedSecret.yaml"

# Create a kustomization for the cluster's Secrets so that apps can depend on it
template=$(sed "s/{{CLUSTER_NAME}}/$CLUSTER_NAME/g" <"$REPO_ROOT"/infrastructure/setup/SealedSecretsKustomization.yaml.templ)
# apply the yml with the substituted value
echo "$template" | kubectl apply -f - || exit 1

# Create value/yaml secrets
message "Generating $CLUSTER_NAME app secrets from values..."
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
  kubectl -n default create secret generic "${basename}" --dry-run=client --from-file=values.yaml="${f}" -o yaml >"./clusters/$CLUSTER_NAME/apps/secrets/${basename}.yaml"
  echo "- ${basename}.yaml" >> "./clusters/$CLUSTER_NAME/apps/secrets/kustomization.yaml"
done

message "Installing $CLUSTER_NAME configs..."
kubectl apply -f "./clusters/$CLUSTER_NAME/ClusterKustomization.yaml"

message "Done configuring $CLUSTER_NAME's cluster"
