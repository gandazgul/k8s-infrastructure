#!/bin/bash

if [[ $EUID = 0 ]]; then
   printf "Don't run this script as root"
   exit 1
fi

printf "\nInstalling cri-o from its repo ==================================================================\n"
if ! dnf list installed cri-o > /dev/null 2>&1; then
  sudo bash -c 'cat <<EOF | tee /etc/yum.repos.d/cri-o.repo
[cri-o]
name=CRI-O
baseurl=https://pkgs.k8s.io/addons:/cri-o:/stable:/v1.32/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/addons:/cri-o:/stable:/v1.32/rpm/repodata/repomd.xml.key
EOF'

  printf "\nInstalling cri-o dependencies\n"
  sudo dnf install -y \
      conntrack \
      container-selinux \
      ebtables \
      ethtool \
      iptables \
      socat

  printf "\nInstalling cri-o\n"
  sudo dnf install -y --repo cri-o cri-o

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
    printf "\nInstall kubelet, kubeadm and kubectl"
    sudo bash -c 'cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.32/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.32/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF'

    sudo dnf -y install --enablerepo=kubernetes kubelet kubectl kubeadm --disableexcludes=kubernetes || exit 1
    # cockpit-pcp enables the metric graphs in cockpit
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
