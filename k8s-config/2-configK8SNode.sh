#!/bin/bash

./configNode.sh || exit 1

if [[ ! -n ${KUBE_JOIN_COMMAND} ]]; then
    printf "Run 'kubeadm token create --print-join-command' in the master to get a join command. Then re-run this script with KUBE_JOIN_COMMAND=command ./2-configK8SNode.sh"
    exit 1
fi;

printf "\nJoin Kubernetes Cluster ==================================================================================\n"
if [ ! -f "kubeadminit.lock" ]; then
    sudo systemctl enable kubelet.service
    # how to get this automatically
    eval ${KUBE_JOIN_COMMAND}
    touch kubeadminit.lock
else
    printf "\nNOTE: Looks like kubeadm init already ran. If you want to run it again, delete kubeadminit.lock =========\n"
fi;

printf "\n\n=========================================================================================================\n"
printf "Node is now joined. Verify that is running:\n"
kubectl get nodes
kubectl get ds --namespace=kube-system
printf "\n\n"
