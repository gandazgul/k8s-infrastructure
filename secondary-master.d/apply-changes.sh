#!/usr/bin/env bash

kubectl config use-context tony

source ./secondary-master.d/secrets.sh

echo ""
echo -n "Do you wish to proceed? (y/n)? "
read answer
if [ "$answer" != "${answer#[Yy]}" ] ;then
    helmfile -f ./secondary-master.d/ apply
fi;

kubectl config use-context home
