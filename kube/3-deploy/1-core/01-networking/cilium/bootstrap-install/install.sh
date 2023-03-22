#!/bin/bash
## one of these days, I'll learn and switch to Taskfiles
set -euo pipefail
GITROOT=$(git rev-parse --show-toplevel)
source <(sops -d $1 | yq .data | sed -re 's/^/export /g' | sed -e 's/: /="/g' | sed -re 's/$/"/g')
kustomize build $2 --enable-helm | envsubst | kubectl apply -f -
