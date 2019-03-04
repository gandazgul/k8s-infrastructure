#!/usr/bin/env bash

kubectl config use-context tony

helm tiller stop
helm tiller start &

source ./secondary-master.d/secrets.sh

echo ""
echo -n "Do you wish to proceed? (y/n)? "
read answer
if [ "$answer" != "${answer#[Yy]}" ] ;then
    helmfile -f ./secondary-master.d/ apply
fi;

helm tiller stop
kubectl config use-context home
