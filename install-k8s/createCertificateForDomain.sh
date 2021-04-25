#!/usr/bin/env bash

if [ -z "$1" ]
then
  echo "Please supply a subdomain to create a certificate for";
  echo "e.g. www.mysite.com"
  exit;
fi

if [ ! -f v3.ext ]; then
  echo 'Please download the "v3.ext" file and try again!'
  exit;
fi

# Create a new private key if one doesnt exist, or use the existing one if it does
if [ -f device.key ]; then
  KEY_OPT="-key"
else
  KEY_OPT="-keyout"
fi

DOMAIN=$1
COMMON_NAME=${2:-$1}
SUBJECT="/C=CA/ST=None/L=NB/O=None/CN=$COMMON_NAME"
NUM_OF_DAYS=3650
openssl req -new -newkey rsa:2048 -sha256 -nodes $KEY_OPT device.key -subj "$SUBJECT" -out device.csr
cat v3.ext | sed s/%%DOMAIN%%/"$COMMON_NAME"/g > /tmp/__v3.ext
openssl x509 -req -in device.csr -CA /etc/kubernetes/pki/ca.crt -CAkey /etc/kubernetes/pki/ca.key -CAcreateserial -out device.crt -days $NUM_OF_DAYS -sha256 -extfile /tmp/__v3.ext

# move output files to final filenames
mv device.csr "$DOMAIN.csr"
mv device.crt "$DOMAIN.crt"

echo
echo "###########################################################################"
echo Done!
echo "###########################################################################"
