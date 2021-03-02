#!/bin/bash

while [[ $# -gt 0 ]]
do
key="$1"

case $key in
  --hcloud-token)
    TOKEN="$2"
    shift
    shift
  ;;
  --whitelisted-ips)
    WHITELIST_S="$2"
    shift
    shift
  ;;
  --floating-ips)
    FLOATING_IPS="1"
    shift
  ;;
  *)
    shift
  ;;
esac
done

FLOATING_IPS=${FLOATING_IPS:-"0"}

if [ "$FLOATING_IPS" == "1" ]; then
  FLOATING_IPS=( $(curl -H 'Accept: application/json' -H "Authorization: Bearer ${TOKEN}" 'https://api.hetzner.cloud/v1/floating_ips' | jq -r '.floating_ips[].ip') )    

  for IP in "${FLOATING_IPS[@]}"; do
    ip addr add $IP/32 dev eth0
  done  
fi
