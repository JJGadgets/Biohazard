# Self-hosted PR reviewer on Biohazard

This app runs [misospace/pr-reviewer-action](https://github.com/misospace/pr-reviewer-action)
**operator mode**, with its own GitHub App, Flux HelmRelease, PostgreSQL,
and ephemeral Kubernetes Jobs. It does **not** use GitHub ARC/Actions runners,
accept public GitHub webhooks, or publish any `llmkube-router` endpoint.

## Runtime and trust boundary

1. The controller polls **only** `JJGadgets/Biohazard` via its GitHub App every
   five minutes; `allowlist` + `discovered-default: adopt` permits only
   that repository and cannot be widened by PR-authored config.
2. An in-cluster controller schedules one hardened worker Job per review.
   The worker has **no Kubernetes API token**, uses the upstream restricted
   PodSpec, and shares CephFS RWX run/workspace claims with the controller.
   The controller alone has namespace-scoped Job and ephemeral-Secret RBAC.
3. Each worker reaches `http://llmkube.llmkube.svc.cluster.local/v1` via
   service DNS and port 8080, permitted by the matching Cilium egress and
   router ingress policies. There is no external Gateway, ingress, Service,
   or NodePort for the reviewer or llmkube-router.
4. GitHub API/clone egress uses a short FQDN allowlist over TLS. The
   controller additionally reaches the Kubernetes API and `pg-home`
   through the existing opt-in cluster policies. DNS follows the cluster's
   default Cilium DNS policy. No broad Internet egress label is assigned.

**Security limitation:** The upstream executor does not expose a
`runtimeClassName` setting for worker Jobs. The controller uses gVisor;
worker Jobs use upstream nonroot/seccomp/readonly-rootfs restrictions and
PSS `restricted` in this dedicated namespace. The pinned images are
**linux/amd64-only**; don't schedule this workload on ARM nodes.

## Versions and provenance

Both images and the Helm chart are pinned to upstream source commit
`1799b9f750a28764b0afc441a7e840acbfe50137`, from the successful
[upstream image build](https://github.com/misospace/pr-reviewer-action/actions/runs/44340992609)
on 2026-11-18. The controller and worker digests are recorded in
`app/hr.yaml`. The chart is loaded from the pinned GitRepository at
`deploy/charts/pr-reviewer` (chart 0.1.0, application 3.9.0).

## Prerequisites before Flux reconciliation

1. Create a GitHub App and install it on **JJGadgets/Biohazard**. Grant
   Metadata (read), Contents (read), Pull requests (read/write), Issues
   (read/write for sticky comments), and Checks/Commit statuses permissions
   only if the chosen publication mode uses them. Keep webhooks disabled;
   **reconciliation is outbound polling**, so no public callback URL is
   necessary. Obtain the numeric App ID and *installation* ID and a
   private PEM key. Restrict the installation to the single target repo.
   Validate the minimal permissions needed for the chosen review/publish
   configuration before enabling the App.
2. Provision a dedicated `pr-reviewer` database and non-superuser role on
   existing `pg-home`. The GitOps overlay adds that role and database to
   `kube/deploy/core/db/pg/clusters/home/ks.yaml`. Obtain the generated
   credential from the `pg` namespace and prepare a PostgreSQL DSN with
   TLS certificate verification to `pg-home`. **Do not put it in Git.**
3. Create a 1Password item named `pr-reviewer - biohazard` with the
   following exact field names (supply values, not quoted templates):

   | Field | Purpose |
   | --- | --- |
   | `GITHUB_APP_ID` | Numeric GitHub App ID |
   | `GITHUB_INSTALLATION_ID` | Numeric GitHub App installation ID |
   | `GITHUB_APP_PRIVATE_KEY` | Multiline GitHub App PEM |
   | `POSTGRES_DSN` | Dedicated PostgreSQL DSN (TLS verified) |
   | `MODEL_API_KEY` | Non-empty private model credential; required by reviewer runtime |

   External Secrets creates `pr-reviewer-secrets` (PEM, DSN and model key)
   and a separate `pr-reviewer-ids` Secret. **Only IDs are exposed to
   Flux postBuild substitution**; no credentials appear in HelmRelease
   objects or Git history.
4. Ensure `ghcr.io/misospace/pr-reviewer-{controller,worker}` images are
   pullable by cluster nodes (upstream notes GHCR packages may be private;
   attach a read-only registry pull Secret if necessary). The Helm chart
   requires source-controller to resolve its pinned bjw-s `common` chart
   dependency 5.3.0. The run/workspace claims use CephFS `file`
   `ReadWriteMany`; state uses `block` `ReadWriteOnce`.

The reviewer refuses to start if required credentials, configuration, or DB
access are unavailable. Deployment is incomplete until the prerequisites
are fulfilled; no credential or numeric GitHub App ID is fabricated here.

## Network / operations

- `app/netpol.yaml`: separate default-deny Cilium policies for controller
  and worker pods; neither permits inbound application traffic.
- `kube/deploy/apps/llmkube/app/netpol.yaml`: narrow router ingress
  exception for **only** labeled worker Jobs in `pr-reviewer` namespace.
- `app/configmap.yaml`: deliberately empty evidence providers config,
  staged into the shared workspace claim by a startup initContainer. No
  repository-controlled commands or external evidence tools are enabled.
- The in-cluster controller admin/dashboard listener is disabled, and
  GitHub webhooks are disabled. Logs and Job state remain accessible through
  normal Kubernetes operations (RBAC-gated).
- When rotating any backing Secret, restart the controller: its credential
  environment is a startup snapshot.
- The upstream chart's own `networkPolicy` is intentionally disabled;
  generic port-443 rules would undermine the scoped cluster policies and
  would omit the HTTP model endpoint.
- Start with a test PR in `JJGadgets/Biohazard`; verify controller
  readiness, GitHub reconciliation, ephemeral Jobs, pull-request publication,
  no access to unapproved cluster services, and no network ingress.
- Fork PRs are governed by upstream fork privilege separation; verify
  the desired fork behavior before granting broader permissions.

Reference: [upstream self-hosted deployment runbook](https://github.com/misospace/pr-reviewer-action/blob/1799b9f750a28764b0afc441a7e840acbfe50137/docs/self-hosted-deployment.md).
