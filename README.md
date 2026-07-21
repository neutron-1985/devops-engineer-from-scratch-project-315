[![Actions Status](https://github.com/neutron-1985/devops-engineer-from-scratch-project-315/actions/workflows/hexlet-check.yml/badge.svg)](https://github.com/neutron-1985/devops-engineer-from-scratch-project-315/actions)
[![Deploy](https://github.com/neutron-1985/devops-engineer-from-scratch-project-315/actions/workflows/deploy.yml/badge.svg)](https://github.com/neutron-1985/devops-engineer-from-scratch-project-315/actions/workflows/deploy.yml)

# Project infrastructure

Ansible configuration for provisioning and deploying the `project-devops-deploy` application. The application image is built and published by the separate application repository; this repository deploys a selected image tag.

## Deployed service

The production service is available at the following addresses:

- Application: `https://n-devops.jumpingcrab.com/`
- Swagger UI: `https://n-devops.jumpingcrab.com/swagger-ui/index.html`

Nginx redirects public HTTP traffic on port `80` to HTTPS on port `443`.
Application port `8080` and
Actuator port `9090` are bound to `127.0.0.1` and are not exposed publicly.

## Requirements

- Ansible
- SSH access to the application and service hosts
- Ansible Vault password

Install roles and collections:

```bash
make ansible-install
```

Create the local Vault password file:

```bash
install -m 600 /dev/null .vault-password
$EDITOR .vault-password
```

## Deployment

Use an immutable image tag published by the application repository:

```bash
make ansible-check APP_IMAGE_TAG=sha-0123456789abcdef
make deploy APP_IMAGE_TAG=sha-0123456789abcdef
```

The image repository defaults to `docker.io/neutron1985/project-devops-deploy` and can be overridden when necessary:

```bash
make deploy IMAGE_REPOSITORY=docker.io/example/project-devops-deploy APP_IMAGE_TAG=sha-0123456789abcdef
```

Deployment commands target `production` by default; override `ANSIBLE_LIMIT` for another environment. `make provision` is an alias for `make step-01` and targets the `application` hosts.

## Manual GitHub Actions deployment

Open **Actions → Deploy → Run workflow**, enter the Docker tag, and start the workflow. Prefer the immutable `sha-<commit>` tag produced by the application repository instead of `latest`.

Configure these secrets in the `production` GitHub Environment or in repository Actions secrets:

- `ANSIBLE_VAULT_PASSWORD`
- `DEPLOY_SSH_KEY`

The workflow validates the tag, runs Ansible in check mode, and then performs the deployment. The `production` environment can additionally require reviewer approval.

## Infrastructure commands

| Command | Purpose |
|---|---|
| `make step-01` | Prepare application hosts: Docker, Compose, deployment user, and UFW |
| `make step-02 APP_IMAGE_TAG=...` | Deploy the standalone application with local storage |
| `make step-03 APP_IMAGE_TAG=...` | Prepare database hosts, provision PostgreSQL, run migrations, and switch production to the production profile |
| `make step-04 APP_IMAGE_TAG=...` | Prepare object-storage hosts, provision the selected S3-compatible service, and switch production files to S3 |
| `make step-05 APP_IMAGE_TAG=...` | Put the production application behind the HTTP Nginx reverse proxy |
| `make step-06 APP_IMAGE_TAG=...` | Enable Let's Encrypt HTTPS on production |
| `make nginx-install` | Install Nginx, apply the minimal bootstrap configuration, and start it |
| `make nginx-proxy` | Add the application reverse proxy without caching |
| `make nginx-cache` | Add cache zones and the `/assets/` and `/uploads/` locations |
| `make nginx-cache-check` | Verify HTTP cache behavior after the three learning stages |
| `make all APP_IMAGE_TAG=...` | Install dependencies, render configuration, and run all six steps |
| `make provision` | Alias for `make step-01` |
| `make database` | Alias for `make step-03` |
| `make storage` | Alias for `make step-04` |
| `make smoke` | Verify object storage and Nginx caches through the deployed application |
| `make cache-check` | Verify `MISS`/`HIT` behavior for frontend assets and uploads |
| `make tls-check` | Verify HTTPS, TLS policy, certificate renewal, and the Certbot timer |
| `make reset` | Remove project resources, data, deploy users, Docker, and UFW from infrastructure hosts |
| `make ansible-check APP_IMAGE_TAG=...` | Check a deployment without applying it |
| `make deploy APP_IMAGE_TAG=...` | Deploy the selected application image |
| `make vault-rekey` | Rotate the Ansible Vault password |

## Incremental project steps

The root `playbook.yml` is intentionally short and imports the six files under
`playbooks/steps/` in project order. To verify the project incrementally, run
`make reset` and then execute `make step-01`, inspect the result, execute
`make step-02`, and continue in order. Each target runs only its own step and
therefore assumes that all preceding steps completed successfully.

The environment changes from a standalone development deployment to production
in **step 3**. That step provisions PostgreSQL, runs migrations, and starts the
application with the `prod` Spring profile while files still use persistent
local storage. Step 4 moves files to S3, step 5 changes the public entry point
to HTTP Nginx, and step 6 enables HTTPS.

Each step includes its own readiness checks: host assertions, container health,
database availability and migrations, S3 upload/download verification, Nginx
configuration validation, or TLS smoke tests as appropriate. These checks
cannot guarantee that an external provider is available, but they fail the step
before it can be considered complete.

The step targets are intended for learning and incremental verification. Use
`make all` for a complete rebuild or `make deploy` for routine application
updates in an already provisioned production environment.
The existing `ANSIBLE_LIMIT`, `IMAGE_REPOSITORY`, and
`APP_IMAGE_TAG` overrides continue to apply.

Deployment targets, SSH host keys, users, database credentials, and object
storage credentials are grouped by service under the `project_vault`
namespace in encrypted `group_vars/all/vault.yml`. Open project settings are
grouped in `group_vars/all/vars.yml`.
The same namespace provides the SSH connection port used by both Ansible and
the `firewall_policy` role.
The render playbook exposes the inventory section under the compatibility
`vault_inventory` variable used by playbooks and roles.

Each service step prepares its own target hosts before starting containers.
Step 1 provisions application hosts, step 3 provisions database hosts, and
step 4 provisions object-storage hosts. PostgreSQL and the selected object
storage provider manage only their own restricted service firewall rules. The
provisioning user performs host
administration, while the deployment user is created on each host during its
provisioning step, belongs to the `docker` group, and manages containers
without privilege escalation.

`make reset` is destructive. It removes the application, PostgreSQL, MinIO, and
RustFS
containers and persistent data, project firewall rules and facts, deployment
users, Docker, Nginx, and UFW. It deliberately preserves the provisioning user so the
hosts remain reachable. Limit cleanup to selected hosts with `RESET_LIMIT`, for
example `make reset RESET_LIMIT=production`. The role requires the explicit
`infrastructure_reset_confirm=true` confirmation supplied by the Make target.

## Nginx reverse proxy and caching

The Nginx implementation is split into four one-way learning stages:

1. `nginx_install` installs the package without allowing its post-install
   script to start the service. It completely replaces the distribution
   `nginx.conf` with only the mandatory `events`/`http` wrappers and a
   text-response `server`, validates it, and only then starts Nginx. It has no
   includes, project proxy, or cache variables.
2. `nginx_reverse_proxy` keeps the same minimal `events`/`http` structure,
   replaces the text response with `proxy_pass`, and adds no cache or
   object-storage configuration.
3. `nginx_cache` keeps that reverse proxy, then adds cache zones and the
   `/assets/` and `/uploads/` locations. Each role renders a complete readable
   snapshot of its stage; no earlier role contains extension points for a
   later one.
4. `nginx_cache_smoke_test` verifies real `MISS`/`HIT` behavior and cleans
   up its temporary upload.

After completing project steps 1–4, run `make nginx-install`,
`make nginx-proxy`, `make nginx-cache`, and `make nginx-cache-check` in
order to inspect each intermediate HTTP state. The proxy command also applies
the existing firewall policy at the playbook level; firewall management is not
part of the reverse-proxy role. Use `make cache-check` for the final HTTPS
environment. The regular `make step-05` target executes all four stages in the required
order. Dependencies point forward only: a later role validates artifacts
created by an earlier role, while earlier roles contain no knowledge of later
ones.

The `nginx_reverse_proxy` role configures `n-devops.jumpingcrab.com` as the
virtual host and proxies dynamic requests to the application on
`127.0.0.1:8080`. The application and Actuator ports remain available only on
the server loopback interface.

The base reverse-proxy role remains HTTP-only. Step 6 upgrades the same virtual
host through the independent `tls_nginx` role. It publishes the HTTP-01
challenge, invokes the `tls_certificate` role, replaces the HTTP virtual host
with an HTTP-to-HTTPS redirect and TLS virtual host.

`tls_certificate` uses `geerlingguy.certbot` for package installation and
certificate issuance. The external role's cron renewal is disabled in favor
of the distribution-provided `certbot.timer`. A deploy hook validates the
Nginx configuration and reloads Nginx after successful renewal. Run the full
verification with:

```bash
make tls-check
```

TLS is enabled by running `make step-06`; leaving the environment at step 5
keeps the original HTTP reverse proxy. There is no separate boolean switch.
The `nginx_reverse_proxy` role requires no TLS-specific code or variables.

Frontend files under `/assets/` are cached by Nginx for one year. Uploaded bulletin images are
served from the selected object storage service through `/uploads/` and cached
for 30 days. Cached responses include `X-Cache-Status`, which reports values
such as `MISS` and `HIT`.

Steps 5 and 6 run an end-to-end cache smoke test after deploying the
application. The test requests a real frontend asset twice and requires the
second response to be a cache `HIT`. It also uploads a temporary object through
the application, requires `MISS` followed by `HIT` from `/uploads/`, verifies
the response content, and removes the object from storage. Run this check
independently with:

```bash
make cache-check
```

The shared `firewall_policy` role exposes `8080` after step 1, replaces it with public
HTTP port `80` after Nginx is ready in step 5, and adds `443` only after HTTPS
is configured in step 6. Nginx and TLS roles do not manage UFW themselves.

## S3-compatible object storage

Object storage responsibilities are split between four roles:

- `object_storage_host` prepares the host firewall;
- `object_storage_deploy` prepares and runs MinIO or RustFS;
- `object_storage_migration` copies and verifies data between S3 endpoints;
- `object_storage_provider_switch` coordinates application downtime and cutover.

Select the implementation with `object_storage_provider` in
`group_vars/all/object_storage.yml`; the project currently selects RustFS.
Switching providers performs an online initial copy and a final copy while the
application is stopped. Provider data directories remain available for rollback.
`make reset` removes resources belonging to both providers.

The selected RustFS image is pinned to `1.0.0-beta.3`; treat this branch as an
experimental deployment option until RustFS publishes a stable release suitable
for this project.

`make storage` provisions the `bulletin-images` bucket in the selected service
and configures two separate identities:

- `bulletins-storage-admin` is the administrative identity used only by Ansible
  for provisioning and smoke-test cleanup.
- `bulletins-app` is passed to the application and has only
  `s3:GetObject` and `s3:PutObject` on
  `arn:aws:s3:::bulletin-images/bulletins/*`.

Objects under the `bulletins/` prefix are publicly readable because they are
public bulletin images served through Nginx. Listing the bucket and writing or
deleting objects still require credentials.

The administrative secret and application secret key are stored in the encrypted
`group_vars/all/vault.yml`. Do not add either credential
directly to GitHub secrets. GitHub Actions needs only
`ANSIBLE_VAULT_PASSWORD` to decrypt them during deployment.

Provision or update the bucket, user, and policy:

```bash
make storage
```

The production inventory supplies the S3 endpoint, bucket, and region.
The deployment role passes those values and the restricted application
credentials as `STORAGE_S3_*` environment variables.

## Object storage verification

Every production `make deploy` runs an S3 smoke test after the application
becomes ready. Run the same check without redeploying:

```bash
make smoke
```
The check uploads a text object through `POST /api/files/upload`, requests a
fresh link from `GET /api/files/view`, downloads the object through the
public Nginx URL from the Ansible controller, and compares its contents. It also
verifies that the application credentials cannot delete the object. Finally,
Ansible removes the test object using the administrative identity.
