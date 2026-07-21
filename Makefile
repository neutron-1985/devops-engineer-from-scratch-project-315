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
ANSIBLE_ROLLBACK_COMMAND = $(ANSIBLE) playbooks/rollback.yml --limit "$(ANSIBLE_LIMIT)"

# Help
help:
	@echo "Project steps:"
	@echo "  make step-01             Prepare and deploy the standalone application"
	@echo "    make application       Alias for step-01"
	@echo "  make step-02             Provision database hosts and PostgreSQL"
	@echo "    make database          Alias for step-02"
	@echo "  make step-03             Provision the selected object storage service"
	@echo "    make storage           Alias for step-03"
	@echo "  make step-04             Configure Nginx"
	@echo "    make nginx             Alias for step-04"
	@echo "    make nginx-install     Install and start Nginx"
	@echo "    make nginx-proxy       Configure the application reverse proxy"
	@echo "    make nginx-cache       Add static and upload caches"
	@echo "    make nginx-cache-check Verify the HTTP cache behavior"
	@echo "  make step-05             Run all HTTPS stages"
	@echo "    make https             Alias for step-05"
	@echo "    make cert              Issue the Let's Encrypt certificate"
	@echo "    make cert-renewal      Configure automatic certificate renewal"
	@echo "    make cert-https        Enable secure HTTPS and redirect"
	@echo ""
	@echo "Operations:"
	@echo "  make all       Run the complete five-step scenario"
	@echo "  make deploy    Deploy an application update"
	@echo "  make rollback  Swap the active application with its previous runtime"
	@echo "  make smoke     Verify database, object storage, and Nginx caches"
	@echo "  make cache-check Verify Nginx static and upload caches"
	@echo "  make tls-check Verify HTTPS and certificate renewal"
	@echo "  make reset     Reset infrastructure (destructive)"

# Ansible setup
ansible-install:
	ANSIBLE_CONFIG=ansible.cfg ansible-galaxy role install -r requirements.yml --roles-path roles/vendor
	ANSIBLE_CONFIG=ansible.cfg ansible-galaxy collection install -r requirements.yml

$(GENERATED_CONFIG) &: group_vars/all/vars.yml group_vars/all/vault.yml templates/inventory.ini.j2 templates/known_hosts.j2 playbooks/render_deploy_config.yml .vault-password
	$(ANSIBLE_CONFIGURE_COMMAND)
	touch $(GENERATED_CONFIG)

ansible-configure: $(GENERATED_CONFIG)
	@echo "Ansible configuration is up to date."

# Project steps
# Step 1 | Application
step-01: ansible-configure
	$(ANSIBLE) playbooks/steps/step_01_application.yml $(ANSIBLE_IMAGE_VARS)
application: step-01

# Step 2 | Database
step-02: ansible-configure
	$(ANSIBLE) playbooks/steps/step_02_database.yml $(ANSIBLE_IMAGE_VARS)
database: step-02

# Step 3 | Object storage
step-03: ansible-configure
	$(ANSIBLE) playbooks/steps/step_03_object_storage.yml $(ANSIBLE_IMAGE_VARS)
storage: step-03

# Step 4 | Nginx
step-04: ansible-configure
	$(ANSIBLE) playbooks/steps/step_04_nginx.yml $(ANSIBLE_IMAGE_VARS)
nginx: step-04

nginx-install: ansible-configure
	$(ANSIBLE) playbooks/steps/step_04_nginx.yml --tags nginx-install

nginx-proxy: ansible-configure
	$(ANSIBLE) playbooks/steps/step_04_nginx.yml --tags nginx-proxy

nginx-cache: ansible-configure
	$(ANSIBLE) playbooks/steps/step_04_nginx.yml --tags nginx-cache

nginx-cache-check: ansible-configure
	$(ANSIBLE) playbooks/steps/step_04_nginx.yml --tags cache-smoke

# Step 5 | HTTPS
step-05: ansible-configure
	$(ANSIBLE) playbooks/steps/step_05_https.yml
https: step-05

cert: ansible-configure
	$(ANSIBLE) playbooks/steps/step_05_https.yml --tags tls-certificate

cert-renewal: ansible-configure
	$(ANSIBLE) playbooks/steps/step_05_https.yml --tags tls-renewal

cert-https: ansible-configure
	$(ANSIBLE) playbooks/steps/step_05_https.yml --tags tls-nginx

# Complete scenario
all: ansible-install ansible-configure
	$(ANSIBLE_ALL_COMMAND)

# Production operations
deploy: ansible-configure
	$(ANSIBLE_DEPLOY_COMMAND)

rollback: ansible-configure
	$(ANSIBLE_ROLLBACK_COMMAND)

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

.PHONY: help ansible-install ansible-configure step-01 application step-02 database step-03 storage step-04 nginx nginx-install nginx-proxy nginx-cache nginx-cache-check step-05 https cert cert-renewal cert-https all deploy rollback ansible-check smoke cache-check tls-check reset vault-rekey
