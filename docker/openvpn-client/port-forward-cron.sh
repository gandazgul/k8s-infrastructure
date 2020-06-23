#!/usr/bin/env bash

if [ -f /vpn/port-fowarding.sh ]; then
  /vpn/port-fowarding.sh
else
  echo "/vpn/port-fowarding.sh doesn't exist"
fi
