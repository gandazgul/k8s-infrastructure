#!/bin/bash

if [[ $EUID = 0 ]]; then
   printf "Don't run this script as root"
   exit 1
fi

printf "\nGet docker ===============================================================================================\n"
if [ ! -f docker-ce-18.06.2.ce-3.fc28.x86_64.rpm ]; then
    wget https://download.docker.com/linux/fedora/28/x86_64/stable/Packages/docker-ce-18.06.2.ce-3.fc28.x86_64.rpm || exit 1

    printf "\nInstall docker & deps ====================================================================================\n"
    sudo mkdir -p /var/lib/docker || exit 1
    sudo sudo dnf install -y docker-ce-18.06.2.ce-3.fc28.x86_64.rpm || exit 1
    sudo sed -i 's/rhgb quiet"/rhgb quiet systemd.unified_cgroup_hierarchy=0"/' /etc/default/grub || exit 1
    sudo sh -c 'grub2-mkconfig > /boot/efi/EFI/fedora/grub.cfg'  || exit 1

    echo -n "I have to restart in order to finish installing Docker. After reboot, re-run this script. Reboot? (y/n)? "
    read answer
    if [ "$answer" != "${answer#[Yy]}" ] ;then
        sudo reboot
    fi;
fi;

# only 19 is available
#if ! dnf list installed docker >/dev/null 2>&1; then
#    sudo dnf -y install dnf-plugins-core
#    sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
#
#    printf "\nInstall docker & deps ====================================================================================\n"
#    sudo dnf -y install docker-1.13.1*
#    sudo dnf update --exclude="docker"
#fi;

printf "\nEnable docker ============================================================================================\n"
sudo systemctl enable --now docker || exit 1

printf "\nVerify docker is working by running hello-world ==========================================================\n"
sudo docker run --rm hello-world || exit 1

# There are no cri-o rpms yet in the regular repos
#if ! dnf list installed cri-o > /dev/null 2>&1; then
#if [[ ! -f cri-o-1.13.0-1.gite8a2525.module_f29+3066+eba77a73.x86_64.rpm ]]; then
#    printf "\nDownload cri-o ===========================================================================================\n"
#    wget https://dl.fedoraproject.org/pub/fedora/linux/updates/testing/29/Modular/x86_64/Packages/c/cri-o-1.13.0-1.gite8a2525.module_f29+3066+eba77a73.x86_64.rpm
#    wget https://dl.fedoraproject.org/pub/fedora/linux/updates/testing/29/Modular/x86_64/Packages/c/cri-tools-1.13.0-1.gitc06001f.module_f29+3066+eba77a73.x86_64.rpm
#    sudo dnf update --exclude="cri-*"
#
#    printf "\nInstall cri-o ============================================================================================\n"
#    sudo dnf install -y ./cri-o-1.13.0-1.gite8a2525.module_f29+3066+eba77a73.x86_64.rpm ./cri-tools-1.13.0-1.gitc06001f.module_f29+3066+eba77a73.x86_64.rpm
#
#    printf "\nInstall cri-o ===========================================================================================\n"
#    sudo dnf -y install cri-o-1.13* cri-tools-1.13* || exit 1
#    sudo dnf update --exclude="cri-*"

#    printf "\nEnable cri-o =============================================================================================\n"
#    sudo systemctl enable --now cri-o || exit 1
#
#    printf "\nVerify cri-o is running ==========================================================\n"
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
    sudo dnf -y install cockpit-pcp || exit 1

    # enable cni plugins
    sudo mkdir -p /opt/cni/
    sudo ln -s /usr/libexec/cni/ /opt/cni/bin
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
    # needed for cri-o
#    sudo modprobe overlay
    # enable iptables in the kernel
    sudo modprobe br_netfilter
    # This ensured all network traffic goes through iptables
    echo 1 | sudo tee --append /proc/sys/net/bridge/bridge-nf-call-iptables
fi;
