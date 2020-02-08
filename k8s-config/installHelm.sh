#!/bin/bash

echo "Installing helm with the tiller plugin ========================================================================="
if [ ! -f ~/.helm/plugins ]; then
    curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash
#    helm init --client-only
    mkdir -p ~/.helm/plugins
    helm plugin install https://github.com/databus23/helm-diff --version master || exit 1
    helm ls || exit 1
    echo "If you see any errors before this line then helm didn't install ============================================"
else
    echo "Looks like helm is already installed."
fi;
