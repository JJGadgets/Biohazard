#!/usr/bin/env bash

# renovate: datasource=github-tags depName=vyos/vyos-1x
VYOS_VERSION="${VYOS_VERSION:="1.3.6"}"
VYOS_URL="${VYOS_URL:=https://github.com/vyos/vyos-build}"
VYOS_ARCH="${VYOS_ARCH:=amd64}"
VYOS_BUILD_TIME="${VYOS_BUILD_TIME:="$(date +%Y%m%d%H%M)"}"

# renovate: datasource=github-releases depName=getsops/sops
SOPS_VERSION="v3.8.1"
SOPS_VERSION="${SOPS_VERSION#*v}"
#VYAML_VERSION="v

# renovate: datasource=github-releases depName=atuinsh/atuin
ATUIN_VERSION="v18.0.1"
ATUIN_VERSION="${ATUIN_VERSION#*v}"

# renovate: datasource=github-releases depName=go-task/task
TASK_VERSION="v3.35.0"
TASK_VERSION="${TASK_VERSION#*v}"

pwd
git clone --depth=1 --branch "${VYOS_VERSION}" --single-branch "${VYOS_URL}" ./vyos-build
cd ./vyos-build
mkdir -p ./build ./packages
pwd
ls -AlhR . # debug

curl -vL -o ./packages/sops.deb "https://github.com/getsops/sops/releases/download/v${SOPS_VERSION}/sops_${SOPS_VERSION}_${VYOS_ARCH}.deb"
curl -vL -o ./packages/atuin.deb "https://github.com/atuinsh/atuin/releases/download/v${ATUIN_VERSION}/atuin_${ATUIN_VERSION}_${VYOS_ARCH}.deb"
curl -vL -o ./packages/task.deb "https://github.com/atuinsh/atuin/releases/download/v${TASK_VERSION}/task_linux_${VYOS_ARCH}.deb"
curl -v -o ./packages/1password.deb "https://downloads.1password.com/linux/debian/${VYOS_ARCH}/stable/1password-latest.deb"
curl -v -o ./packages/duo-unix.deb "https://pkg.duosecurity.com/Debian/dists/bullseye/main/binary-amd64/duo-unix_2.0.3-0_amd64.deb"

# script assumes running as sudo/root
make clean
./build-vyos-image iso \
    --architecture "${VYOS_ARCH}" \
    --build-by "${VYOS_BUILDER:=root}" \
    --build-type "${VYOS_BUILD_TYPE:=release}" \
    --build-comment "Biohazardous VyOS" \
    --version "${VYOS_VERSION}-${VYOS_BUILD_TIME}" \
    --custom-package "iptables" \
    --custom-package "jo" \
    --custom-package "moreutils" \
    --custom-package "tree" \
    --custom-package "tmux" \
    --custom-package "fish" \
    --custom-package "iotop" \
    --custom-package "btop" \
    --custom-package "neovim" \
    --custom-package "zram-tools" \
    --custom-package "systemd-zram-generator" # jank city
