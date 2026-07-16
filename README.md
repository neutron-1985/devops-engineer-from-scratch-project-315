[![Actions Status](https://github.com/neutron-1985/devops-engineer-from-scratch-project-315/actions/workflows/hexlet-check.yml/badge.svg)](https://github.com/neutron-1985/devops-engineer-from-scratch-project-315/actions)
[![Deploy](https://github.com/neutron-1985/devops-engineer-from-scratch-project-315/actions/workflows/deploy.yml/badge.svg)](https://github.com/neutron-1985/devops-engineer-from-scratch-project-315/actions/workflows/deploy.yml)

# Project infrastructure

Ansible configuration for provisioning and deploying the `project-devops-deploy` application. The application image is built and published by the separate application repository; this repository deploys a selected image tag.

## Deployed service

The production service is available at the following addresses:

- Application: `http://n-devops.jumpingcrab.com:80/`
- Swagger UI: `http://n-devops.jumpingcrab.com:80/swagger-ui/index.html`

Nginx accepts public HTTP traffic on port `80`. Application port `8080` and
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

Deployment commands target `production` by default; override `ANSIBLE_LIMIT` for another environment. `make provision` targets all `infrastructure` hosts by default; override `PROVISION_LIMIT` for a narrower group.

## Manual GitHub Actions deployment

Open **Actions → Deploy → Run workflow**, enter the Docker tag, and start the workflow. Prefer the immutable `sha-<commit>` tag produced by the application repository instead of `latest`.

Configure these secrets in the `production` GitHub Environment or in repository Actions secrets:

- `ANSIBLE_VAULT_PASSWORD`
- `DEPLOY_SSH_KEY`

The workflow validates the tag, runs Ansible in check mode, and then performs the deployment. The `production` environment can additionally require reviewer approval.

## Infrastructure commands

| Command | Purpose |
|---|---|
| `make all` | Install Ansible dependencies, render configuration, provision services, deploy the application, and run the smoke test |
| `make provision` | Install Docker, configure UFW, and install Nginx on application hosts |
| `make database` | Provision PostgreSQL |
| `make storage` | Provision MinIO object storage |
| `make smoke` | Upload and download a test object through the deployed application |
| `make reset` | Remove project resources, data, deploy users, Docker, and UFW from infrastructure hosts |
| `make ansible-check APP_IMAGE_TAG=...` | Check a deployment without applying it |
| `make deploy APP_IMAGE_TAG=...` | Deploy the selected application image |
| `make vault-rekey` | Rotate the Ansible Vault password |

`make all` executes the complete bootstrap in dependency order: `ansible-install`, configuration rendering, host provisioning, PostgreSQL, object storage, and application deployment with its smoke test. The existing `PROVISION_LIMIT`, `ANSIBLE_LIMIT`, `IMAGE_REPOSITORY`, and `APP_IMAGE_TAG` overrides also apply to this command.

Deployment targets, SSH host keys, users, and environment groups are stored in encrypted `vars/inventory_vault.yml`. Database and object-storage credentials are stored in `group_vars/all/database_vault.yml` and `group_vars/all/object_storage_vault.yml`.

Run `make provision` before `make database` or `make storage`. The service roles assume that `server_provision` has already installed Docker and UFW; they only configure PostgreSQL or MinIO and their service-specific firewall rules.

`make reset` is destructive. It removes the application, PostgreSQL and MinIO
containers and persistent data, project firewall rules and facts, deployment
users, Docker, Nginx, and UFW. It deliberately preserves the provisioning user so the
hosts remain reachable. Limit cleanup to selected hosts with `RESET_LIMIT`, for
example `make reset RESET_LIMIT=production`. The role requires the explicit
`infrastructure_reset_confirm=true` confirmation supplied by the Make target.

## Nginx reverse proxy and caching

The `nginx_reverse_proxy` role configures `n-devops.jumpingcrab.com` as the
virtual host and proxies dynamic requests to the application on
`127.0.0.1:8080`. The application and Actuator ports remain available only on
the server loopback interface.

Frontend files under `/assets/` are cached by Nginx and clients for one year;
Vite includes a content hash in their names. Uploaded bulletin images are
served from MinIO through `/uploads/` and cached for 30 days. Responses include
`X-Cache-Status`, which reports values such as `MISS` and `HIT`. HTML and API
responses use `Cache-Control: no-cache`.

Run `make provision`, `make storage`, and then `make deploy APP_IMAGE_TAG=...`
when enabling this setup on an existing environment. Provisioning removes the
old public firewall rules for ports `8080` and `9090`.

## S3-compatible object storage

`make storage` provisions the `bulletin-images` bucket in MinIO and
configures two separate identities:

- `bulletins-storage-admin` is the MinIO root identity used only by Ansible
  for provisioning and smoke-test cleanup.
- `bulletins-app` is passed to the application and has only
  `s3:GetObject` and `s3:PutObject` on
  `arn:aws:s3:::bulletin-images/bulletins/*`.

Objects under the `bulletins/` prefix are publicly readable because they are
public bulletin images served through Nginx. Listing the bucket and writing or
deleting objects still require credentials.

The root password and application secret key are stored in the encrypted
`group_vars/all/object_storage_vault.yml`. Do not add either credential
directly to GitHub secrets. GitHub Actions needs only
`ANSIBLE_VAULT_PASSWORD` to decrypt them during deployment.

Provision or update the bucket, user, and policy:

```bash
make storage
```

The production inventory supplies the MinIO endpoint, bucket, and region.
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
