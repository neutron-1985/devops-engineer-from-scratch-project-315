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
containers and data. A shared host-networked Nginx container publishes
independently managed environment routes, while one-shot Certbot containers
issue and renew certificates.

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
| `make all ENVIRONMENT=stage` | Provision dependencies and deploy one environment completely |
| `make infra-preview ENVIRONMENT=stage` | Preview changes on prepared infrastructure |
| `make infra-apply ENVIRONMENT=stage` | Reconcile infrastructure for one environment |
| `make ansible-check ENVIRONMENT=stage` | Check a deployment without applying it |
| `make deploy ENVIRONMENT=stage` | Deploy the tag recorded in inventory |
| `make rollback ENVIRONMENT=stage` | Swap the active and previous application runtimes |
| `make smoke` | Run service smoke tests |
| `make cache-check` | Verify Nginx asset and upload caching |
| `make tls-check` | Verify HTTPS, TLS policy, and the renewal timer |
| `make reset ENVIRONMENT=stage RESET_MODE=soft` | Stop stage containers and preserve persistent data and logs |
| `make reset RESET_MODE=soft` | Stop all project environments and preserve persistent data and logs |
| `make reset ENVIRONMENT=stage` | Hard-reset resources belonging to stage |
| `make reset` | Hard-reset all environments and shared resources owned by this project |
| `make vault-rekey` | Change the password protecting the shared Ansible Vault |

`make all` processes only the selected environment; without `ENVIRONMENT`, it
deploys `dev`. Reset uses hard mode by default and accepts only `soft` or `hard`
as `RESET_MODE`.

Soft reset stops only the selected project containers and preserves persistent
data, mounted logs, active service container logs, Nginx routes, certificates,
firewall rules, and local facts. A subsequent `make all` starts or recreates
the runtime on the preserved state.

Hard environment reset removes the selected project containers, Nginx route,
data, logs, caches, firewall rules, and local facts. The unqualified hard reset
applies this to `dev`, `stage`, and `prod`, then removes the shared Nginx
routes, caches, gateway container, gateway logs, and Certbot renewal timer.
Issued TLS certificates are preserved to avoid unnecessary ACME reissuance
and rate limits.

Docker, containerd, UFW, deployment users, unrelated containers, images,
volumes, and observability data are always preserved.

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

After a pull request reaches `main`, the `Release` workflow runs when an
environment tag or deployment configuration changes. Deployment configuration
includes shared inventory, roles, playbooks, Ansible dependencies, the
Makefile, and the release workflows themselves.

The changed inventories are evaluated in fixed priority order:

```text
dev → stage → prod
```

The first changed environment becomes the release source. Its committed
`app_image_tag` is used for that environment and every higher environment in
the same promotion run:

| Changed inventory | Release source | Deployment chain |
|---|---|---|
| `dev` (with or without other changes) | tag from `dev` | `dev → stage → prod` |
| `stage`, but not `dev` | tag from `stage` | `stage → prod` |
| only `prod` | tag from `prod` | `prod` |

For example, if both `dev` and `stage` files changed, the workflow deliberately
uses the tag from `dev` for the complete chain. The selected tag is passed as
an explicit Ansible override; the per-environment tags remain independent in
their own `vars.yml` files.

A configuration-only change reconciles `dev`, `stage`, and `prod` in order,
using each environment's own committed image tag. For a mixed change, lower
environments keep their own tags while the release source and every higher
environment use the selected promotion tag. For example, a role change combined
with a stage tag update reconciles dev with its current tag and promotes the
stage tag through stage and prod.

Each deployment checks out the same triggering commit. A later push cannot
replace the selected tag in a running or approval-waiting workflow.

Configure required reviewers on the `stage` and `prod` GitHub Environments.
This creates approval gates before the workflow continues to those higher
environments. The source environment starts without an additional workflow
input.

Configure these secrets in the `dev`, `stage`, and `prod` GitHub Environments:

- `ANSIBLE_VAULT_PASSWORD`
- `DEPLOY_SSH_KEY`

Release runs are serialized and are not cancelled while deployment or approval
is in progress.

## Provisioning stages

The root `playbook.yml` implements a complete deployment through five
orchestration layers:

1. `infrastructure.yml` — prepare common host prerequisites and the containerized Nginx gateway.
2. `provision.yml` — start and initialize PostgreSQL and object storage.
3. `runtime.yml` — apply database migrations and deploy the application.
4. `gateway.yml` — publish the selected environment route through Nginx and TLS.
5. `verify.yml` — run database, storage, cache, and TLS smoke tests.

The numbered Make targets provide the alternative incremental project flow:

1. `make step-01` — prepare the application server infrastructure without deploying the application.
2. `make step-02` — provision PostgreSQL and verify its persistence.
3. `make step-03` — provision S3-compatible storage, migrate the database,
   and deploy the application with the production profile and S3 backend.
4. `make step-04` — publish the application through Nginx and verify storage
   and cache behavior.
5. `make step-05` — one SAN certificate and HTTPS for all environments.

`make all ENVIRONMENT=<name>` for a complete environment deployment.
Per-environment commands update only their selected route and preserve routes
already published for other environments.

Use the steps for incremental verification or `make all` for a complete build.
Each step assumes the preceding steps have completed.

The application starts only after PostgreSQL and object storage are ready. It
is bound to loopback and uses its final `prod`/S3 configuration from the first
start, so provisioning never exposes a temporary local-data runtime.

Project roles are grouped by domain under `roles/`: `common`, `application`,
`database`, `object_storage`, `nginx`, and `tls`. Playbooks reference nested
roles by paths such as `database/service`. The `playbooks/roles` symlink
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

The main `/etc/nginx/nginx.conf` is stable and includes managed virtual-host
configuration from `/etc/nginx/conf.d`. Both paths are stored on the host and
mounted read-only into the host-networked Nginx container. Cache, certificate,
ACME webroot, and log directories are mounted separately. Every generated
configuration is validated inside the container with `nginx -t` before reload.

Long-running application, PostgreSQL, object-storage, and Nginx containers
have Docker healthchecks. Ansible also waits for service readiness before
starting dependent deployment stages.

## Logs

Service logs are persisted on the managed hosts. The environment suffix is
`-dev` or `-stage` and is empty for `prod`.

| Service | Host path |
|---|---|
| Application | `/var/log/project-devops-deploy<suffix>/application.log` |
| PostgreSQL | `/var/log/project-devops-postgresql<suffix>/postgresql-<weekday>.log` |
| MinIO | `/var/log/project-devops-minio<suffix>/minio.log` |
| RustFS | `/var/log/project-devops-rustfs<suffix>/` |
| Nginx access | `/var/log/project-devops-nginx/access.log` |
| Nginx errors | `/var/log/project-devops-nginx/error.log` |
| Certbot | `/var/log/project-devops-certbot/` |

Application and MinIO stdout and stderr are redirected to their mounted log
files. Nginx writes access and error logs into its mounted log directory. Host
`logrotate` rotates these files at 10 MiB, keeps five compressed archives, and
uses `copytruncate` so containers do not need to restart. PostgreSQL rotates its
mounted log daily, and Certbot keeps bounded log backups in its mounted directory.
Docker `json-file` output for long-running containers is additionally bounded to
five 10 MiB files.

The selected S3-compatible provider is configured with
`object_storage_provider` in shared vars. Credentials remain in Ansible Vault;
GitHub Actions only needs the Vault password required to decrypt them.
