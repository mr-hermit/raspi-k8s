# GitHub Actions Runner Controller (ARC) Addon

Deploys [ARC](https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners-with-actions-runner-controller/quickstart-for-actions-runner-controller) to the cluster. ARC runs self-hosted GitHub Actions runners as ephemeral pods, scaling them up on demand and terminating them after each job.

## Prerequisites

- Kubernetes cluster up (`k8s/k8s-setup.yaml` completed)
- Helm installed on the control plane node
- A GitHub PAT with the required scope (see below)

## Configuration

Add these vars to `inventory.ini`:

```ini
# ── GitHub Actions Runner Controller ─────────────────────────────────────────
arc_github_config_url=https://github.com/<org-or-org/repo>
arc_github_token=ghp_...          # encrypt with ansible-vault
arc_runner_scale_set_name=arc-runner-set
arc_runner_min_runners=0
arc_runner_max_runners=5
```

**PAT scopes required:**
- Organization-level runners: `admin:org`
- Repository-level runners: `repo`

## Usage

```sh
# Full install (controller + runner scale set)
ansible-playbook -i ../../inventory.ini arc-setup.yaml

# Controller only
ansible-playbook -i ../../inventory.ini arc-setup.yaml --tags arc_controller

# Runner scale set only (re-apply after config change)
ansible-playbook -i ../../inventory.ini arc-setup.yaml --tags arc_runners
```

## How it works

ARC consists of two Helm releases installed into separate namespaces:

| Component | Namespace | Purpose |
|---|---|---|
| `arc` (controller) | `arc-systems` | Watches `AutoscalingRunnerSet` CRDs; drives KEDA scaling |
| `arc-runner-set` (scale set) | `arc-runners` | Registers with GitHub; spawns runner pods per job |

Runners are ephemeral — each pod handles one job then terminates. At zero load, `minRunners=0` means no pods run idle.

## Using in workflows

Reference the runner by its scale set name in your workflow:

```yaml
jobs:
  build:
    runs-on: arc-runner-set
```

## GitHub App authentication (alternative to PAT)

For production use, a GitHub App is more secure than a PAT. To switch:

1. Create a GitHub App with `Actions: Read & Write` and `Administration: Read & Write` permissions
2. Install it on your org/repo and note the App ID and Installation ID
3. Generate a private key and store it in a Kubernetes secret
4. Replace `githubConfigSecret` in the Helm values with the App credentials format described in the [ARC docs](https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners-with-actions-runner-controller/authenticating-to-the-github-api)

## References

- [ARC Quickstart](https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners-with-actions-runner-controller/quickstart-for-actions-runner-controller)
- [ARC GitHub](https://github.com/actions/actions-runner-controller)
- [Helm chart values](https://github.com/actions/actions-runner-controller/tree/master/charts/gha-runner-scale-set)
