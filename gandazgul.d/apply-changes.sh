#!/usr/bin/env bash

kubectl config use-context home

source ./gandazgul.d/secrets.sh

echo ""
echo -n "Do you wish to proceed? (y/n)? "
read answer
if [ "$answer" != "${answer#[Yy]}" ] ;then
    helmfile -f ./gandazgul.d/ apply
fi;
