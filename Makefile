.DEFAULT_GOAL := help

EDITOR ?= vi
ENVIRONMENT ?= dev
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
ENVIRONMENT_STEP_ALL_TARGETS = step-01-all step-02-all step-03-all
STEP_ALL_TARGETS = $(ENVIRONMENT_STEP_ALL_TARGETS) step-04-all

# Help
help:
	@echo "Project steps:"
	@echo "  make step-01             Prepare and deploy the standalone application"
	@echo "  make step-02             Provision database hosts and PostgreSQL"
	@echo "  make step-03             Provision the selected object storage service"
	@echo "  make step-04             Configure Nginx"
	@echo "    make nginx-install     Install and start Nginx"
	@echo "    make nginx-proxy       Configure the application reverse proxy"
	@echo "    make nginx-cache       Add caches and complete the storage proxy cutover"
	@echo "    make nginx-cache-check Verify the HTTP cache behavior"
	@echo "  make step-05             Configure shared HTTPS for all domains"
	@echo "  make step-01-all..step-04-all  Run the selected environment step for dev, stage, and prod"
	@echo ""
	@echo "Operations:"
	@echo "  make all       Run the complete five-step scenario"
	@echo "  make infra-preview ENVIRONMENT=stage  Preview shared and environment infrastructure changes"
	@echo "  make infra-apply ENVIRONMENT=stage  Reconcile shared and environment infrastructure"
	@echo "  make infra-apply-all  Reconcile shared infrastructure and all environments"
	@echo "  make deploy ENVIRONMENT=stage  Deploy the selected environment"
	@echo "  make rollback ENVIRONMENT=stage  Roll back the selected environment"
	@echo "  make prepare-inventory  Render ignored host inventories from Vault"
	@echo "  make prepare-ssh ENVIRONMENT=stage  Prepare trusted SSH host keys"
	@echo "  make smoke     Verify database, object storage, and Nginx caches"
	@echo "  make cache-check Verify Nginx static and upload caches"
	@echo "  make tls-check Verify HTTPS and certificate renewal"
	@echo "  make reset ENVIRONMENT=stage  Reset only the selected environment"
	@echo "  make reset     Reset all infrastructure (destructive default)"

# Ansible setup
ansible-install:
	ANSIBLE_CONFIG=ansible.cfg ansible-galaxy role install -r requirements.yml --roles-path roles/vendor
	ANSIBLE_CONFIG=ansible.cfg ansible-galaxy collection install -r requirements.yml

prepare-inventory:
	$(ANSIBLE_RENDER_INVENTORY_COMMAND)

prepare-ssh: prepare-inventory
	$(ANSIBLE_PREPARE_SSH_COMMAND)

# Project steps
# Step 1 | Application
step-01: prepare-ssh
	$(ANSIBLE) playbooks/steps/step_01_application.yml $(ANSIBLE_IMAGE_VARS)

# Step 2 | Database
step-02: prepare-ssh
	$(ANSIBLE) playbooks/steps/step_02_database.yml $(ANSIBLE_IMAGE_VARS)

# Step 3 | Object storage
step-03: prepare-ssh
	$(ANSIBLE) playbooks/steps/step_03_object_storage.yml $(ANSIBLE_IMAGE_VARS)

# Step 4 | Nginx
step-04: prepare-ssh
	$(ANSIBLE) playbooks/steps/step_04_nginx.yml $(ANSIBLE_IMAGE_VARS)

nginx-install: prepare-ssh
	$(ANSIBLE) playbooks/steps/step_04_nginx.yml --tags nginx-install

nginx-proxy: prepare-ssh
	$(ANSIBLE) playbooks/steps/step_04_nginx.yml --tags nginx-proxy

nginx-cache: prepare-ssh
	$(ANSIBLE) playbooks/steps/step_04_nginx.yml --tags nginx-cache

nginx-cache-check: prepare-ssh
	$(ANSIBLE) playbooks/steps/step_04_nginx.yml --tags cache-smoke

# Step 5 | HTTPS
step-05: prepare-inventory
	$(ANSIBLE_PROD) playbooks/prepare_ssh.yml
	$(ANSIBLE_PROD) playbooks/steps/step_05_https.yml


# Run one project step for every environment in promotion order.
$(ENVIRONMENT_STEP_ALL_TARGETS):
	$(MAKE) $(patsubst %-all,%,$@) ENVIRONMENT=dev
	$(MAKE) $(patsubst %-all,%,$@) ENVIRONMENT=stage
	$(MAKE) $(patsubst %-all,%,$@) ENVIRONMENT=prod

step-04-all: prepare-inventory
	$(ANSIBLE_PROD) playbooks/prepare_ssh.yml
	$(ANSIBLE_PROD) playbooks/steps/step_04_nginx.yml --tags gateway $(ANSIBLE_IMAGE_VARS)
	$(call ANSIBLE_FOR,dev) playbooks/steps/step_04_nginx.yml --tags environment $(ANSIBLE_IMAGE_VARS)
	$(call ANSIBLE_FOR,stage) playbooks/steps/step_04_nginx.yml --tags environment $(ANSIBLE_IMAGE_VARS)
	$(call ANSIBLE_FOR,prod) playbooks/steps/step_04_nginx.yml --tags environment $(ANSIBLE_IMAGE_VARS)

# Complete scenario
all: ansible-install prepare-ssh
	$(ANSIBLE) playbook.yml $(ANSIBLE_IMAGE_VARS)

# Runtime operations
infra-preview: prepare-ssh
	$(ANSIBLE_PROD) playbooks/infrastructure.yml --check --diff
	$(ANSIBLE) playbooks/provision.yml --check --diff
	$(ANSIBLE_PROD) playbooks/gateway.yml --check --diff

infra-apply: prepare-ssh
	$(ANSIBLE_PROD) playbooks/infrastructure.yml
	$(ANSIBLE) playbooks/provision.yml
	$(ANSIBLE_PROD) playbooks/gateway.yml

infra-apply-all: prepare-ssh
	$(ANSIBLE_PROD) playbooks/infrastructure.yml
	$(call ANSIBLE_FOR,dev) playbooks/provision.yml
	$(call ANSIBLE_FOR,stage) playbooks/provision.yml
	$(call ANSIBLE_FOR,prod) playbooks/provision.yml
	$(ANSIBLE_PROD) playbooks/gateway.yml

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
reset: reset-environment
else
reset: reset-all
endif

reset-environment: prepare-ssh
	$(ANSIBLE) playbooks/reset.yml --tags reset -e reset_scope=environment -e environment_reset_confirm=true

reset-all: prepare-inventory
	$(ANSIBLE_PROD) playbooks/prepare_ssh.yml
	$(ANSIBLE_PROD) playbooks/reset.yml --tags reset -e reset_scope=all -e infrastructure_reset_confirm=true

vault-rekey:
	install -m 600 /dev/null .vault-password.new
	$(EDITOR) .vault-password.new
	ansible-vault rekey --new-vault-password-file .vault-password.new $(VAULT_FILES)
	mv .vault-password.new .vault-password

.PHONY: help ansible-install prepare-inventory prepare-ssh step-01 step-02 step-03 step-04 nginx-install nginx-proxy nginx-cache nginx-cache-check step-05 $(STEP_ALL_TARGETS) all infra-preview infra-apply infra-apply-all deploy rollback ansible-check smoke cache-check tls-check reset reset-environment reset-all vault-rekey
