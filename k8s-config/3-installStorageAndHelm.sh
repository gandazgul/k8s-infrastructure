#!/bin/bash

printf "\nInstalling Hostpath Provisioner ===========================================================================\n"
kubectl apply -f ./hostpath.yaml || exit 1

printf "\nCreating CA TLS secret ====================================================================================\n"
kubectl create namespace ingress
sudo -E kubectl --namespace=ingress create secret tls ca-key-pair --key=/etc/kubernetes/pki/ca.key --cert=/etc/kubernetes/pki/ca.crt

printf "\nCreating a certificate for cockpit ========================================================================\n"
./createCertificateForDomain.sh $MASTER_HOSTNAME
cat k8s.sytes.net.crt > 1-k8s.sytes.net.cert
echo "" >> 1-k8s.sytes.net.cert
cat device.key >> 1-k8s.sytes.net.cert
sudo -E mv 1-k8s.sytes.net.cert /etc/cockpit/ws-certs.d/

./installHelm.sh
