#!/bin/bash

if [[ $EUID = 0 ]]; then
   printf "Don't run this script as root"
   exit 1
fi

#printf "\nGet docker ===============================================================================================\n"
#if [ ! -f docker-ce-17.03.2.ce-1.fc25.x86_64.rpm ]; then
#    # TODO: try new docker versions now supported in Kubernetes 1.13.1
#    # https://download.docker.com/linux/fedora/28/x86_64/stable/Packages/
#    # https://github.com/kubernetes/kubernetes/blob/master/CHANGELOG-1.13.md#external-dependencies
#
#    wget https://download.docker.com/linux/fedora/25/x86_64/stable/Packages/docker-ce-17.03.2.ce-1.fc25.x86_64.rpm || exit 1
#    wget https://download.docker.com/linux/fedora/25/x86_64/stable/Packages/docker-ce-selinux-17.03.2.ce-1.fc25.noarch.rpm || exit 1
#
#    printf "\nInstall docker & deps ====================================================================================\n"
#    sudo dnf -y install policycoreutils-python || exit 1
#    sudo mkdir -p /var/lib/docker || exit 1
#    sudo rpm -i docker-ce-selinux-17.03.2.ce-1.fc25.noarch.rpm || exit 1
#    sudo rpm -i docker-ce-17.03.2.ce-1.fc25.x86_64.rpm || exit 1
#fi;

if dnf list installed docker >/dev/null 2>&1; then
    printf "\nInstall docker & deps ====================================================================================\n"
    sudo dnf -y install docker-1.13.1*
    sudo dnf update --exclude="docker"

    printf "\nEnable docker ============================================================================================\n"
    sudo systemctl enable --now docker || exit 1

    printf "\nVerify docker is working by running hello-world ==========================================================\n"
    sudo docker run --rm hello-world || exit 1
fi;

# There are no good cri-o RPMs
#if ! dnf list installed cri-o > /dev/null 2>&1; then
#    printf "\nInstall cri-o ===========================================================================================\n"
#    sudo dnf config-manager --add-repo=https://cbs.centos.org/repos/paas7-crio-113-candidate/x86_64/os/
#
#    sudo dnf -y install --nogpgcheck cri-o cri-tools || exit 1
#
#    printf "\nEnable cri-o ============================================================================================\n"
#    sudo systemctl enable --now cri-o || exit 1
#
#    printf "\nVerify cri-o is working by running hello-world ==========================================================\n"
#    if ! systemctl is-active --quiet cri-o >/dev/null 2>&1; then
#        printf "\nSomething failed while installing cri-o please verify that is running and run this script again"
#        exit 1
#    fi;
#fi;

printf "\nDisable SELINUX because kubelet doesnt support it ========================================================\n"
sudo setenforce 0
echo "SELINUX=disabled" | sudo tee /etc/sysconfig/selinux

printf "\nInstalling Kubernetes packages from repo =================================================================\n"
if [[ ! -f /etc/yum.repos.d/kubernetes.repo ]]; then
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
    sudo dnf -y install cockpit-kubernetes cockpit-pcp || exit 1
fi;

printf "\nEnabling cockpit =========================================================================================\n"
sudo systemctl enable --now cockpit.socket || exit 1

printf "\nDisabling swap ===========================================================================================\n"
sudo swapoff -a || exit 1

if dnf list installed firewalld >/dev/null 2>&1; then
    printf "\nDisabling the firewall ===================================================================================\n"
    sudo systemctl stop firewalld
    sudo systemctl disable firewalld
    # fedora 29 complained that uninstalling firewalld would uninstall kernel-core
    # sudo dnf -y remove firewalld
    # Masking prevents the service from ever being started
    sudo systemctl mask firewalld.service

    # Enable ipv4 forwarding
    echo 1 | sudo tee --append /proc/sys/net/ipv4/ip_forward
    # fedora 29 doesnt support bridges out of the box?
#    sudo modprobe overlay # do I need this?
    # enable iptables in the kernel
    sudo modprobe br_netfilter
    # This ensured all network traffic goes through iptables
    echo 1 | sudo tee --append /proc/sys/net/bridge/bridge-nf-call-iptables
fi;
