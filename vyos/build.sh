#!/usr/bin/env bash

if [[ -z "${VYOS_VERSION}" ]]; then
    # renovate: datasource=github-tags depName=vyos/vyos-1x
    export VYOS_VERSION="1.3.6"
fi
VYOS_VERSION_TYPE="${VYOS_VERSION_TYPE:=lts}"
VYOS_URL="${VYOS_URL:=https://github.com/vyos/vyos-build}"
VYOS_ARCH="${VYOS_ARCH:=amd64}"
VYOS_BUILD_TIME="${VYOS_BUILD_TIME:="$(date +%Y%m%d%H%M)"}"
DEBIAN_CODENAME=${DEBIAN_CODENAME:=bookworm} # only used by custom packages' APT repos like Duo Unix

# renovate: datasource=github-releases depName=getsops/sops
SOPS_VERSION="v3.8.1"
SOPS_VERSION="${SOPS_VERSION#*v}"

# renovate: datasource=github-releases depName=p3lim/vyaml
VYAML_VERSION="0.2.5"

# renovate: datasource=github-releases depName=atuinsh/atuin
ATUIN_VERSION="v18.0.1"
ATUIN_VERSION="${ATUIN_VERSION#*v}"

# renovate: datasource=github-releases depName=go-task/task
TASK_VERSION="v3.35.0"
TASK_VERSION="${TASK_VERSION#*v}"

# renovate: datasource=github-releases depName=duosecurity/duo_unix
DUO_VERSION="duo_unix-2.0.3"
DUO_VERSION="${DUO_VERSION#*duo_unix-}"

# renovate: datasource=github-releases depName=tailscale/tailscale
TAILSCALE_VERSION="v1.60.1"
TAILSCALE_VERSION="${TAILSCALE_VERSION#*v}"

echo "STAGE 1: Clone vyos-build Git repository, with ${VYOS_VERSION} tag"
echo "=========="
git clone --depth=1 --branch "${VYOS_VERSION}" "${VYOS_URL}" ./vyos-build
cd ./vyos-build
VYOSDIR=$(pwd)
git switch -c "${VYOS_VERSION}" # T6064
mkdir -p ${VYOSDIR}/build ${VYOSDIR}/packages
ls -AlhR ${VYOSDIR} # debug

echo "STAGE 2: Download packages outside of Debian & VyOS repos"
echo "=========="
cd ${VYOSDIR}/packages
curl -vLO "https://github.com/getsops/sops/releases/download/v${SOPS_VERSION}/sops_${SOPS_VERSION}_${VYOS_ARCH}.deb"
curl -vL -o ./vyaml_${VYAML_VERSION}_${VYOS_ARCH}.deb "https://github.com/p3lim/vyaml/releases/download/${VYAML_VERSION}/vyaml-${VYOS_ARCH}.deb"
curl -vLO "https://github.com/atuinsh/atuin/releases/download/v${ATUIN_VERSION}/atuin_${ATUIN_VERSION}_${VYOS_ARCH}.deb"
curl -vLO "https://github.com/go-task/task/releases/download/v${TASK_VERSION}/task_linux_${VYOS_ARCH}.deb"
curl -vO "https://pkgs.tailscale.com/stable/debian/pool/tailscale_${TAILSCALE_VERSION}_${VYOS_ARCH}.deb"
curl -vO "https://pkg.duosecurity.com/Debian/dists/${DEBIAN_CODENAME}/main/binary-${VYOS_ARCH}/duo-unix_${DUO_VERSION}-0_amd64.deb" # TODO: better solution to this than assuming the -0 version suffix
curl -vO "https://downloads.1password.com/linux/debian/${VYOS_ARCH}/stable/1password-cli-${VYOS_ARCH}-latest.deb" # always use latest 1Password CLI version for security reasons
OP_VERSION=$(dpkg-deb --field ./1password-cli-${VYOS_ARCH}-latest.deb version)
mv ./1password-cli-${VYOS_ARCH}-latest.deb ./1password-cli_${OP_VERSION}_${VYOS_ARCH}.deb
cd ${VYOSDIR}

# script assumes running as sudo/root
echo "STAGE 3: Build VyOS ISO"
echo "=========="
make clean
ls -AlhR ${VYOSDIR}/packages # debug
./build-vyos-image iso \
    --architecture "${VYOS_ARCH}" \
    --build-by "${VYOS_BUILDER:=custom}" \
    --build-type "${VYOS_BUILD_TYPE:=release}" \
    --build-comment "Biohazardous VyOS" \
    --version "${VYOS_VERSION}-${VYOS_VERSION_TYPE}-${VYOS_BUILDER:=custom}-${VYOS_BUILD_TIME}" \
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

ls -AlhR .

echo "STAGE 3: Post-Build"
echo "=========="
ls -AlhR ${VYOSDIR}/build
cp -r ${VYOSDIR}/build/*.iso ${VYOSDIR}/build/${VYOS_VERSION_TYPE}-${VYOS_ARCH}.iso