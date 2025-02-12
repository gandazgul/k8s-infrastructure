#!/usr/bin/env bash

# The directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "$SCRIPT_DIR/requirements.sh"

# Get the current branch name
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)

# Check if the current branch exists on the remote
if ! git ls-remote --exit-code origin "$CURRENT_BRANCH" &> /dev/null; then
  message "Branch $CURRENT_BRANCH does not exist on the remote. Pushing..."
  git push --set-upstream origin "$CURRENT_BRANCH"
fi

message "Changing branch to ${CURRENT_BRANCH}"
< "$SCRIPT_DIR"/GitRepoSync.yaml.templ sed "s/main/${CURRENT_BRANCH}/g" | kubectl apply -f -

message "Reconciling..."
flux reconcile kustomization --with-source kube-system -n kube-system && flux reconcile kustomization ${CLUSTER_NAME} -n kube-system
