.PHONY: deploy deploy-scripts pull-full pull-selective status install-launchd uninstall-launchd install-cron ssh-setup help

SHELL := /bin/bash

# Load config
include config.env
export

help: ## Show this help
	@echo "Scotty — NAS Backup & Config Sync"
	@echo ""
	@grep -Eh '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

deploy: ## Deploy docker-compose files to NAS
	@echo "Deploying docker-compose files to $(NAS_SSH):$(NAS_COMPOSE_PATH)..."
	rsync -avz --checksum \
		docker-compose.yml docker-compose.env env.txt \
		$(NAS_SSH):$(NAS_COMPOSE_PATH)/
	@echo "Deploy complete. SSH into NAS and run 'docker compose pull && docker compose up -d' to apply."

deploy-scripts: ## Deploy NAS-side scripts to NAS
	@echo "Deploying scripts to $(NAS_SSH):$(NAS_SCRIPTS_PATH)..."
	ssh $(NAS_SSH) "mkdir -p $(NAS_SCRIPTS_PATH)"
	rsync -avz --checksum \
		scripts/nas/ $(NAS_SSH):$(NAS_SCRIPTS_PATH)/
	rsync -avz --checksum \
		config.env $(NAS_SSH):$(NAS_SCRIPTS_PATH)/config.env
	ssh $(NAS_SSH) "chmod +x $(NAS_SCRIPTS_PATH)/*.sh"
	@echo "Scripts deployed. Set up Synology Task Scheduler to run them nightly."

pull-full: ## Pull full backup from NAS (photos + docs + DSM config)
	scripts/client/pull-backup.sh --full

pull-selective: ## Pull selective backup from NAS (docs + DSM config, no photos)
	scripts/client/pull-backup.sh --selective

status: ## Check NAS connectivity and backup freshness
	@echo "Checking NAS connectivity..."
	@if ssh -o ConnectTimeout=5 -o BatchMode=yes $(NAS_SSH) true 2>/dev/null; then \
		echo "NAS: reachable"; \
		echo ""; \
		ssh $(NAS_SSH) "$(NAS_SCRIPTS_PATH)/backup-report.sh" 2>/dev/null || echo "  (backup-report.sh not yet deployed — run 'make deploy-scripts')"; \
	else \
		echo "NAS: NOT reachable"; \
	fi
	@echo ""
	@echo "--- Local Backup ---"
	@if [ -f "$(LOCAL_BACKUP_PATH)/.last-pull-backup" ]; then \
		LAST_TS=$$(cat "$(LOCAL_BACKUP_PATH)/.last-pull-backup"); \
		echo "Last pull: $$(date -r $$LAST_TS '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo 'unknown')"; \
	else \
		echo "Last pull: NEVER"; \
	fi
	@if [ -d "$(LOCAL_BACKUP_PATH)" ]; then \
		echo "Local backup size: $$(du -sh "$(LOCAL_BACKUP_PATH)" 2>/dev/null | cut -f1)"; \
	fi

install-launchd: ## Install macOS launchd plist for scheduled selective backups
	@echo "Installing launchd plist..."
	@mkdir -p $(HOME)/Library/LaunchAgents
	@sed "s|\$$HOME|$(HOME)|g" scripts/client/com.scotty.nas-backup.plist \
		> $(HOME)/Library/LaunchAgents/com.scotty.nas-backup.plist
	launchctl bootout gui/$$(id -u) $(HOME)/Library/LaunchAgents/com.scotty.nas-backup.plist 2>/dev/null || true
	launchctl bootstrap gui/$$(id -u) $(HOME)/Library/LaunchAgents/com.scotty.nas-backup.plist
	@echo "Installed. Runs every 6 hours. Check: launchctl list | grep scotty"

uninstall-launchd: ## Remove macOS launchd plist
	launchctl bootout gui/$$(id -u) $(HOME)/Library/LaunchAgents/com.scotty.nas-backup.plist 2>/dev/null || true
	rm -f $(HOME)/Library/LaunchAgents/com.scotty.nas-backup.plist
	@echo "Launchd plist removed."

install-cron: ## Print cron line for Desktop Linux (full backup every 4 hours)
	@echo "Add this line to crontab on Desktop Linux (crontab -e):"
	@echo ""
	@echo "  0 */4 * * * /path/to/scotty/scripts/client/pull-backup.sh --full"
	@echo ""
	@echo "Adjust the path to where you cloned the scotty repo."

ssh-setup: ## Copy SSH key to NAS (one-time setup)
	@echo "Setting up SSH key auth for $(NAS_SSH)..."
	@if [ ! -f $(HOME)/.ssh/id_ed25519.pub ]; then \
		echo "No ed25519 key found. Generating..."; \
		ssh-keygen -t ed25519 -f $(HOME)/.ssh/id_ed25519 -N ""; \
	fi
	ssh-copy-id $(NAS_SSH)
	@echo "Verifying..."
	ssh -o BatchMode=yes $(NAS_SSH) "echo 'SSH key auth works!'"
