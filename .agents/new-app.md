# Adding a New App

0. **Research first.** Before scaffolding, read and analyze the app's official documentation for its "container" or "Docker" deployment and configuration methods — look for supported environment variables, config file paths and formats, volumes/mounts, exposed ports, and required runtime privileges. Also search [kubesearch.dev](https://kubesearch.dev) for the app to find how other Kubernetes homelab users have deployed and configured it, and reference their patterns where appropriate. Prefer configuration via environment variables over config files where the app supports both.

1. `task k8s:newapp APP=<name> IMAGENAME=<img> IMAGETAG=<tag>` — copies `kube/templates/test/` to `kube/deploy/apps/<name>/`, substituting `APPNAME`/`IMAGENAME`/`IMAGETAG`.
2. Configure the app via env vars or config file. For config files, place them in `./kube/deploy/apps/<app>/app/config/` and add a `configMapGenerator` with `disableNameSuffixHash: true` in `./kube/deploy/apps/<app>/app/config/kustomization.yaml`.
3. Add secrets via `envFrom` (referencing a Secret named `<app>-secrets`) and edit `es.yaml` accordingly (ExternalSecret pulling from 1Password key `<app> - ${CLUSTER_NAME}`).
4. Edit the generated files: set pod labels for netpol/ingress/auth opt-in, runtimeClassName, securityContext UID/GID, persistence (create `<app>-pvc` Kustomization for VolSync-backed PVC or inline PVC for misc), route (internal/external Gateway refs), service (LB if non-HTTP ports), optionally DB Kustomization.
5. Add the app path to `kube/clusters/biohazard/flux/kustomization.yaml`.
6. Create the 1Password entries for the app's secrets and vars, matching the keys referenced in `es.yaml` and `vars.yaml`.
7. Commit and push — Flux reconciles within 5m; Renovate will track the image/chart versions.
