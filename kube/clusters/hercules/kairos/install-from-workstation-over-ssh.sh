#!/bin/bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
ssh-keygen -R $1
ssh root@$1 curl -o /root/.ssh/authorized_keys "https://github.com/JJGadgets.keys"
scp -rO ./kairos-takeover.sh root@$1:/tmp/kairos-takeover.sh
# scp -rO ./cloud-config.yaml root@$1:/root/config.yaml
sops exec-env ../config/secrets.sops.env "envsubst < ./cloud-config.yaml" | ssh root@$1 "cat >/root/config.yaml"
ssh root@$1 chmod +x /tmp/kairos-takeover.sh
ssh root@$1 /tmp/kairos-takeover.sh
