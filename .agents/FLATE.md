# flate — Offline Flux Rendering & Diffing

## What It Is

[flate](https://github.com/home-operations/flate) is a single static Go binary that renders and diffs Flux GitOps repos fully offline — no cluster, no `kubectl`, no `helm`/`kustomize`/`flux` CLIs, and no shellouts. It is a native Go rewrite of [flux-local](https://github.com/allenporter/flux-local) with Helm, kustomize, go-git, and oras-go linked as libraries.

## Why It Matters

- **One binary** — no kind cluster, no CLI dependencies, no shellouts
- **Fast** — changed-only mode reconciles only the subtree a PR touches
- **CI-native** — ships with a GitHub Action; runs in seconds, not minutes
- **Embeddable** — `pkg/orchestrator` is a library entry point

## Usage

Every reconcile-running command takes `--path <dir>` (default `.`). Use `--path-orig <dir>` for changed-only diff mode.

### Common Commands

```bash
# List Kustomizations
flate get ks --path ./kube -o table

# Build a specific Kustomization or HelmRelease to YAML
flate build ks 0-biohazard-config --path ./kube
flate build hr some-app --path ./kube

# Diff Kustomizations against a baseline (changed-only mode)
flate diff ks --path ./kube --path-orig ../baseline/kube

# Diff all resources
flate diff all --path ./kube --path-orig ../baseline/kube

# Diff image changes in JSON
flate diff images --path ./kube --path-orig ../baseline/kube -o json

# Pytest-style pass/fail
flate test all --path ./kube
```

### Output Formats

| Command | Targets | Output Formats |
|---------|---------|---------------|
| `get` | `ks`, `hr`, `images`, `all` | `-o table` / `yaml` / `json` / `name` |
| `build` | `ks`, `hr`, `all` | YAML or JSON manifests (`-o yaml` / `json`) |
| `diff` | `ks`, `hr`, `images`, `all` | `human` (default), `github`, `brief`, `gitlab`, `gitea`, `diff`, `html` |
| `test` | `ks`, `hr`, `all` | `PASS` / `FAIL` / `SKIPPED` |

The `html` diff output is a self-contained page with syntax highlighting, filterable navigation, and side-by-side views — useful for browser review (`flate diff all -o html > diff.html`).

### Cache Management

```bash
# Prune stale cache entries
flate cache gc

# Delete the persistent helm template-output cache
flate cache clear-render
```

Cache directory defaults to `$XDG_CACHE_HOME/flate`. Use `--cache-dir` to override.

## Changed-Only Mode

Pass `--path-orig <dir>` to enable change-aware reconcile. flate diffs the two paths, walks ownership backwards via Flux KS `spec.path`, and reconciles only the touched subtree.

```bash
git worktree add ../baseline main
flate diff ks --path ./kube --path-orig ../baseline/kube
```

**In the keep-set:** direct file edits, chart sources, KS `sourceRef`, HR `valuesFrom`, kustomize components (touching a shared component re-renders every consumer).
**Out:** `dependsOn` (reconcile-ordering only, not content — skipped resources still get marked `Ready` so downstream waits unblock) and meta-Kustomizations that don't claim deeper files.

`--path` can point at a narrow Flux entry like `./kube/clusters/biohazard/flux`; flate iteratively follows each loaded KS's `spec.path` to discover the rest of the tree.

**`--base` shortcut:** Instead of `--path-orig`, use `--base <rev>` (e.g., `main`, `HEAD~1`) to auto-checkout a git rev to a temp dir and diff against it.

## Important Behaviors

### Secrets (SOPS)

- SOPS-encrypted values are wiped to `..PLACEHOLDER_<key>..` — flate cannot decrypt offline, and raw ciphertext poisons rendering
- Cleartext Secret values are NOT wiped (flate renders your own repo, not a live cluster)
- Downstream `postBuild.substituteFrom` lookups resolve SOPS values to the placeholder rather than failing

### `--allow-missing-secrets`

Off by default. When set, any source whose auth `secretRef` is missing or PLACEHOLDER-wiped marks `Ready / "skipped: …"` instead of `Failed`. Consumers propagate the skip so `flate test` reports `SKIPPED` rather than cascading `FAILED`.

**Auto-skip** is on by default with no flag: when a referenced Secret is missing but an in-repo `ExternalSecret` or `SealedSecret` declares it as a target, flate skips it automatically. A missing Secret with **no** declared producer still fails loud — a real typo is never silently swallowed.

### Other Behaviors

- **`spec.suspend`** — honored; suspended resources mark `Ready / "suspended"` with no rendered output
- **`spec.dependsOn[].readyExpr` (CEL)** — evaluated against `self` and `dep` projections
- **Substitution opt-out** — `kustomize.toolkit.fluxcd.io/substitute: disabled` label/annotation is honored per-resource
- **`--strip-attr <key>`** (repeatable) — drops annotation/label keys before comparison; defaults cover chart-bump noise (`helm.sh/chart`, `checksum/config`, `checksum/secret`, `app.kubernetes.io/version`, `chart`)
- **`--skip-secrets` / `--skip-crds`** — both default to `true`; output-stream filters that strip Secrets and CRDs from manifest output
- **`--skip-kinds <kind>`** (repeatable) — drops additional resource kinds from output
- **`-l/--selector key=value`** — label filtering on `get ks` and `get hr`
- **`--stream`** — emit YAML as each resource finishes reconciling (completion order)

### Signature Verification

flate does **not** verify signatures. `spec.verify` on `OCIRepository` (cosign) and `GitRepository` (PGP) is ignored — artifacts are pulled and rendered unconditionally. Signature enforcement belongs in-cluster.

## Source Kind Support

| Kind | Status | Auth |
|------|--------|------|
| `GitRepository` | Full | HTTPS: username+password or bearerToken. SSH: identity (+ optional password, known_hosts) |
| `OCIRepository` | Full | `.dockerconfigjson`. Falls back to `--registry-config`, then `~/.docker/config.json` |
| `HelmRepository` | Full | HTTP basic: username+password; OCI routes through OCI puller |
| `HelmChart` | Full | Inline (`HR.spec.chart`) and standalone CRD |
| `Bucket` | `generic` only | `accesskey` + `secretkey` |
| `ExternalArtifact` | `file://` only | `status.artifact.url` must be a local path |

## Architecture

```
discovery → Store ⇄ events ⇄ controllers (source · kustomization · helmrelease)
```

Pipeline: discovery → loader pre-pass → file walk → `spec.path` + ResourceSet fixed-point expansion → namespace inheritance → parent index → `dependsOn` cycle preflight → change-filter → controllers fire → render-time keep-set extension → orphan demotion → output.

The Store is the single source of truth. Every stored manifest is immutable; mutation routes through `Store.Mutate[T]`. Helm chart loads coalesce through a per-path keylock.

## Limits

- **No SOPS decryption** — pre-decrypt if you need real values in the diff
- **No signature verification** — `spec.verify` is ignored
- **No cloud workload identity** — `spec.serviceAccountName` is a no-op; use static creds
- **No `healthChecks`** — flate tracks resource readiness, not rendered object status conditions
- **Dynamic ResourceSetInputProviders** contribute zero inputs unless you pre-bake `status.exportedInputs`
- **Diff output is not a source patch** — diffs are of rendered manifests, not repo files

## flate on This Repo — Current State

### What Works

Running `--allow-missing-secrets` is required because our repo uses `postBuild.substituteFrom` against `biohazard-vars` and `biohazard-secrets` Secrets (synced from 1Password). With that flag:

- `get ks` discovers ~200 Kustomizations across core and apps
- `get hr` discovers 2+ HelmReleases (limited by missing `app-template` OCI sources)
- `diff ks` with `--path-orig` works well — changed-only mode diff only renders the touched subtree (~5-12s vs 60s+ for full reconcile)
- `diff images` and `build` work for individual resources once sources are reachable

### Known Blocking Issue

`0-biohazard-config` (the root Kustomization at `./kube/clusters/biohazard/flux`) fails during kustomize build with:

```
add operation does not apply: doc is missing path: "/spec/dependsOn/-": missing value
```

**Root cause:** The global patches in `flux-repo.yaml` use JSON Patch `op: add` with path `/spec/dependsOn/-` to inject `dependsOn` entries on all matching Kustomizations. The `notin (false, no-deps)` labelSelector matches many KS CRs that don't have `spec.dependsOn` defined yet. The JSON Patch spec requires the target path to exist; `add` to an array with `/-` fails when the array is absent.

This is stricter than kustomize-native `patches` (which create missing paths) but flate uses a stricter JSON Patch engine. In-cluster Flux reconciles Kustomizations individually, so the patch is applied only to the target Kustomization itself, not globally against all discovered Kustomizations.

**Fix:** Add `dependsOn: []` to every Flux Kustomization CR so the array exists for the `add` operation. The blank array is a no-op in-cluster (Flux ignores empty `dependsOn`) and prevents the JSON Patch failure during offline rendering.
