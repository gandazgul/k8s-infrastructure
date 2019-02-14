#!/bin/bash

printf "\nLetting the master node run pods ==========================================================================\n"
MASTER_HOSTNAME=`kubectl get nodes --selector=node-role.kubernetes.io/master -o=jsonpath='{.items[0].metadata.name}'`
kubectl taint node $MASTER_HOSTNAME node-role.kubernetes.io/master:NoSchedule-

printf "\nInstalling Hostpath Provisioner ===========================================================================\n"
kubectl apply -f ./hostpath.yaml || exit 1

printf "\nCreating CA TLS secret =======================================================================================\n"
sudo -E kubectl --namespace=default create secret tls ca-key-pair --key=/etc/kubernetes/pki/ca.key --cert=/etc/kubernetes/pki/ca.crt

printf "\nInstalling the dashboard ==================================================================================\n"
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/master/src/deploy/recommended/kubernetes-dashboard.yaml
kubectl apply -f ./dashboard.yaml || exit 1
DASHBOARD_USER_SECRET=`kubectl -n kube-system get secret | grep admin-user | awk '{print $1}'`
if [ ! -z "$DASHBOARD_USER_SECRET" ]; then
    printf "\nDashboard installed!\n"
    kubectl -n kube-system describe secret ${DASHBOARD_USER_SECRET} | grep token: | awk -F: '{gsub(/^[ \t]+/, "", $2); print $2}' > dashboard.token
else
    printf "\nSomething went wrong getting the credentials for the dashboard\n"
fi;

./installHelm.sh

MASTER_SERVER=`kubectl config view -o jsonpath='{.clusters[0].cluster.server}'`;
MASTER_IP=`printf "${MASTER_SERVER}" | awk -F: '{print $2}' | awk -F/ '{print $3}'`

printf "\n"
printf "\n"
printf "=============================================================================================================\n"
printf "=========== Dashboard Installed! ============================================================================\n"
printf "=========== https://${MASTER_IP}:8443/ ======================================================================\n"
printf "=============================================================================================================\n"
printf "Token: \n"
cat dashboard.token

