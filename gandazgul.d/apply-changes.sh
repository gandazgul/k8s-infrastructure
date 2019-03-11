#!/usr/bin/env bash

kubectl config use-context home

helm tiller stop

source ./gandazgul.d/secrets.sh

echo ""
echo -n "Do you wish to proceed? (y/n)? "
read answer
if [ "$answer" != "${answer#[Yy]}" ] ;then
    helm tiller run helmfile -f ./gandazgul.d/ apply
fi;
