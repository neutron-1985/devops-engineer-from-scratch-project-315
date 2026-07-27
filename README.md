[![Actions Status](https://github.com/neutron-1985/devops-engineer-from-scratch-project-315/actions/workflows/hexlet-check.yml/badge.svg)](https://github.com/neutron-1985/devops-engineer-from-scratch-project-315/actions)
[![Release](https://github.com/neutron-1985/devops-engineer-from-scratch-project-315/actions/workflows/release.yml/badge.svg)](https://github.com/neutron-1985/devops-engineer-from-scratch-project-315/actions/workflows/release.yml)

# Project infrastructure

Ansible configuration for provisioning and deploying
`project-devops-deploy`. The application image is built in a separate
repository; this repository records and deploys an immutable image tag.

Production:

- Application: `https://n-devops.jumpingcrab.com/`
- Swagger UI: `https://n-devops.jumpingcrab.com/swagger-ui/index.html`

## Environments

The project manages `dev`, `stage`, and `prod` on shared physical hosts. Each
environment has isolated application, PostgreSQL, and S3-compatible storage
containers and data.

| Environment | Domain | Application | PostgreSQL | S3 API |
|---|---|---:|---:|---:|
| dev | `dev.n-devops.jumpingcrab.com` | `127.0.0.1:8082` | `5434` | `9004` |
| stage | `stage.n-devops.jumpingcrab.com` | `127.0.0.1:8081` | `5433` | `9002` |
| prod | `n-devops.jumpingcrab.com` | `127.0.0.1:8080` | `5432` | `9000` |

Desired state is stored in:

```text
environments/<name>/inventory/group_vars/all/vars.yml
```

This file includes the environment identity, ports, domain, and immutable
Docker tag:

```yaml
app_image_tag: sha-0123456789abcdef
```

Shared settings are stored under `environments/_shared/inventory/`. The
encrypted `inventory.vault.yml` contains host topology, SSH settings, and
environment secrets. Generated `hosts.yml` and `known_hosts` files are ignored
by Git and created before Ansible operations.

## Setup

Requirements:

- Ansible
- SSH access to the managed hosts
- Ansible Vault password

Install Ansible dependencies and configure the local Vault password:

```bash
make ansible-install
install -m 600 /dev/null .vault-password
$EDITOR .vault-password
```

`dev` is the default environment. Select another one with
`ENVIRONMENT=stage` or `ENVIRONMENT=prod`.

## Common commands

| Command | Purpose |
|---|---|
| `make infra-preview ENVIRONMENT=stage` | Preview changes on prepared infrastructure |
| `make infra-apply ENVIRONMENT=stage` | Reconcile infrastructure for one environment |
| `make infra-apply-all` | Reconcile all environments |
| `make ansible-check ENVIRONMENT=stage` | Check a deployment without applying it |
| `make deploy ENVIRONMENT=stage` | Deploy the tag recorded in inventory |
| `make rollback ENVIRONMENT=stage` | Swap the active and previous application runtimes |
| `make smoke` | Run service smoke tests |
| `make cache-check` | Verify Nginx asset and upload caching |
| `make tls-check` | Verify HTTPS and certificate renewal |
| `make reset ENVIRONMENT=stage` | Remove resources belonging to one environment |
| `make reset` | Remove all project infrastructure and data |

`make reset` is destructive. The environment-specific form leaves shared
services and other environments intact.

## Application deployment

Update `app_image_tag` in the target environment inventory, then run:

```bash
make ansible-check ENVIRONMENT=stage
make deploy ENVIRONMENT=stage
```

Automated releases always use the committed inventory tag. For temporary local
testing it can be overridden:

```bash
make deploy ENVIRONMENT=stage APP_IMAGE_TAG=sha-0123456789abcdef
```

The default image repository is
`docker.io/neutron1985/project-devops-deploy`; override it with
`IMAGE_REPOSITORY` when necessary. Routine deployments reject `latest` and
tags that do not identify a commit.

## GitHub Actions release

The `Release` workflow runs after a push to `main` that changes one or more
environment `vars.yml` files.

1. `dorny/paths-filter` identifies the changed environments.
2. A matrix creates an independent job for each environment.
3. Each job reconciles infrastructure, checks the deployment, and deploys the
   tag from inventory.
4. A production job waits for approval through the `prod` GitHub Environment.

Configure these secrets in the `dev`, `stage`, and `prod` GitHub Environments:

- `ANSIBLE_VAULT_PASSWORD`
- `DEPLOY_SSH_KEY`

The workflow can also be started manually for one selected environment. It
still reads the image tag from that environment inventory.

Promote a verified tag through separate reviewed changes:

```text
dev vars.yml → verify dev → stage vars.yml → verify stage → prod vars.yml
```

If several inventories change in one push, their matrix jobs are independent;
stage does not wait for dev. Separate changes preserve the promotion sequence
in Git history.

## Provisioning stages

The root `playbook.yml` imports five incremental project steps:

1. `make step-01` — application with local storage.
2. `make step-02` — PostgreSQL, migrations, and the production Spring profile.
3. `make step-03` — S3-compatible object storage.
4. `make step-04` — Nginx reverse proxy, uploads, caching, and firewall policy.
5. `make step-05` — one SAN certificate and HTTPS for all environments.

Use the steps for incremental verification or `make all` for a complete build.
Each step assumes the preceding steps have completed.

Project roles are grouped by domain under `roles/`: `common`, `application`,
`database`, `object_storage`, `nginx`, and `tls`. Playbooks reference nested
roles by paths such as `database/service`. The `playbooks/steps/roles` symlink
exposes the same role root to CI runners.

## Verification and recovery

Run a step twice after a clean reset to check idempotence. The second run should
report `changed=0`, `failed=0`, and `unreachable=0`.

Deployments keep one stopped previous application runtime. If a candidate fails
its health checks, Ansible restores that runtime automatically. A manual
rollback swaps the active and previous runtimes:

```bash
make rollback ENVIRONMENT=stage
```

Rollback does not reverse database migrations or external data changes, so
production migrations must remain compatible with the previous image.

Nginx redirects HTTP to HTTPS and exposes application traffic only through
ports `80` and `443`. Application and management ports remain bound to
loopback. Uploaded files are served through `/uploads/`; frontend assets and
uploads are cached and verified by `make cache-check`.

The selected S3-compatible provider is configured with
`object_storage_provider` in shared vars. Credentials remain in Ansible Vault;
GitHub Actions only needs the Vault password required to decrypt them.
