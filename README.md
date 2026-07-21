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

Deployment commands target `production` by default; override `ANSIBLE_LIMIT` for another environment. Use `make step-01` to prepare the `application` hosts and deploy the standalone application.
The semantic aliases follow the same sequence: `application`, `database`,
`storage`, `nginx`, and `https` map to
`step-01` through `step-05`.

## Manual GitHub Actions deployment

Open **Actions → Deploy → Run workflow**, enter the immutable `sha-<commit>` tag produced by the application repository, and start the workflow. Routine `make deploy`, `make ansible-check`, and GitHub Actions deployments reject `latest` and tags that do not identify a commit. Incremental `step-01` through `step-05` runs may use the default `latest` tag for learning and verification.

Configure these secrets in the `production` GitHub Environment or in repository Actions secrets:

- `ANSIBLE_VAULT_PASSWORD`
- `DEPLOY_SSH_KEY`

The workflow validates the tag, runs Ansible in check mode, and then performs the deployment. The `production` environment can additionally require reviewer approval.

## Infrastructure commands

| Command | Purpose |
|---|---|
| `make step-01 APP_IMAGE_TAG=...` | Prepare application hosts and deploy the standalone application with local storage |
| `make step-02 APP_IMAGE_TAG=...` | Prepare database hosts, provision PostgreSQL, run migrations, and switch production to the production profile |
| `make step-03 APP_IMAGE_TAG=...` | Prepare object-storage hosts, provision the selected S3-compatible service, and switch production files to S3 |
| `make step-04 APP_IMAGE_TAG=...` | Put the production application behind the HTTP Nginx reverse proxy |
| `make step-05` | Enable Let's Encrypt HTTPS on production |
| `make cert` | Publish HTTP-01 and issue the Let's Encrypt certificate |
| `make cert-renewal` | Configure the Certbot timer and Nginx reload hook |
| `make cert-https` | Enable secure HTTPS and redirect HTTP |
| `make nginx-install` | Install Nginx, apply the minimal bootstrap configuration, and start it |
| `make nginx-proxy` | Add the application reverse proxy without caching |
| `make nginx-cache` | Add cache zones and the `/assets/` and `/uploads/` locations |
| `make nginx-cache-check` | Verify HTTP cache behavior after the three learning stages |
| `make all APP_IMAGE_TAG=...` | Install dependencies, render configuration, and run all five steps |
| `make smoke` | Verify the application database, object storage, and Nginx caches |
| `make cache-check` | Verify `MISS`/`HIT` behavior for frontend assets and uploads |
| `make tls-check` | Verify HTTPS, TLS policy, certificate renewal, and the Certbot timer |
| `make reset` | Remove project resources, data, deploy users, Docker, and UFW from infrastructure hosts |
| `make ansible-check APP_IMAGE_TAG=...` | Check a deployment without applying it |
| `make deploy APP_IMAGE_TAG=...` | Deploy the selected application image |
| `make rollback` | Swap the active application with the complete previous container runtime |
| `make vault-rekey` | Rotate the Ansible Vault password |

## Incremental project steps

The root `playbook.yml` is intentionally short and imports the five files under
`playbooks/steps/` in project order. To verify the project incrementally, run
`make reset` and then execute `make step-01`, inspect the result, execute
`make step-02`, and continue in order. Each target runs only its own step and
therefore assumes that all preceding steps completed successfully.

The environment changes from a standalone development deployment to production
in **step 2**. That step provisions PostgreSQL, runs migrations, and starts the
application with the `prod` Spring profile while files still use persistent
local storage. Step 3 moves files to S3, step 4 changes the public entry point
to HTTP Nginx, and step 5 enables HTTPS.

The database stage follows the same role-oriented structure as the Nginx and
TLS stages. `database/host` prepares host dependencies and persistent storage,
`database/firewall` restricts PostgreSQL access, and `database/service` manages
the container and credentials. `database/service_smoke_test` verifies a marker
survives a PostgreSQL container restart. `database/migration` applies the
Flyway schema before `application/service`, while
`database/application_smoke_test` checks
the migrated relation and application readiness. Each role exposes its normal
workflow through `tasks/main.yml`; the step playbook only orders the roles.

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

Check idempotence directly after `make reset` by running step 1 twice:

```bash
make step-01 APP_IMAGE_TAG=sha-0123456789abcdef
make step-01 APP_IMAGE_TAG=sha-0123456789abcdef
```

The second run should report `changed=0`, `failed=0`, and `unreachable=0` for
every host. Do not run this check on an environment that has
already advanced beyond step 1 because the step intentionally restores the
standalone application and its firewall policy.

The application writes structured JSON to standard output. Its container uses
Docker's `json-file` logging driver with five rotated 10 MB files, preserving
logs across ordinary container restarts while bounding local disk usage.

### Application runtime rollback

A deployment first compares the active container with the desired image and
configuration. An unchanged deployment does not rotate containers. Only a real
release change stops the active container and preserves its complete runtime as
`project-devops-deploy-previous` before starting the candidate.

On success, exactly one stopped previous runtime remains available. If the
candidate fails its readiness or public health check, Ansible removes it,
restores the previous container name and starts that exact runtime configuration.

Run a manual one-release rollback with:

```bash
make rollback
```

The command swaps active and previous containers, verifies the restored runtime,
and returns the original active container if verification fails. A successful
manual rollback keeps the replaced release in the previous slot, so the swap is
reversible until the next deployment.

Container rollback does not reverse database migrations or external data
changes. Production migrations must remain compatible with the previous image.

Deployment targets, SSH host keys, users, database credentials, and object
storage credentials are grouped by service under the `project_vault`
namespace in encrypted `group_vars/all/vault.yml`. Open project settings are
grouped in `group_vars/all/vars.yml`.
The same namespace provides the SSH connection port used by both Ansible and
the `common/firewall_policy` role.
The render playbook exposes the inventory section under the compatibility
`vault_inventory` variable used by playbooks and roles.

Project roles are grouped by domain under `roles/`: `common`, `application`,
`database`, `object_storage`, `nginx`, `tls`, and `vendor`. Playbooks use path-qualified
role names such as `database/service` and `tls/certificate`; the directory
provides the namespace, so role directories do not repeat their domain prefix.
The names of role variables remain fully prefixed because Ansible variables
share a play-level namespace. Galaxy roles are installed under `roles/vendor`
and keep their upstream names inside that directory.

Each service step prepares its own target hosts before starting containers.
Step 1 provisions application hosts, step 2 provisions database hosts, and
step 3 provisions object-storage hosts. PostgreSQL and the selected object
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

1. `nginx/install` installs the package without allowing its post-install
   script to start the service. It completely replaces the distribution
   `nginx.conf` with only the mandatory `events`/`http` wrappers and a
   text-response `server`, validates it, and only then starts Nginx. It has no
   includes, project proxy, or cache variables.
2. `nginx/reverse_proxy` keeps the same minimal `events`/`http` structure,
   replaces the text response with `proxy_pass`, and adds no cache or
   object-storage configuration.
3. `nginx/cache` keeps that reverse proxy, then adds cache zones and the
   `/assets/` and `/uploads/` locations. Each role renders a complete readable
   snapshot of its stage; no earlier role contains extension points for a
   later one.
4. `nginx/cache_smoke_test` verifies real `MISS`/`HIT` behavior and cleans
   up its temporary upload.

After completing project steps 1–3, run `make nginx-install`,
`make nginx-proxy`, `make nginx-cache`, and `make nginx-cache-check` in
order to inspect each intermediate HTTP state. The proxy command also applies
the existing firewall policy at the playbook level; firewall management is not
part of the reverse-proxy role. Use `make cache-check` for the final HTTPS
environment. The regular `make step-04` target executes all four stages in the required
order. Dependencies point forward only: a later role validates artifacts
created by an earlier role, while earlier roles contain no knowledge of later
ones.

The `nginx/reverse_proxy` role configures `n-devops.jumpingcrab.com` as the
virtual host and proxies dynamic requests to the application on
`127.0.0.1:8080`. The application and Actuator ports remain available only on
the server loopback interface.

The base reverse-proxy role remains HTTP-only. Step 5 splits HTTPS provisioning
between three roles. `tls/certificate` publishes the HTTP-01 challenge and
uses `geerlingguy.certbot` for package installation and certificate issuance.
`tls/certificate_renewal` enables the distribution-provided `certbot.timer`;
its deploy hook validates the Nginx configuration and reloads Nginx after a
successful renewal. The external Certbot role's cron renewal is disabled.
`tls/nginx` then replaces the HTTP virtual host with an HTTP-to-HTTPS redirect
and a TLS virtual host.

Run these stages independently and in order:

```bash
make cert
make cert-renewal
make cert-https
```

Only TLS 1.2 and TLS 1.3 are enabled. TLS 1.2 and TLS 1.3 use explicit modern
cipher allowlists; legacy protocols, CBC suites, static RSA key exchange, and
TLS session tickets are disabled. Run the full verification with:

```bash
make tls-check
```

The aggregate `make step-05` target runs all three stages. TLS becomes public
after `make cert-https`; leaving the environment after the certificate stage
keeps the original HTTP reverse proxy. There is no separate boolean switch.
The `nginx/reverse_proxy` role requires no TLS-specific code or variables.

Frontend files under `/assets/` are cached by Nginx for one year. Uploaded bulletin images are
served from the selected object storage service through `/uploads/` and cached
for 30 days. Cached responses include `X-Cache-Status`, which reports values
such as `MISS` and `HIT`.

Steps 4 and 5 run an end-to-end cache smoke test after deploying the
application. The test requests a real frontend asset twice and requires the
second response to be a cache `HIT`. It also uploads a temporary object through
the application, requires `MISS` followed by `HIT` from `/uploads/`, verifies
the response content, and removes the object from storage. Run this check
independently with:

```bash
make cache-check
```

The shared `common/firewall_policy` role exposes `8080` after step 1, replaces it with public
HTTP port `80` after Nginx is ready in step 4, and adds `443` only after HTTPS
is configured in step 5. Nginx and TLS roles do not manage UFW themselves.

## S3-compatible object storage

Object storage responsibilities are split between four roles:

- `object_storage/host` prepares the host firewall;
- `object_storage/deploy` prepares and runs MinIO or RustFS;
- `object_storage/migration` copies and verifies data between S3 endpoints;
- `object_storage/provider_switch` coordinates application downtime and cutover.

Select the implementation with `object_storage_provider` in
`group_vars/all/object_storage.yml`; the project currently selects RustFS.
Switching providers performs an online initial copy and a final copy while the
application is stopped. Provider data directories remain available for rollback.
`make reset` removes resources belonging to both providers.

The selected RustFS image is pinned to `1.0.0-beta.3`; treat this branch as an
experimental deployment option until RustFS publishes a stable release suitable
for this project.

`make step-03` provisions the `bulletin-images` bucket in the selected service
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
make step-03
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
