# CI (GitHub Actions)

- **Flux Diff** — runs `flux-local` diff on PRs against `main`, posts results as PR comments. All PRs to `main` trigger this.
- **Renovate** — hourly, opens PRs for dependency updates. Most automerge. Uses semantic commits with scopes like `oci/<image>`, `helm/<chart>`, `mise/<tool>`, `gha/<action>`.
- **Flux Localhost Build** — rebuilds `kube/bootstrap/flux/flux-install-localhost-manifests.yaml` on Flux version bump, opens a PR.
- **OSTree Build** — weekly (Fri), builds and pushes OSTree images to GHCR.
