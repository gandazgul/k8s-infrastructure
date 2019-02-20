#!/bin/bash

if [[ $EUID = 0 ]]; then
   printf "Don't run this script as root"
   exit 1
fi

printf "\nGet docker ===============================================================================================\n"
if [ ! -f docker-ce-17.03.2.ce-1.fc25.x86_64.rpm ]; then
    # TODO: try new docker versions now supported in Kubernetes 1.13.1
    # https://download.docker.com/linux/fedora/28/x86_64/stable/Packages/
    # https://github.com/kubernetes/kubernetes/blob/master/CHANGELOG-1.13.md#external-dependencies

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

printf "\nVerify docker is working by running hello-world ==========================================================\n"
sudo docker run --rm hello-world || exit 1

printf "\nDisable SELINUX because kubelet doesnt support it ========================================================\n"
sudo setenforce 0
echo "SELINUX=disabled" | sudo tee /etc/sysconfig/selinux

printf "\nInstalling Kubernetes packages from repo =================================================================\n"
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

    sudo dnf -y install --enablerepo=kubernetes kubelet kubectl kubeadm --disableexcludes=kubernetes || exit 1
    sudo dnf -y install cockpit-docker cockpit-kubernetes cockpit-pcp || exit 1
fi;

printf "\nEnabling cockpit =========================================================================================\n"
sudo systemctl enable --now cockpit.socket || exit 1

printf "\nDisabling swap ===========================================================================================\n"
sudo swapoff -a || exit 1

printf "\nDisabling the firewall ===================================================================================\n"
sudo systemctl stop firewalld
sudo systemctl disable firewalld
sudo dnf -y remove firewalld
