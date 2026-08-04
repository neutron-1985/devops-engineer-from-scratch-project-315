.DEFAULT_GOAL := help

EDITOR ?= vi
ENVIRONMENT ?= dev
RESET_MODE ?= hard
INVENTORY_DIR = environments/$(ENVIRONMENT)/inventory
INVENTORY = $(INVENTORY_DIR)/hosts.yml
PROD_INVENTORY = environments/prod/inventory/hosts.yml
SHARED_INVENTORY = environments/_shared/inventory/inventory.vault.yml
VAULT_FILES = $(SHARED_INVENTORY)
ANSIBLE = ANSIBLE_CONFIG=ansible.cfg ansible-playbook -i $(SHARED_INVENTORY) -i $(INVENTORY)
ANSIBLE_PROD = ANSIBLE_CONFIG=ansible.cfg ansible-playbook -i $(SHARED_INVENTORY) -i $(PROD_INVENTORY)
ANSIBLE_FOR = ANSIBLE_CONFIG=ansible.cfg ansible-playbook -i $(SHARED_INVENTORY) -i environments/$(1)/inventory/hosts.yml
ANSIBLE_SHARED = ANSIBLE_CONFIG=ansible.cfg ansible-playbook -i $(SHARED_INVENTORY)
ANSIBLE_RENDER_INVENTORY_COMMAND = $(ANSIBLE_SHARED) playbooks/render_inventory.yml
ANSIBLE_PREPARE_SSH_COMMAND = $(ANSIBLE) playbooks/prepare_ssh.yml
ANSIBLE_IMAGE_VARS = $(if $(IMAGE_REPOSITORY),-e app_image_repository=$(IMAGE_REPOSITORY)) $(if $(APP_IMAGE_TAG),-e app_image_tag=$(APP_IMAGE_TAG))

# Help
help:
	@printf '%-52s | %s\n' \
		"Command" "Description" \
		"----------------------------------------------------" "-----------------------------------------------" \
		"make ansible-install" "Install Ansible roles and collections" \
		"make prepare-inventory" "Render ignored host inventories from Vault" \
		"make prepare-ssh ENVIRONMENT=stage" "Prepare trusted SSH host keys" \
		"----------------------------------------------------" "-----------------------------------------------" \
		"make step-01" "Prepare application server infrastructure" \
		"make step-02" "Provision database hosts and PostgreSQL" \
		"make step-03" "Provision object storage, migrate DB, and deploy application" \
		"make step-04" "Configure Nginx and verify application storage" \
		"make step-05" "Configure shared HTTPS for all domains" \
		"----------------------------------------------------" "-----------------------------------------------" \
		"make all ENVIRONMENT=stage" "Provision dependencies and deploy one environment" \
		"make infra-preview ENVIRONMENT=stage" "Preview shared and environment infrastructure changes" \
		"make infra-apply ENVIRONMENT=stage" "Reconcile shared and selected environment infrastructure" \
		"make ansible-check ENVIRONMENT=stage" "Check deployment without applying changes" \
		"make deploy ENVIRONMENT=stage" "Deploy the selected environment" \
		"make rollback ENVIRONMENT=stage" "Roll back the selected environment" \
		"make smoke ENVIRONMENT=stage" "Verify database, object storage, and Nginx caches" \
		"make cache-check ENVIRONMENT=stage" "Verify Nginx static and upload caches" \
		"make tls-check ENVIRONMENT=stage" "Verify HTTPS, TLS policy, and renewal timer" \
		"----------------------------------------------------" "-----------------------------------------------" \
		"make reset ENVIRONMENT=stage RESET_MODE=soft" "Stop stage and preserve data and logs" \
		"make reset RESET_MODE=soft" "Stop all project environments and preserve data and logs" \
		"make reset ENVIRONMENT=stage" "Hard-reset only the selected environment" \
		"make reset" "Hard-reset all project environments and shared resources" \
		"----------------------------------------------------" "-----------------------------------------------" \
		"make vault-rekey" "Change the Ansible Vault password"


# Ansible setup
ansible-install:
	ANSIBLE_CONFIG=ansible.cfg ansible-galaxy role install -r requirements.yml --roles-path roles/vendor
	ANSIBLE_CONFIG=ansible.cfg ansible-galaxy collection install -r requirements.yml

prepare-inventory:
	$(ANSIBLE_RENDER_INVENTORY_COMMAND)

prepare-ssh: prepare-inventory
	$(ANSIBLE_PREPARE_SSH_COMMAND)

# Project steps
# Step 1 | Application server infrastructure
step-01: prepare-ssh
	$(ANSIBLE) playbooks/steps/step_01_application.yml

# Step 2 | Database
step-02: prepare-ssh
	$(ANSIBLE) playbooks/steps/step_02_database.yml

# Step 3 | Object storage
step-03: prepare-ssh
	$(ANSIBLE) playbooks/steps/step_03_object_storage.yml $(ANSIBLE_IMAGE_VARS)

# Step 4 | Nginx
step-04: prepare-ssh
	$(ANSIBLE) playbooks/steps/step_04_nginx.yml

# Step 5 | HTTPS
step-05: prepare-inventory
	$(ANSIBLE_PROD) playbooks/prepare_ssh.yml
	$(ANSIBLE_PROD) playbooks/steps/step_05_https.yml -e nginx_route_scope=all


# Complete scenario
all: prepare-ssh
	$(ANSIBLE) playbook.yml $(ANSIBLE_IMAGE_VARS)

# Runtime operations
infra-preview: prepare-ssh
	$(ANSIBLE_PROD) playbooks/infrastructure.yml --check --diff
	$(ANSIBLE) playbooks/provision.yml --check --diff
	$(ANSIBLE_PROD) playbooks/gateway.yml --check --diff -e nginx_route_environment=$(ENVIRONMENT)

infra-apply: prepare-ssh
	$(ANSIBLE_PROD) playbooks/infrastructure.yml
	$(ANSIBLE) playbooks/provision.yml
	$(ANSIBLE_PROD) playbooks/gateway.yml -e nginx_route_environment=$(ENVIRONMENT)

deploy: prepare-ssh
	$(ANSIBLE) playbooks/deploy.yml $(ANSIBLE_IMAGE_VARS)

rollback: prepare-ssh
	$(ANSIBLE) playbooks/rollback.yml

ansible-check: prepare-ssh
	$(ANSIBLE) playbooks/deploy.yml --check --diff $(ANSIBLE_IMAGE_VARS)

smoke: prepare-ssh
	$(ANSIBLE) playbooks/verify.yml --tags smoke

cache-check: prepare-ssh
	$(ANSIBLE) playbooks/verify.yml --tags cache-smoke

tls-check: prepare-ssh
	$(ANSIBLE) playbooks/verify.yml --tags tls-smoke

# Maintenance
ifneq ($(filter command line environment environment override,$(origin ENVIRONMENT)),)
reset: prepare-ssh
	$(ANSIBLE) playbooks/reset.yml --tags reset -e reset_scope=environment -e reset_mode=$(RESET_MODE) -e environment_reset_confirm=true
else
reset: prepare-inventory
	$(ANSIBLE_PROD) playbooks/prepare_ssh.yml
	$(call ANSIBLE_FOR,dev) playbooks/reset.yml --tags reset -e reset_scope=environment -e reset_mode=$(RESET_MODE) -e environment_reset_confirm=true
	$(call ANSIBLE_FOR,stage) playbooks/reset.yml --tags reset -e reset_scope=environment -e reset_mode=$(RESET_MODE) -e environment_reset_confirm=true
	$(call ANSIBLE_FOR,prod) playbooks/reset.yml --tags reset -e reset_scope=environment -e reset_mode=$(RESET_MODE) -e environment_reset_confirm=true
	$(ANSIBLE_PROD) playbooks/reset.yml --tags reset -e reset_scope=all -e reset_mode=$(RESET_MODE) -e infrastructure_reset_confirm=true
endif

vault-rekey:
	install -m 600 /dev/null .vault-password.new
	$(EDITOR) .vault-password.new
	ansible-vault rekey --new-vault-password-file .vault-password.new $(VAULT_FILES)
	mv .vault-password.new .vault-password

.PHONY: help ansible-install prepare-inventory prepare-ssh step-01 step-02 step-03 step-04 step-05 all infra-preview infra-apply deploy rollback ansible-check smoke cache-check tls-check reset vault-rekey
