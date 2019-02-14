#!/bin/bash

printf "\nLetting the master node run pods ==========================================================================\n"
MASTER_HOSTNAME=`kubectl get nodes --selector=node-role.kubernetes.io/master -o=jsonpath='{.items[0].metadata.name}'`
kubectl taint node $MASTER_HOSTNAME node-role.kubernetes.io/master:NoSchedule-

printf "\nInstalling Hostpath Provisioner ===========================================================================\n"
kubectl apply -f ./hostpath.yaml || exit 1

printf "\nCreating CA TLS secret =======================================================================================\n"
sudo -E kubectl --namespace=ingress create secret tls ca-key-pair --key=/etc/kubernetes/pki/ca.key --cert=/etc/kubernetes/pki/ca.crt

./installHelm.sh
