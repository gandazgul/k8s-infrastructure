#!/bin/bash

if [[ $EUID = 0 ]]; then
   printf "Don't run this script as root"
   exit 1
fi

if ! dnf list installed cri-o > /dev/null 2>&1; then
    printf "\nInstall cri-o and crun ================================================================================\n"
    sudo dnf -y module enable cri-o:1.24 || exit 1
    sudo dnf -y install crun cri-o || exit 1
    sudo dnf update --exclude="cri-*" || exit 1

    printf "\nRaising user watches to the highest number to allow kubelet to work with lots of containers ===========\n"
    echo fs.inotify.max_user_watches=1048576 | sudo tee --append /etc/sysctl.conf
    echo fs.inotify.max_user_instances=1048576 | sudo tee --append /etc/sysctl.conf
fi;

cat /etc/crio/crio.conf | grep default_runtime | grep crun
GREP_RE=$?
if [ $GREP_RE != 0 ]; then
  printf "\nChange cri-o's config to work with crun ===============================================================\n"
  sudo sed -c -i "s/\(default_runtime *= *\).*/\1\"crun\"/" /etc/crio/crio.conf || exit 1
  echo "[crio.runtime.runtimes.crun]" | sudo tee --append /etc/crio/crio.conf || exit 1
  echo "runtime_path = \"/usr/bin/crun\"" | sudo tee --append /etc/crio/crio.conf || exit 1
  echo "runtime_type = \"oci\"" | sudo tee --append /etc/crio/crio.conf || exit 1
  echo "runtime_root = \"/run/crun\"" | sudo tee --append /etc/crio/crio.conf || exit 1

  printf "\nEnable cri-o ==========================================================================================\n"
  sudo systemctl daemon-reload || exit 1
  sudo systemctl enable --now crio || exit 1
  sudo systemctl start crio || exit 1

  printf "\nVerify cri-o is running ===============================================================================\n"
  if ! systemctl is-active --quiet crio >/dev/null 2>&1; then
      printf "\nSomething failed while installing cri-o please verify that is running and run this script again"
      exit 1
  fi;
fi;

printf "\nInstalling Kubernetes packages from repo ==================================================================\n"
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

    sudo dnf -y install --enablerepo=kubernetes kubelet-1.24.11-0 kubectl-1.24.11-0 kubeadm-1.24.11-0 --disableexcludes=kubernetes || exit 1
    sudo dnf -y install cockpit-pcp || exit 1

    # enable cni plugins
    sudo mkdir -p /opt/cni/
    sudo ln -s /usr/libexec/cni/ /opt/cni/bin
fi;

printf "\nEnabling cockpit ==========================================================================================\n"
sudo systemctl enable --now cockpit.socket || exit 1

if dnf list installed zram-generator-defaults > /dev/null 2>&1; then
  printf "\nDisabling swap ==========================================================================================\n"
  sudo dnf -y remove zram-generator-defaults
  sudo systemctl stop swap-create@zram0 || exit 1
  sudo swapoff /dev/zram0 || exit 1
fi

if systemctl is-active --quiet firewalld >/dev/null 2>&1; then
    printf "\nDisabling the firewall ================================================================================\n"
    sudo systemctl stop firewalld
    sudo systemctl disable firewalld
    # fedora 29 complained that uninstalling firewalld would uninstall kernel-core
    # sudo dnf -y remove firewalld
    # Masking prevents the service from ever being started
    sudo systemctl mask firewalld.service

    # needed for cri-o
    sudo modprobe overlay
    # enable iptables in the kernel
    sudo modprobe br_netfilter
    cat <<EOF | sudo tee /etc/modules-load.d/crio.conf
overlay
br_netfilter
EOF

    # Enable ipv4 forwarding
    echo 1 | sudo tee --append /proc/sys/net/ipv4/ip_forward
    # This ensures all network traffic goes through iptables
    echo 1 | sudo tee --append /proc/sys/net/bridge/bridge-nf-call-iptables

    # same as above?
    cat <<EOF | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

# make the above settings take effect now
sudo sysctl --system
fi;
