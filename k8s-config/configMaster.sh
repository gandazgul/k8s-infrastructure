#!/bin/bash

if [[ $EUID = 0 ]]; then
   echo "Don't run this script as root"
   exit 1
fi

echo "Upgrade ========================================================================================================"
sudo dnf -y update || exit 1

echo "\nGet docker ====================================================================================================="
if [ ! -f docker-ce-17.03.2.ce-1.fc25.x86_64.rpm ]; then
    wget https://download.docker.com/linux/fedora/25/x86_64/stable/Packages/docker-ce-17.03.2.ce-1.fc25.x86_64.rpm || exit 1
    wget https://download.docker.com/linux/fedora/25/x86_64/stable/Packages/docker-ce-selinux-17.03.2.ce-1.fc25.noarch.rpm || exit 1

    echo "\nInstall docker & deps ======================================================================================"
    sudo dnf -y install policycoreutils-python || exit 1
    sudo mkdir -p /var/lib/docker || exit 1
    sudo rpm -i docker-ce-selinux-17.03.2.ce-1.fc25.noarch.rpm || exit 1
    sudo rpm -i docker-ce-17.03.2.ce-1.fc25.x86_64.rpm || exit 1
fi;

echo "\nEnable docker =================================================================================================="
sudo systemctl enable --now docker || exit 1

echo "\nVerify docker is working by running hello-world"
sudo docker run hello-world

if [ ! -f /etc/yum.repos.d/kubernetes.repo ]; then
    echo "\nInstall kubelet, kubeadm, crictl(needed by kubelet), cockpit (nice fedora dashboard):"
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
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
exclude=kube*
EOF'
fi;

sudo setenforce 0
sudo dnf -y install --enablerepo=kubernetes kubelet kubectl --disableexcludes=kubernetes || exit 1
sudo dnf -y install --enablerepo=kubernetes-unstable kubeadm --disableexcludes=kubernetes || exit 1
sudo dnf -y install cockpit-docker cockpit-kubernetes git || exit 1

echo "\nEnabling cockpit ==============================================================================================="
sudo systemctl enable --now cockpit.socket || exit 1

echo "\nDisabling swap ================================================================================================="
sudo swapoff -a || exit 1

echo "\nDisabling the firewall ========================================================================================="
sudo systemctl stop firewalld || exit 1
sudo systemctl disable firewalld || exit 1
setenforce 0

echo "\nInstalling kubernetes =========================================================================================="
sudo systemctl enable kubelet.service
sudo kubeadm config images pull
sudo kubeadm init --config=./kubeadm.yaml || exit 1

echo "\nCopy kubectl config ========================================================================================"
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

echo "\nVerify that is running: ========================================================================================"
kubectl get nodes
kubectl get all --all-namespaces
sudo systemctl status kubelet

echo "\nInstalling flannel ============================================================================================="
kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/k8s-manifests/kube-flannel-rbac.yml

echo "\nLetting the master node run pods ==============================================================================="
MASTER_HOSTNAME=`kubectl get nodes -o jsonpath='{.items[0].metadata.name}'`
kubectl taint node $MASTER_HOSTNAME node-role.kubernetes.io/master:NoSchedule-

echo "\nInstalling the dashboard ======================================================================================="
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/master/src/deploy/recommended/kubernetes-dashboard.yaml
kubectl apply -f ./dashboard.yaml || exit 1
DASHBOARD_USER_SECRET=`kubectl -n kube-system get secret | grep admin-user | awk '{print $1}'`
if [ ! -z "$DASHBOARD_USER_SECRET" ]; then
    MASTER_SERVER=`kubectl config view -o jsonpath='{.clusters[0].cluster.server}'`;
    DASHBOARD_URL=`echo "https://10.1.1.63:6443" | awk -F: '{print $2}'`
    echo "\nDashboard installed! visit: https:$DASHBOARD_URL:8443\n"
    kubectl -n kube-system describe secret ${DASHBOARD_USER_SECRET}
else
    echo "\nSomething went wrong getting the credentials for the dashboard"
fi;

./installHelm.sh
