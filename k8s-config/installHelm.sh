#!/bin/bash

echo "Installing helm with the tiller plugin ========================================================================="
if [ ! -f ~/.helm/plugins ]; then
    curl https://raw.githubusercontent.com/kubernetes/helm/master/scripts/get | bash
    mkdir -p ~/.helm/plugins
    helm plugin install https://github.com/rimusz/helm-tiller || exit 1
    helm tiller run helm list || exit 1
    echo "If you see any errors before this line then helm didn't install ============================================"
    echo "Usage: helm tiller start|stop|run"
else
    echo "Looks like helm is already installed."
fi;
