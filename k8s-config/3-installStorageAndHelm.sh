#!/bin/bash

if [ -z "$1" ]
then
  echo "Please supply a domain to create a certificate for cockpit";
  echo "e.g. ./3-installStorageAndHelm.sh www.mysite.com"
  exit;
fi

printf "\nCreating CA TLS secret ====================================================================================\n"
kubectl create namespace ingress
sudo -E kubectl --kubeconfig=/home/gandazgul/.kube/config --namespace=ingress create secret tls ca-key-pair --key=/etc/kubernetes/pki/ca.key --cert=/etc/kubernetes/pki/ca.crt

printf "\nCreating a certificate for cockpit ========================================================================\n"
DOMAIN=$1
sudo -E ./createCertificateForDomain.sh $DOMAIN
sudo -E cat $DOMAIN.crt > 1-$DOMAIN.cert
sudo -E echo "" >> 1-$DOMAIN.cert
sudo -E cat device.key >> 1-$DOMAIN.cert
sudo -E mv 1-$DOMAIN.cert /etc/cockpit/ws-certs.d/

./installHelm.sh
