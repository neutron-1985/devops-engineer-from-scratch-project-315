.DEFAULT_GOAL := help

EDITOR ?= vi
ANSIBLE_LIMIT ?= production
RESET_LIMIT ?= infrastructure
ANSIBLE = ANSIBLE_CONFIG=ansible.cfg ansible-playbook
ANSIBLE_CONFIGURE_COMMAND = $(ANSIBLE) -i localhost, -c local playbooks/render_deploy_config.yml
GENERATED_CONFIG = generated.inventory.ini generated.known_hosts
ANSIBLE_IMAGE_VARS = $(if $(IMAGE_REPOSITORY),-e app_image_repository=$(IMAGE_REPOSITORY)) $(if $(APP_IMAGE_TAG),-e app_image_tag=$(APP_IMAGE_TAG))
ANSIBLE_ALL_COMMAND = $(ANSIBLE) playbook.yml $(ANSIBLE_IMAGE_VARS)
ANSIBLE_DEPLOY_COMMAND = $(ANSIBLE) playbooks/deploy.yml --limit "$(ANSIBLE_LIMIT)" $(ANSIBLE_IMAGE_VARS)

# Help
help:
	@echo "Project steps:"
	@echo "  make step-01   Provision application hosts"
	@echo "  make step-02   Deploy the standalone application"
	@echo "  make step-03   Provision database hosts and PostgreSQL"
	@echo "  make step-04   Provision the selected object storage service"
	@echo "  make step-05   Configure Nginx"
	@echo "  make step-06   Configure HTTPS"
	@echo ""
	@echo "Nginx learning stages:"
	@echo "  make nginx-install Install and start Nginx"
	@echo "  make nginx-proxy Configure the application reverse proxy"
	@echo "  make nginx-cache Add static and upload caches"
	@echo "  make nginx-cache-check Verify the HTTP cache behavior"
	@echo ""
	@echo "Operations:"
	@echo "  make all       Run the complete six-step scenario"
	@echo "  make deploy    Deploy an application update"
	@echo "  make smoke     Verify object storage and Nginx caches"
	@echo "  make cache-check Verify Nginx static and upload caches"
	@echo "  make tls-check Verify HTTPS and certificate renewal"
	@echo "  make reset     Reset infrastructure (destructive)"
	@echo ""
	@echo "Aliases:"
	@echo "  make provision -> step-01"
	@echo "  make database  -> step-03"
	@echo "  make storage   -> step-04"

# Ansible setup
ansible-install:
	ANSIBLE_CONFIG=ansible.cfg ansible-galaxy install -r requirements.yml

$(GENERATED_CONFIG) &: group_vars/all/vars.yml group_vars/all/vault.yml templates/inventory.ini.j2 templates/known_hosts.j2 playbooks/render_deploy_config.yml .vault-password
	$(ANSIBLE_CONFIGURE_COMMAND)
	touch $(GENERATED_CONFIG)

ansible-configure: $(GENERATED_CONFIG)
	@echo "Ansible configuration is up to date."

# Project steps
step-01: ansible-configure
	$(ANSIBLE) playbooks/steps/step_01_infrastructure.yml

step-02: ansible-configure
	$(ANSIBLE) playbooks/steps/step_02_application.yml $(ANSIBLE_IMAGE_VARS)

step-03: ansible-configure
	$(ANSIBLE) playbooks/steps/step_03_database.yml $(ANSIBLE_IMAGE_VARS)

step-04: ansible-configure
	$(ANSIBLE) playbooks/steps/step_04_object_storage.yml $(ANSIBLE_IMAGE_VARS)

step-05: ansible-configure
	$(ANSIBLE) playbooks/steps/step_05_nginx.yml $(ANSIBLE_IMAGE_VARS)

nginx-install: ansible-configure
	$(ANSIBLE) playbooks/steps/step_05_nginx.yml --tags nginx-install

nginx-proxy: ansible-configure
	$(ANSIBLE) playbooks/steps/step_05_nginx.yml --tags nginx-proxy

nginx-cache: ansible-configure
	$(ANSIBLE) playbooks/steps/step_05_nginx.yml --tags nginx-cache

nginx-cache-check: ansible-configure
	$(ANSIBLE) playbooks/steps/step_05_nginx.yml --tags cache-smoke

step-06: ansible-configure
	$(ANSIBLE) playbooks/steps/step_06_https.yml $(ANSIBLE_IMAGE_VARS)

# Complete scenario
all: ansible-install ansible-configure
	$(ANSIBLE_ALL_COMMAND)

# Step aliases
provision: step-01
database: step-03
storage: step-04

# Production operations
deploy: ansible-configure
	$(ANSIBLE_DEPLOY_COMMAND)

ansible-check: ansible-configure
	$(ANSIBLE) playbooks/deploy.yml --check --diff --limit "$(ANSIBLE_LIMIT)" $(ANSIBLE_IMAGE_VARS)

smoke: ansible-configure
	$(ANSIBLE) playbooks/verify.yml --tags smoke --limit production

cache-check: ansible-configure
	$(ANSIBLE) playbooks/verify.yml --tags cache-smoke --limit production

tls-check: ansible-configure
	$(ANSIBLE) playbooks/verify.yml --tags tls-smoke --limit production

# Maintenance
reset: ansible-configure
	$(ANSIBLE) playbooks/reset.yml --tags reset --limit "$(RESET_LIMIT)" -e infrastructure_reset_confirm=true

vault-rekey:
	install -m 600 /dev/null .vault-password.new
	$(EDITOR) .vault-password.new
	ansible-vault rekey --vault-password-file .vault-password --new-vault-password-file .vault-password.new group_vars/all/vault.yml
	mv .vault-password.new .vault-password

.PHONY: help all ansible-install ansible-configure vault-rekey provision deploy ansible-check database storage smoke cache-check tls-check reset nginx-install nginx-proxy nginx-cache nginx-cache-check step-01 step-02 step-03 step-04 step-05 step-06
