#!/bin/sh
curl -v -o ./ostree/tailscale.repo "https://pkgs.tailscale.com/stable/fedora/tailscale.repo" | wget -O ./ostree/tailscale.repo "https://pkgs.tailscale.com/stable/fedora/tailscale.repo"