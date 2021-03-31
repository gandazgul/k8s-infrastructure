#!/bin/bash

./configNode.sh || exit 1

printf "\nInstalling kubernetes ===================================================================================\n"
# Check if kubeadm already ran, do kubeadm reset to re-run
if [[ ! -f "/etc/kubernetes/kubelet.conf" ]]; then
    sudo systemctl enable kubelet.service
    sudo kubeadm config images pull
    sudo kubeadm init --config=./kubeadm.yaml --cri-socket=unix:///var/run/crio/crio.sock || exit 1
else
    printf "\nNOTE: Looks like kubeadm init already ran. If you want to run it again, run kubeadm reset ===============\n"
fi;

printf "\nCopy kubectl config ======================================================================================\n"
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

printf "\nInstalling flannel =======================================================================================\n"
kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml

printf "\n\n=========================================================================================================\n"
printf "Kubernetes is now installed. Please check the status of flannel and kubelet to make sure the network is ready before we proceed to the next step."
printf "\nVerify that is running:\n"
kubectl get nodes
printf "\n"
kubectl get ds --watch --namespace=kube-system

echo -n "I have to restart in order to finish installing K8s. After reboot, run step 3. Reboot? (y/n)? "
    read answer
    if [ "$answer" != "${answer#[Yy]}" ] ;then
        sudo reboot
    fi;
