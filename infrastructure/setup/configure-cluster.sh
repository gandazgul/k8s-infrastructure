#!/usr/bin/env bash

# The directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "$SCRIPT_DIR/requirements.sh"

# Seal main secrets file with SealedSecrets
message "Generating $CLUSTER_NAME secret..."
rm -rf "$REPO_ROOT/clusters/$CLUSTER_NAME/sealed-secret/SealedSecret.yaml"
kubectl create secret generic secrets --dry-run=client --namespace=kube-system --from-env-file="$REPO_ROOT/clusters/$CLUSTER_NAME/secrets.env" -o json |
  jq '.metadata.annotations |= { "reflector.v1.k8s.emberstack.com/reflection-auto-enabled": "true", "reflector.v1.k8s.emberstack.com/reflection-allowed": "true", "reflector.v1.k8s.emberstack.com/reflection-allowed-namespaces": "default" }' |
  kubeseal -o yaml > "$REPO_ROOT/clusters/$CLUSTER_NAME/sealed-secret/SealedSecret.yaml"

# apply the sealed secret
kubectl apply -f "$REPO_ROOT/clusters/$CLUSTER_NAME/sealed-secret/SealedSecret.yaml"

# Create a Kustomization for the cluster's Secrets so that apps can depend on it
echo "$(sed "s/{{CLUSTER_NAME}}/$CLUSTER_NAME/g" <"$SCRIPT_DIR"/SealedSecretsKustomization.yaml.templ)" | kubectl apply -f -

# Create value/yaml secrets
message "Generating $CLUSTER_NAME app secrets from values..."
rm -rf "$REPO_ROOT/clusters/$CLUSTER_NAME/apps/secrets/"
mkdir "$REPO_ROOT/clusters/$CLUSTER_NAME/apps/secrets/"
cat <<EOT >> "$REPO_ROOT/clusters/$CLUSTER_NAME/apps/secrets/kustomization.yaml"
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
EOT

for f in "$REPO_ROOT"/clusters/"$CLUSTER_NAME"/apps/values/*.yaml; do
  echo "Generating secrets from values file: $f..."
  basename=$(basename "$f" .yaml)
  kubectl -n default create secret generic "${basename}" --dry-run=client --from-file=values.yaml="${f}" -o yaml >"$REPO_ROOT/clusters/$CLUSTER_NAME/apps/secrets/${basename}.yaml"
  echo "- ${basename}.yaml" >> "$REPO_ROOT/clusters/$CLUSTER_NAME/apps/secrets/kustomization.yaml"
done

message "Installing $CLUSTER_NAME configs..."
kubectl apply -f "$REPO_ROOT/clusters/$CLUSTER_NAME/ClusterKustomization.yaml"

message "Done configuring $CLUSTER_NAME's cluster"
