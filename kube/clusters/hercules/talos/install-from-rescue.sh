#!/bin/sh
SSH_KNOWN_HOSTS=/dev/null ssh root@${IP} /bin/bash -c "\
  curl -vLO 'https://github.com/siderolabs/talos/releases/download/v${TALOS_VERSION:=1.6.7}/metal-amd64.raw.xz';
  fdisk -l ${DISK:=/dev/sdb};
  sgdisk --zap-all ${DISK};
  sgdisk --zap-all ${DISK};
  wipefs --all --backup ${DISK};
  wipefs --all --backup ${DISK};
  fdisk -l ${DISK:=/dev/sdb};

  xz -vv -d -c ./metal-amd64.raw.xz | dd of=${DISK} status=progress;
  sync;
  echo 3 > /proc/sys/vm/drop_caches;
"
