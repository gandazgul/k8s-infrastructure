#!/bin/bash

./configNode.sh

printf "\nInstalling kubernetes ====================================================================================\n"
if [ ! -f "kubeadminit.lock" ]; then
    sudo systemctl enable kubelet.service
    sudo kubeadm config images pull
    sudo kubeadm init --config=./kubeadm.yaml || exit 1
    touch kubeadminit.lock
else
    printf "\nNOTE: Looks like kubeadm init already ran. If you want to run it again, delete kubeadminit.lock ======\n"
fi;

printf "\nCopy kubectl config ======================================================================================\n"
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

printf "\nInstalling flannel =======================================================================================\n"
kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/k8s-manifests/kube-flannel-rbac.yml

printf "\n\n=========================================================================================================\n"
printf "Kubernetes is now installed. Please check the status of flannel and kubelet to make sure the network is ready before we proceed to the next step."
printf "\nVerify that is running:\n"
kubectl get nodes
kubectl get ds --namespace=kube-system
printf "Run 'sudo systemctl status kubelet' to see how kubelet is doing\n\n"
