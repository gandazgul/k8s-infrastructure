#!/bin/bash

if [[ $EUID = 0 ]]; then
   printf "Don't run this script as root"
   exit 1
fi

printf "Upgrade ====================================================================================================\n"
sudo dnf -y update || exit 1

printf "\nGet docker ===============================================================================================\n"
if [ ! -f docker-ce-17.03.2.ce-1.fc25.x86_64.rpm ]; then
    wget https://download.docker.com/linux/fedora/25/x86_64/stable/Packages/docker-ce-17.03.2.ce-1.fc25.x86_64.rpm || exit 1
    wget https://download.docker.com/linux/fedora/25/x86_64/stable/Packages/docker-ce-selinux-17.03.2.ce-1.fc25.noarch.rpm || exit 1

    printf "\nInstall docker & deps ====================================================================================\n"
    sudo dnf -y install policycoreutils-python || exit 1
    sudo mkdir -p /var/lib/docker || exit 1
    sudo rpm -i docker-ce-selinux-17.03.2.ce-1.fc25.noarch.rpm || exit 1
    sudo rpm -i docker-ce-17.03.2.ce-1.fc25.x86_64.rpm || exit 1
fi;

printf "\nEnable docker ============================================================================================\n"
sudo systemctl enable --now docker || exit 1

printf "\nVerify docker is working by running hello-world"
sudo docker run --rm hello-world

if [ ! -f /etc/yum.repos.d/kubernetes.repo ]; then
    printf "\nInstall kubelet, kubeadm, crictl(needed by kubelet), cockpit (nice fedora dashboard):"
    sudo bash -c 'cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
exclude=kube*

[kubernetes-unstable]
name=Kubernetes-unstable
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64-unstable
enabled=0
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
exclude=kube*
EOF'
fi;

sudo setenforce 0
sudo dnf -y install --enablerepo=kubernetes kubelet kubectl --disableexcludes=kubernetes || exit 1
sudo dnf -y install --enablerepo=kubernetes-unstable kubeadm --disableexcludes=kubernetes || exit 1
sudo dnf -y install cockpit-docker cockpit-kubernetes || exit 1

printf "\nEnabling cockpit =========================================================================================\n"
sudo systemctl enable --now cockpit.socket || exit 1

printf "\nDisabling swap ===========================================================================================\n"
sudo swapoff -a || exit 1

printf "\nDisabling the firewall ===================================================================================\n"
sudo systemctl stop firewalld
sudo systemctl disable firewalld
sudo dnf -y remove firewalld
sudo setenforce 0
echo "SELINUX=disabled" | sudo tee -a /etc/sysconfig/selinux

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
kubectl get all --all-namespaces
printf "Run 'sudo systemctl status kubelet' to see how kubelet is doing"
