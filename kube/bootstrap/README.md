# Bootstrap Kubernetes cluster

1. Install Flux in hostNetwork mode binded to localhost
2. Load `${CLUSTER_NAME}-vars` (including 1Password and Hubble Vars) and 1Password Connect secrets (Connect credentials and ESO client token) from 1Password
3. Load root ks (flux-repo.yaml) which installs Cilium