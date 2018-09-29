#!/bin/bash

printf "\nLetting the master node run pods ==========================================================================\n"
MASTER_HOSTNAME=`kubectl get nodes -o jsonpath='{.items[0].metadata.name}'`
kubectl taint node $MASTER_HOSTNAME node-role.kubernetes.io/master:NoSchedule-

printf "\nInstalling Hostpath Provisioner ===========================================================================\n"
kubectl apply -f ./hostpath.yaml || exit 1

MASTER_SERVER=`kubectl config view -o jsonpath='{.clusters[0].cluster.server}'`;
MASTER_IP=`printf "${MASTER_SERVER}" | awk -F: '{print $2}' | awk -F/ '{print $3}'`

printf "\nInstalling Ingress controller =============================================================================\n"
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/mandatory.yaml
kubectl apply -f ./ingress.yaml
kubectl patch service ingress-nginx --namespace=ingress-nginx --patch '{"spec": {"externalIPs": ["'${MASTER_IP}'"]}}'

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

printf "\n"
printf "\n"
printf "=============================================================================================================\n"
printf "=========== Dashboard Installed! ============================================================================\n"
printf "=========== https://${MASTER_IP}:8443/ ======================================================================\n"
printf "=============================================================================================================\n"
printf "Token: \n"
cat dashboard.token

