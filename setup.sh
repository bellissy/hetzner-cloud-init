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
  --registry)
    REGISTRY_URL="$2"
    shift
    shift
  ;;
  --auth-user)
    AUTH_USER="$2"
    shift
    shift
  ;;
  --auth-password)
    AUTH_PASSWORD="$2"
    shift
    shift
  ;;
  --floating-ips)
    FLOATING_IPS="--floating-ips"
    shift
  ;;
  *)
    shift
  ;;
esac
done

if [[ ! -z $REGISTRY_URL && ! -z $AUTH_USER && ! -z $AUTH_PASSWORD ]]; then
cat <<EOF > /usr/local/bin/find_latest_shas.sh
#!/usr/bin/env bash

REGISTRY_URL=$REGISTRY_URL
AUTH_USER=$AUTH_USER
AUTH_PW=$AUTH_PASSWORD
REPOS=\$(curl -s -u \$AUTH_USER:\$AUTH_PW https://\$REGISTRY_URL/v2/_catalog | jq -r .repositories[])

for REPO in \$REPOS; do
    echo \$AUTH_PW | docker login -u \$AUTH_USER --password-stdin \$REGISTRY_URL
    docker pull --all-tags \$REGISTRY_URL/\$REPO
done
EOF

chmod +x /usr/local/bin/find_latest_shas.sh
cat <<EOF >> /etc/crontab
* * * * * root /usr/local/bin/find_latest_shas.sh
EOF
fi

FLOATING_IPS=${FLOATING_IPS:-""}


sed -i 's/[#]*PermitRootLogin yes/PermitRootLogin prohibit-password/g' /etc/ssh/sshd_config
sed -i 's/[#]*PasswordAuthentication yes/PasswordAuthentication no/g' /etc/ssh/sshd_config

systemctl restart sshd

cat <<EOF >> /etc/sysctl.d/99-custom.conf
vm.overcommit_memory=1
vm.panic_on_oom=0
kernel.panic=10
kernel.panic_on_oops=1
kernel.keys.root_maxbytes=25000000
EOF

sysctl -p /etc/sysctl.d/99-custom.conf



wget https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64
chmod +x jq-linux64
mv jq-linux64 /usr/local/bin/jq

curl -o /usr/local/bin/rke-node-kubeconfig.sh https://raw.githubusercontent.com/bellissy/hetzner-cloud-init/master/rke-node-kubeconfig.sh

chmod +x /usr/local/bin/rke-node-kubeconfig.sh

curl -o /usr/local/bin/kubectl https://raw.githubusercontent.com/bellissy/hetzner-cloud-init/master/kubectl

chmod +x /usr/local/bin/kubectl

curl -o /usr/local/bin/update-config.sh https://raw.githubusercontent.com/bellissy/hetzner-cloud-init/master/update-config.sh

chmod +x /usr/local/bin/update-config.sh

ufw allow proto tcp from any to any port 22,80,443

IFS=', ' read -r -a WHITELIST <<< "$WHITELIST_S"

for IP in "${WHITELIST[@]}"; do
  ufw allow from "$IP"
done

ufw allow from 10.43.0.0/16
ufw allow from 10.42.0.0/16
ufw allow from 10.0.0.0/16 # default private network cidr
ufw allow from 10.244.0.0/16 # in case we use the default cidr expected by the cloud controller manager

ufw -f default deny incoming
ufw -f default allow outgoing

ufw -f enable

cat <<EOF >> /etc/crontab
* * * * * root /usr/local/bin/update-config.sh --hcloud-token ${TOKEN} --whitelisted-ips ${WHITELIST_S} ${FLOATING_IPS}
EOF

cat <<EOF >> /etc/crontab
30 * * * * root docker system prune -a -f
EOF

/usr/local/bin/update-config.sh --hcloud-token ${TOKEN} --whitelisted-ips ${WHITELIST_S} ${FLOATING_IPS}
