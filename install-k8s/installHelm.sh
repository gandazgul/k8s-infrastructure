#!/bin/bash

echo "Installing helm with the tiller plugin ========================================================================="
if [ ! -f ~/.helm/plugins ]; then
    curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash
    helm repo add "stable" "https://charts.helm.sh/stable" --force-update
    helm ls || exit 1
    echo "If you see any errors before this line then helm didn't install ============================================"
else
    echo "Looks like helm is already installed."
fi;
