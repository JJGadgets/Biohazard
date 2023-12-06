#!/bin/bash
#set -euo pipefail

# install SSH authorized_keys for passwordless
curl -o ~/.ssh/authorized_keys "https://github.com/JJGadgets.keys"

# save on RAM and disk space
systemctl disable --now glances atop atopacct systemd-journald.service systemd-journald.socket systemd-journald-audit.socket systemd-journald-dev-log.socket
apt purge -y nmap vim man-db glances atop
apt purge -y linux-headers-6.1.0-10-amd64 linux-image-6.1.0-10-amd64 || true
rm -rf /usr/share/doc
rm -rf /usr/share/vim
rm -rf /usr/share/nmap
rm -rf /usr/lib/modules/6.1.0-10-amd64 || true # unused kernel modules
apt autoremove -y

# install Docker apt repo (pulled from Docker docs)
apt update
apt install -y ca-certificates curl gnupg
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
  "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null
apt update -y
# install Docker
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# save on more disk space
rm -rf /var/cache/apt/archives/*

# mount zram on /var/lib/docker to have more available space for Kairos image (last checked on 2023-10-14: 2.3GB)
systemctl disable --now docker.socket docker.service && systemctl stop docker.socket docker.service
modprobe zram
zramctl -f -s 3G -a zstd
mkfs.ext4 /dev/zram0
mount -t ext4 -o rw /dev/zram0 /var/lib/docker
systemctl enable --now docker.socket docker.service

# pull Docker image
docker pull --platform amd64 quay.io/kairos/kairos-debian:v2.4.1-k3sv1.27.3-k3s1
# flush in-memory disk cache
sync; echo 3 > /proc/sys/vm/drop_caches
# run Kairos takeover
docker run --privileged -v $HOME:/data -v /dev:/dev quay.io/kairos/kairos-debian:v2.4.1-k3sv1.27.3-k3s1 kairos-agent manual-install --device /dev/sdb --source oci:quay.io/kairos/kairos-debian:v2.4.1-k3sv1.27.3-k3s1 /data/config.yaml
