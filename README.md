[![Actions Status](https://github.com/neutron-1985/devops-engineer-from-scratch-project-315/actions/workflows/hexlet-check.yml/badge.svg)](https://github.com/neutron-1985/devops-engineer-from-scratch-project-315/actions)
[![Deploy](https://github.com/neutron-1985/devops-engineer-from-scratch-project-315/actions/workflows/deploy.yml/badge.svg)](https://github.com/neutron-1985/devops-engineer-from-scratch-project-315/actions/workflows/deploy.yml)

# Project infrastructure

Ansible configuration for provisioning and deploying the `project-devops-deploy` application. The application image is built and published by the separate application repository; this repository deploys a selected image tag.

## Requirements

- Ansible
- SSH access to the managed hosts
- Ansible Vault password

Install roles and collections:

```bash
make ansible-install
```

Create the local Vault password file:

```bash
install -m 600 /dev/null ansible/.vault-password
$EDITOR ansible/.vault-password
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

Commands target `production` by default. Override `ANSIBLE_LIMIT` to work with another inventory group.

## Manual GitHub Actions deployment

Open **Actions → Deploy → Run workflow**, enter the Docker tag, and start the workflow. Prefer the immutable `sha-<commit>` tag produced by the application repository instead of `latest`.

Configure these secrets in the `production` GitHub Environment or in repository Actions secrets:

- `ANSIBLE_VAULT_PASSWORD`
- `DEPLOY_SSH_KEY`

The workflow validates the tag, runs Ansible in check mode, and then performs the deployment. The `production` environment can additionally require reviewer approval.

## Infrastructure commands

| Command | Purpose |
|---|---|
| `make provision` | Provision application hosts |
| `make database` | Provision PostgreSQL |
| `make storage` | Provision MinIO object storage |
| `make ansible-check APP_IMAGE_TAG=...` | Check a deployment without applying it |
| `make deploy APP_IMAGE_TAG=...` | Deploy the selected application image |
| `make vault-rekey` | Rotate the Ansible Vault password |

Deployment targets, SSH host keys, users, and environment groups are stored in encrypted `ansible/vault/production.yml`. Service credentials are stored in encrypted files under `ansible/group_vars/all/`.
