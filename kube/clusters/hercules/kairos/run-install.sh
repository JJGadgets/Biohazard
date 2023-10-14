#!/bin/bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
ssh-keygen -R $1
ssh root@$1 curl -o /root/.ssh/authorized_keys "https://github.com/JJGadgets.keys"
scp -rO ./install.sh root@$1:/tmp/install.sh
scp -rO ./cloud-config.yaml root@$1:/root/config.yaml
ssh root@$1 chmod +x /tmp/install.sh
ssh root@$1 /tmp/install.sh
