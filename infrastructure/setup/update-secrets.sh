#!/usr/bin/env bash

for cluster in ./clusters/*/ ; do
    echo "Processing $cluster"
    # Seal main secrets file
    rm -rf "$cluster"SealedSecret.yaml
    kubectl create secret generic secrets --dry-run=client --namespace=flux-system --from-env-file="$cluster"secrets.env -o json \
     | kubeseal -o yaml > "$cluster"SealedSecret.yaml
    # apply it
    kubectl apply -f "$cluster"SealedSecret.yaml
    clusterName="$(basename $cluster)"
    flux reconcile kustomization "$clusterName"

    # Create value/yaml secrets
    rm -rf "$cluster"apps/secrets/
    mkdir "$cluster"apps/secrets/

    for f in "$cluster"apps/values/*.yaml
    do
      echo "Generating secrets from values file: $f..."
      basename=$(basename "$f" .yaml)
      kubectl create secret generic "${basename}" --dry-run=client --from-file=values.yaml="${f}" -o yaml > ""$cluster"apps/secrets/${basename}.yaml"
    done

done
