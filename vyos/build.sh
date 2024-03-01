#!/usr/bin/env bash

if [[ -z "${VYOS_VERSION}" ]]; then
    # renovate: datasource=github-tags depName=vyos/vyos-1x
    export VYOS_VERSION="1.3.6"
fi
VYOS_URL="${VYOS_URL:=https://github.com/vyos/vyos-build}"
VYOS_ARCH="${VYOS_ARCH:=amd64}"
VYOS_BUILD_TIME="${VYOS_BUILD_TIME:="$(date +%Y%m%d%H%M)"}"

# renovate: datasource=github-releases depName=getsops/sops
SOPS_VERSION="v3.8.1"
SOPS_VERSION="${SOPS_VERSION#*v}"

# renovate: datasource=github-releases depName=p3lim/vyaml
VYAML_VERSION="0.2.4"

# renovate: datasource=github-releases depName=atuinsh/atuin
ATUIN_VERSION="v18.0.1"
ATUIN_VERSION="${ATUIN_VERSION#*v}"

# renovate: datasource=github-releases depName=go-task/task
TASK_VERSION="v3.35.0"
TASK_VERSION="${TASK_VERSION#*v}"

# renovate: datasource=github-releases depName=duosecurity/duo_unix
DUO_VERSION="duo_unix-2.0.3"
DUO_VERSION="${DUO_VERSION#*duo_unix-}"

pwd
git clone --depth=1 --branch "${VYOS_VERSION}" --single-branch "${VYOS_URL}" ./vyos-build
cd ./vyos-build
mkdir -p ./build ./packages
pwd
ls -AlhR . # debug

cd ./packages
curl -vLO "https://github.com/getsops/sops/releases/download/v${SOPS_VERSION}/sops_${SOPS_VERSION}_${VYOS_ARCH}.deb"
curl -vLO "https://github.com/p3lim/vyaml/releases/download/${VYAML_VERSION}/vyaml-${VYOS_ARCH}.deb"
curl -vLO "https://github.com/atuinsh/atuin/releases/download/v${ATUIN_VERSION}/atuin_${ATUIN_VERSION}_${VYOS_ARCH}.deb"
curl -vLO "https://github.com/go-task/task/releases/download/v${TASK_VERSION}/task_linux_${VYOS_ARCH}.deb"
curl -vO "https://downloads.1password.com/linux/debian/${VYOS_ARCH}/stable/1password-latest.deb"
curl -vO "https://pkg.duosecurity.com/Debian/dists/bullseye/main/binary-${VYOS_ARCH}/duo-unix_${DUO_VERSION}-0_amd64.deb" # TODO: better solution to this than assuming the -0 version suffix
cd ../

# script assumes running as sudo/root
make clean
ls -AlhR ./packages # debug
./build-vyos-image iso \
    --architecture "${VYOS_ARCH}" \
    --build-by "${VYOS_BUILDER:=custom}" \
    --build-type "${VYOS_BUILD_TYPE:=release}" \
    --build-comment "Biohazardous VyOS" \
    --version "${VYOS_VERSION}+${VYOS_BUILDER:=custom}-${VYOS_BUILD_TIME}" \
    --custom-package "iptables" \
    --custom-package "jo" \
    --custom-package "moreutils" \
    --custom-package "tree" \
    --custom-package "tmux" \
    --custom-package "fish" \
    --custom-package "iotop" \
    --custom-package "btop" \
    --custom-package "neovim" \
    # VyOS doesn't build kernel with zram :(
    # --custom-package "zram-tools" \
    # --custom-package "systemd-zram-generator" # jank city
