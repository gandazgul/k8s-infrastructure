#!/bin/bash

if [ -z "$1" ]
then
  echo "Please supply a domain to create a certificate for cockpit";
  echo "e.g. ./3-installStorageAndHelm.sh www.mysite.com"
  exit;
fi

printf "\nInstalling Hostpath Provisioner ===========================================================================\n"
kubectl apply -f ./hostpath.yaml || exit 1

printf "\nCreating CA TLS secret ====================================================================================\n"
kubectl create namespace ingress
sudo -E kubectl --namespace=ingress create secret tls ca-key-pair --key=/etc/kubernetes/pki/ca.key --cert=/etc/kubernetes/pki/ca.crt

printf "\nCreating a certificate for cockpit ========================================================================\n"
sudo -E ./createCertificateForDomain.sh $1
cat $1.crt > 1-$1.cert
echo "" >> 1-$1.cert
cat device.key >> 1-$1.cert
sudo -E mv 1-$1.cert /etc/cockpit/ws-certs.d/

./installHelm.sh
