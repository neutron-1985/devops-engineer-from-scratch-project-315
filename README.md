[![Actions Status](https://github.com/neutron-1985/devops-engineer-from-scratch-project-315/actions/workflows/hexlet-check.yml/badge.svg)](https://github.com/neutron-1985/devops-engineer-from-scratch-project-315/actions)
[![Deploy](https://github.com/neutron-1985/devops-engineer-from-scratch-project-315/actions/workflows/deploy.yml/badge.svg)](https://github.com/neutron-1985/devops-engineer-from-scratch-project-315/actions/workflows/deploy.yml)

# Project infrastructure

Ansible configuration for provisioning and deploying the `project-devops-deploy` application. The application image is built and published by the separate application repository; this repository deploys a selected image tag.

## Deployed service

The production service is available at the following addresses:

- Application: `https://n-devops.jumpingcrab.com/`
- Swagger UI: `https://n-devops.jumpingcrab.com/swagger-ui/index.html`

## Runtime environments

Shared settings live next to one encrypted inventory that contains the physical
host topology and named `dev`, `stage`, and `prod` secret sections. Ansible
uses it as the source of truth and renders an ignored host map for every environment before each operation. Application secrets are not written to those generated files. SSH users, the port, the deployment public key, and trusted host keys live once in its `ssh_inventory` section. Each runtime environment contains identity values and a generated inventory entry point:

```text
environments/
├── _shared/
│   ├── inventory/
│   │   ├── group_vars/all/vars.yml
│   │   └── inventory.vault.yml       # encrypted, tracked
│   └── runtime/
│       └── known_hosts               # generated, ignored
├── dev/
│   └── inventory/
│       ├── group_vars/all/vars.yml
│       └── hosts.yml                 # generated, ignored
├── stage/
│   └── inventory/
│       ├── group_vars/all/vars.yml
│       └── hosts.yml                 # generated, ignored
└── prod/
    └── inventory/
        ├── group_vars/all/vars.yml
        └── hosts.yml                 # generated, ignored
```

Each environment `vars.yml` contains exactly seven values: `environment_name`,
the application and management ports, the PostgreSQL port, the object-storage
API and console ports, and `nginx_server_name`. Container, bucket, policy,
directory, and cache names are
derived by the shared vars. The gateway discovers the same identity files and
combines them with the shared host topology when building public routes.

| Environment | Domain | Application | Management | PostgreSQL | S3 API | S3 console |
|---|---|---:|---:|---:|---:|---:|
| prod | `n-devops.jumpingcrab.com` | `127.0.0.1:8080` | `127.0.0.1:9090` | `5432` | `9000` | `127.0.0.1:9001` |
| stage | `stage.n-devops.jumpingcrab.com` | `127.0.0.1:8081` | `127.0.0.1:9091` | `5433` | `9002` | `127.0.0.1:9003` |
| dev | `dev.n-devops.jumpingcrab.com` | `127.0.0.1:8082` | `127.0.0.1:9092` | `5434` | `9004` | `127.0.0.1:9005` |

Every environment uses the production Spring profile and has its own application,
PostgreSQL, and S3-compatible storage containers, persistent directories, ports,
and credentials. All six stateful service instances remain on the same physical
data host but do not share runtimes or data directories.

Select an inventory with `ENVIRONMENT`; `dev` is the default:

```bash
make infra-preview ENVIRONMENT=stage
make infra-apply ENVIRONMENT=stage
make infra-apply-all
make deploy ENVIRONMENT=stage APP_IMAGE_TAG=sha-0123456789abcdef
make deploy ENVIRONMENT=dev APP_IMAGE_TAG=sha-0123456789abcdef
make rollback ENVIRONMENT=stage
```

`infra-preview` runs shared-host, selected-environment, gateway, TLS, and
firewall reconciliation in Ansible check mode. `infra-apply` applies the same
sequence for one environment, while `infra-apply-all` reconciles shared services
and all three environment resource sets.
Environment provisioning creates its database, object-storage service, bucket,
credentials, and application directories; migrations and application containers remain part of
`make deploy`. The gateway derives each route from the environment identity and
shared host topology, then publishes all domains through one SAN certificate.

The `Deploy` workflow targets one selected environment. The `Promote` workflow
first reconciles shared infrastructure and resources for `dev`, `stage`, and
`prod`, then keeps one immutable image tag and infrastructure commit while
advancing through those environments. Make rejects environment names that do not have an
`environments/<name>/inventory/group_vars/all/vars.yml` file. Configure matching
GitHub Environments with the Vault password and deployment SSH key before using
either workflow. The workflow writes `.vault-password`; Make runs `prepare-inventory` to render the ignored environment `hosts.yml` files and then `prepare-ssh` to render the ignored `_shared/runtime/known_hosts` file.

Nginx redirects public HTTP traffic on port `80` to HTTPS on port `443`.
All application and Actuator ports are bound to `127.0.0.1` and are not exposed
publicly.

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
make ansible-check ENVIRONMENT=stage APP_IMAGE_TAG=sha-0123456789abcdef
make deploy ENVIRONMENT=stage APP_IMAGE_TAG=sha-0123456789abcdef
```

The image repository defaults to `docker.io/neutron1985/project-devops-deploy` and can be overridden when necessary:

```bash
make deploy ENVIRONMENT=stage IMAGE_REPOSITORY=docker.io/example/project-devops-deploy APP_IMAGE_TAG=sha-0123456789abcdef
```

Deployment commands target `dev` by default; set `ENVIRONMENT=stage` or
`ENVIRONMENT=prod` explicitly when promoting changes. Use `make step-01` to
prepare the `application` hosts and deploy the standalone application.

## GitHub Actions deployment and promotion

For a one-off deployment, open **Actions → Deploy → Run workflow**, select the
target environment, and enter the immutable `sha-<commit>` image tag produced by
the application repository. The workflow validates the tag, runs Ansible in
check mode, deploys the image, and completes the environment smoke tests.

For a staged release, open **Actions → Promote → Run workflow** and enter the
image tag once. One workflow run then executes:

```text
dev → stage approval → stage → prod approval → prod
```

The stage job starts only after the dev deployment and smoke tests succeed. The
prod job starts only after stage succeeds. Configure **Required reviewers** for
the `stage` and `prod` GitHub Environments; the waiting job is resumed
with **Review deployments → Approve and deploy**. If
the workflow initiator is also the reviewer, leave **Prevent self-review**
disabled. GitHub allows an environment
approval to remain pending for up to 30 days, so a one-week soak period is supported.

Configure these secrets in the `dev`, `stage`, and `prod` GitHub Environments or
as repository Actions secrets:

- `ANSIBLE_VAULT_PASSWORD`
- `DEPLOY_SSH_KEY`

Routine `make deploy`, `make ansible-check`, and GitHub Actions deployments
reject `latest` and tags that do not identify a commit. Incremental `step-01`
through `step-05` runs may use the default `latest` tag for learning and
verification.

The standalone `Deploy` workflow remains available for recovery and targeted
environment operations without advancing the whole promotion chain.

Use **Actions → Infrastructure** to preview or reconcile infrastructure.
The `preview` operation runs Ansible check mode without applying changes. The
`apply` operation waits on the `infrastructure` GitHub Environment before
changing the shared server. Configure
Required reviewers on that environment because host packages, the physical data
host, object storage, Nginx, TLS, and UFW affect multiple runtime environments.
Repository-level `ANSIBLE_VAULT_PASSWORD` and `DEPLOY_SSH_KEY` secrets are
available to preview; the `infrastructure` Environment provides them to the
apply job. The SSH key must authorize both the provisioning
user and the deployment user declared in `ssh_inventory`.

## Infrastructure commands

| Command | Purpose |
|---|---|
| `make step-01 APP_IMAGE_TAG=...` | Prepare application hosts and deploy the standalone application with local storage |
| `make step-02 APP_IMAGE_TAG=...` | Prepare database hosts, provision PostgreSQL, run migrations, and switch production to the production profile |
| `make step-03 APP_IMAGE_TAG=...` | Prepare object-storage hosts, provision the selected S3-compatible service, and switch production files to S3 |
| `make step-04 APP_IMAGE_TAG=...` | Put the application behind Nginx, switch image delivery to `/uploads/`, and restrict the storage API |
| `make step-05` | Issue one SAN certificate and enable HTTPS for all environment domains |
| `make step-01-all` ... `make step-04-all` | Run the selected step for all environments; step 4 reconciles the shared gateway only once |
| `make nginx-install` | Install Nginx, apply the minimal bootstrap configuration, and start it |
| `make nginx-proxy` | Add the application reverse proxy without caching |
| `make nginx-cache` | Add caches, switch uploads to Nginx, and restrict the storage API |
| `make nginx-cache-check` | Verify HTTP cache behavior after the three learning stages |
| `make infra-preview ENVIRONMENT=stage` | Show shared-host and selected-environment infrastructure changes without applying them |
| `make infra-apply ENVIRONMENT=stage` | Reconcile shared services, selected-environment resources, gateway, TLS, and firewall |
| `make infra-apply-all` | Reconcile shared services and resources for dev, stage, and prod before promotion |
| `make all APP_IMAGE_TAG=...` | Install dependencies, render configuration, and run all five steps |
| `make smoke` | Run the database, object-storage, and Nginx smoke-test roles |
| `make cache-check` | Verify `MISS`/`HIT` behavior for frontend assets and uploads |
| `make tls-check` | Verify HTTPS, TLS policy, certificate renewal, and the Certbot timer |
| `make reset ENVIRONMENT=stage` | Remove only the selected environment application, database data, bucket, credentials, and caches |
| `make reset` | Remove all environments and shared project infrastructure |
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
TLS stages. `db_host` prepares host dependencies and persistent storage,
`db_firewall` restricts PostgreSQL access, and `db_service` manages
the container and credentials. `db_service_smoke_test` verifies a marker
survives a PostgreSQL container restart. `db_migration` applies the
Flyway schema before `app_service`, while
`db_application_smoke_test` checks
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
The `ENVIRONMENT`, `IMAGE_REPOSITORY`, and `APP_IMAGE_TAG` overrides apply to runtime operations.

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
make rollback ENVIRONMENT=stage
```

The command swaps active and previous containers, verifies the restored runtime,
and returns the original active container if verification fails. A successful
manual rollback keeps the replaced release in the previous slot, so the swap is
reversible until the next deployment.

Container rollback does not reverse database migrations or external data
changes. Production migrations must remain compatible with the previous image.

Shared and derived settings live in
`environments/_shared/inventory/group_vars/all/vars.yml`. Each environment
keeps its seven identity values in `environments/<name>/inventory/group_vars/all/vars.yml`.
The encrypted
`environments/_shared/inventory/inventory.vault.yml` contains the
real host topology and named `dev`, `stage`, and `prod` secret sections; shared
vars select one by `environment_name`. Before every operation, `make prepare-inventory` renders host groups, addresses, and SSH ports into each ignored environment `hosts.yml` with mode `0600`. Those generated files contain no application credentials and activate their adjacent `group_vars`. Ansible continues to read secret values directly from Vault. The `ssh_client` role creates
`environments/_shared/runtime/known_hosts` locally with mode `0600` before the
first SSH connection.

Project roles are grouped by domain under `roles/`: `common`, `application`,
`database`, `object_storage`, `nginx`, `tls`, and `vendor`. Application, database, and object-storage roles use globally unique prefixed
names such as `app_service`, `db_service`, and `storage_deploy`. Nginx and TLS
roles retain path-qualified names such as `nginx/cache` and `tls/certificate`.
The names of role variables remain fully prefixed because Ansible variables
share a play-level namespace. Galaxy roles are installed under `roles/vendor`
and keep their upstream names inside that directory.

Each service step prepares its own target hosts before starting containers.
Step 1 provisions application hosts, step 2 provisions database hosts, and
step 3 provisions object-storage hosts. PostgreSQL remains restricted to the
application host. The storage API is public during step 3 so browsers can use
presigned image URLs, then the `nginx-cache` substage restricts it to the
application host after switching public image delivery to `/uploads/`. The
provisioning user performs host
administration, while the deployment user is created on each host during its
provisioning step, belongs to the `docker` group, and manages containers
without privilege escalation.

`make reset ENVIRONMENT=dev`, `stage`, or `prod` removes only that environment:
its application and migration containers, persistent application directory,
database container and data, object-storage containers and data, firewall facts,
and Nginx caches. Nginx, TLS, Docker, UFW, deployment users, and the other
environments remain in place.

`make reset` without `ENVIRONMENT` is the destructive full reset. It removes all
application, PostgreSQL, MinIO, and RustFS containers and persistent data,
project firewall rules and facts, deployment users, Docker, Nginx, TLS, and UFW.
It deliberately preserves the provisioning user so the hosts remain reachable.
Both reset modes pass their own explicit confirmation variable from Make to the
corresponding role.

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
3. The `nginx-cache` substage invokes `nginx/cache` to add cache zones and the
   `/assets/` and `/uploads/` locations, switches the application to
   `/uploads/`, and invokes `storage_firewall` to restrict the storage
   API to the application host. Each Nginx role renders a complete readable
   snapshot of its stage; no earlier role contains extension points for a
   later one.
4. `nginx/cache_smoke_test` verifies real `MISS`/`HIT` behavior and cleans
   up its temporary upload.

After completing project steps 1–3, run `make nginx-install`,
`make nginx-proxy`, `make nginx-cache`, and `make nginx-cache-check` in
order to inspect each intermediate HTTP state. The proxy command also applies
the existing firewall policy at the playbook level; firewall management is not
part of the reverse-proxy role. Use `make cache-check` for the final HTTPS
environment. The regular `make step-04` target executes all four stages in the
required order for the selected environment. `make step-04-all` reconciles the
shared Nginx gateway and its route catalog once, then switches the application,
storage firewall, and cache smoke tests independently for dev, stage, and prod.
Dependencies point forward only: a later role validates artifacts created by an
earlier role, while earlier roles contain no knowledge of later ones.

The `nginx/reverse_proxy` role creates one virtual host per environment. Dynamic
requests are routed to `127.0.0.1:8082`, `127.0.0.1:8081`, or
`127.0.0.1:8080`; uploads use the matching isolated RustFS endpoint. Application
and Actuator ports remain available only on the server loopback interface.

The base reverse-proxy role remains HTTP-only. Step 5 splits HTTPS provisioning
between three roles. `tls/certificate` publishes the HTTP-01 challenge and
uses `geerlingguy.certbot` for package installation and certificate issuance.
`tls/certificate_renewal` enables the distribution-provided `certbot.timer`;
its deploy hook validates the Nginx configuration and reloads Nginx after a
successful renewal. The external Certbot role's cron renewal is disabled.
`tls/nginx` then replaces the HTTP virtual host with an HTTP-to-HTTPS redirect
and a TLS virtual host.

Certificate issuance, renewal setup, and HTTPS publication are intentionally
exposed as one operation:

```bash
make step-05
```

Only TLS 1.2 and TLS 1.3 are enabled. TLS 1.2 and TLS 1.3 use explicit modern
cipher allowlists; legacy protocols, CBC suites, static RSA key exchange, and
TLS session tickets are disabled. Run the full verification with:

```bash
make tls-check
```

`make step-05` always uses the production inventory and runs all three TLS roles
once. It manages one SAN certificate containing the dev, stage, and production
domains; `ENVIRONMENT` does not affect this command. TLS becomes public during
the same operation. There is no separate boolean switch.
The `nginx/reverse_proxy` role requires no TLS-specific code or variables.

Frontend files under `/assets/` and uploaded bulletin images under `/uploads/`
are cached by Nginx for five days. Inactive cache entries are eligible for
removal after seven days for frontend assets and after 30 days for uploads.
Cached responses include `X-Cache-Status`, which reports values such as `MISS`
and `HIT`.

Steps 4 and 5 run an end-to-end cache smoke test after deploying the
application. The test requests a real frontend asset twice and requires the
second response to be a cache `HIT`. It also uploads a temporary object through
the application, requires `MISS` followed by `HIT` from `/uploads/`, verifies
the response content, and removes the object from storage. Run this check
independently with:

```bash
make cache-check
```

The shared `firewall_policy` role exposes `8080` after step 1, replaces it with public
HTTP port `80` after Nginx is ready in step 4, and adds `443` only after HTTPS
is configured in step 5. Nginx and TLS roles do not manage UFW themselves.

## S3-compatible object storage

Object storage responsibilities are split between five roles:

- `storage_firewall` manages access to the storage API;
- `storage_deploy` prepares and runs MinIO or RustFS;
- `storage_migration` copies and verifies data between S3 endpoints;
- `storage_provider_switch` coordinates application downtime and cutover;
- `storage_smoke_test` verifies application uploads, downloads, and
  restricted application credentials.

Select the implementation with `object_storage_provider` in
`environments/_shared/inventory/group_vars/all/vars.yml`; the project
currently selects RustFS.
Switching providers performs an online initial copy and a final copy while the
application is stopped. Provider data directories remain available for rollback.
The full `make reset` removes resources belonging to both providers. An
environment reset removes the selected environment's entire storage instance
without touching the other two instances.

The selected RustFS image is pinned to `1.0.0-beta.3`; treat this branch as an
experimental deployment option until RustFS publishes a stable release suitable
for this project.

`make step-03` provisions the selected environment's RustFS instance and bucket
and configures two separate identities:

- `bulletins-storage-admin` is the administrative identity used only by Ansible
  for provisioning and smoke-test cleanup.
- the environment application identity (`bulletins-app`, `bulletins-stage-app`,
  or `bulletins-dev-app`) is passed to the application and has only
  `s3:GetObject` and `s3:PutObject` on
  `arn:aws:s3:::bulletin-images/bulletins/*`.

The selected environment's S3 API (`9000`, `9002`, or `9004`) is publicly reachable so the application can return
presigned image URLs immediately after step 3. Uploading, listing, and other
protected operations still require S3 credentials. The administrative console
(`9001`, `9003`, or `9005`) listens only on the object-storage host loopback
interface. For temporary production console access, create an SSH tunnel:

```bash
ssh -L 9001:127.0.0.1:9001 neutron@89.169.134.144
```

Use the matching port for stage or dev. While the tunnel is open, visit
`http://127.0.0.1:9001/rustfs/console`. Starting
with step 4, public image requests use the Nginx `/uploads/` location instead
of presigned S3 URLs. After that transition, step 4 restricts the selected
environment's S3 API port to the application host and verifies `/uploads/` with
the cache smoke test.

Objects under the `bulletins/` prefix are publicly readable because they are
public bulletin images served through Nginx. Listing the bucket and writing or
deleting objects still require credentials.

The administrative secret and environment application keys are stored in the
encrypted `_shared/inventory/inventory.vault.yml`. Do not add those
credentials directly to GitHub secrets. GitHub Actions needs only
`ANSIBLE_VAULT_PASSWORD` to decrypt them during deployment.

Provision or update the selected environment's complete storage instance:

```bash
make step-03
```

The selected environment inventory supplies the S3 endpoint, bucket, and region.
The deployment role passes those values and the restricted application
credentials as `STORAGE_S3_*` environment variables.

## Object storage verification

Step 3 runs `storage_smoke_test` after the application becomes ready.
It uploads a text object through `POST /api/files/upload`, requests a fresh
presigned URL from `GET /api/files/view`, downloads the object from the Ansible
controller, compares its contents, and verifies that the application
credentials cannot delete it. Ansible then removes the object with the
administrative identity.

After step 4, public image delivery no longer uses presigned URLs. The
`nginx/cache_smoke_test` role uploads an object through the application and
verifies `MISS` followed by `HIT` through `/uploads/`. Run the aggregate smoke
playbook without redeploying:

```bash
make smoke
```
