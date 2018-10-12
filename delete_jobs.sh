#!/usr/bin/env bash

set -x

for j in $(kubectl get jobs --namespace=services -o custom-columns=:.metadata.name)
do
    kubectl delete jobs $j &
done
