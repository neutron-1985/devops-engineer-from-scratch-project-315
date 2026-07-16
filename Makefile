include config.mk

EDITOR ?= vi
IMAGE_REPOSITORY ?= $(DOCKER_REGISTRY)/$(DOCKER_REPOSITORY)
APP_IMAGE_TAG ?= latest
ANSIBLE_LIMIT ?= production
PROVISION_LIMIT ?= infrastructure
RESET_LIMIT ?= infrastructure
ANSIBLE = ANSIBLE_CONFIG=ansible.cfg ansible-playbook
ANSIBLE_CONFIGURE_COMMAND = $(ANSIBLE) -i localhost, -c local playbooks/render_deploy_config.yml
ANSIBLE_PROVISION_COMMAND = $(ANSIBLE) playbook.yml --tags provision --limit "$(PROVISION_LIMIT)"
ANSIBLE_DATABASE_COMMAND = $(ANSIBLE) playbook.yml --tags database --limit database
ANSIBLE_STORAGE_COMMAND = $(ANSIBLE) playbook.yml --tags storage --limit object_storage
ANSIBLE_DEPLOY_COMMAND = $(ANSIBLE) playbook.yml --tags deploy --limit "$(ANSIBLE_LIMIT)" -e app_image_repository=$(IMAGE_REPOSITORY) -e app_image_tag=$(APP_IMAGE_TAG)

all: ansible-install
	$(ANSIBLE_CONFIGURE_COMMAND)
	$(ANSIBLE_PROVISION_COMMAND)
	$(ANSIBLE_DATABASE_COMMAND)
	$(ANSIBLE_STORAGE_COMMAND)
	$(ANSIBLE_DEPLOY_COMMAND)

ansible-install:
	ANSIBLE_CONFIG=ansible.cfg ansible-galaxy install -r requirements.yml

ansible-configure:
	$(ANSIBLE_CONFIGURE_COMMAND)

vault-rekey:
	install -m 700 -d .generated
	install -m 600 /dev/null .generated/vault-password.new
	$(EDITOR) .generated/vault-password.new
	ansible-vault rekey --vault-password-file .vault-password --new-vault-password-file .generated/vault-password.new vars/inventory_vault.yml group_vars/all/database_vault.yml group_vars/all/object_storage_vault.yml
	mv .generated/vault-password.new .vault-password

provision: ansible-configure
	$(ANSIBLE_PROVISION_COMMAND)

deploy: ansible-configure
	$(ANSIBLE_DEPLOY_COMMAND)

ansible-check: ansible-configure
	$(ANSIBLE) playbook.yml --tags deploy --check --diff --limit "$(ANSIBLE_LIMIT)" -e app_image_repository=$(IMAGE_REPOSITORY) -e app_image_tag=$(APP_IMAGE_TAG)

database: ansible-configure
	$(ANSIBLE_DATABASE_COMMAND)

storage: ansible-configure
	$(ANSIBLE_STORAGE_COMMAND)

smoke: ansible-configure
	$(ANSIBLE) playbook.yml --tags smoke --limit production

tls-check: ansible-configure
	$(ANSIBLE) playbook.yml --tags tls-smoke --limit production

reset: ansible-configure
	$(ANSIBLE) playbook.yml --tags reset --limit "$(RESET_LIMIT)" -e infrastructure_reset_confirm=true

.PHONY: all ansible-install ansible-configure vault-rekey provision deploy ansible-check database storage smoke tls-check reset
