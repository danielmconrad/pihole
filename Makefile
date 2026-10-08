-include .env

# Which Pi to talk to. Set these in .env; override per command, e.g. `make upgrade IP=192.168.1.3`.
#   IP   - the Pi's static address on its LAN; DNS checks query it from the Pi itself
#   HOST - where SSH connects (defaults to IP; set to a Tailscale name to work remotely)
#   NAME - the hostname `make setup` gives the Pi
IP      ?= 192.168.1.2
HOST    := $(or $(HOST),$(IP))
PI_USER ?= pi
TARGET  := $(PI_USER)@$(HOST)
# accept-new trusts a host the first time it's seen (e.g. the new static IP after
# setup) but still refuses one whose key has changed.
SSH_OPTS := -o StrictHostKeyChecking=accept-new
SSH     := ssh -t $(SSH_OPTS) $(TARGET)
REMOTE  := pihole-config
APT     := sudo DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold

.DEFAULT_GOAL := help
.PHONY: help setup ssh-key deploy push upgrade upgrade-os upgrade-pihole reboot gravity status check ssh wait

##----------------------------------------------------------------------------------------------------------------------
## Help

help:
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z0-9_-]+:.*?##/ { printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)
	@echo
	@echo "  Target Pi: $(TARGET), LAN IP $(IP)  (override with HOST=... IP=...)"

##----------------------------------------------------------------------------------------------------------------------
##@ Setup

setup: ## First-time setup: make setup HOST=<current address> (IP and NAME come from .env)
	@test -n "$(IP)" -a -n "$(NAME)" || { echo "Usage: make setup HOST=<current address> IP=<static ip> NAME=<hostname>"; exit 1; }
	@$(MAKE) --no-print-directory ssh-key
	@$(MAKE) --no-print-directory push
	$(SSH) 'sudo bash $(REMOTE)/scripts/setup.sh $(NAME) $(IP)'
	@echo "==> Rebooting onto $(IP)"
	-@ssh $(SSH_OPTS) $(TARGET) 'sudo systemctl reboot'
	@$(MAKE) --no-print-directory wait HOST=$(IP) IP=$(IP)
	@$(MAKE) --no-print-directory check HOST=$(IP) IP=$(IP)

ssh-key: ## Install your SSH public key on the Pi so commands stop asking for a password
	ssh-copy-id $(SSH_OPTS) $(TARGET)

deploy: push ## Push settings.conf/adlists.txt changes and apply them
	$(SSH) 'sudo bash $(REMOTE)/scripts/configure.sh'

push:
	@test -f .env || { echo "Missing .env; copy .env.example to .env and fill it in."; exit 1; }
	@ssh $(SSH_OPTS) $(TARGET) 'mkdir -p $(REMOTE)'
	@scp $(SSH_OPTS) -rq .env settings.conf adlists.txt scripts systemd $(TARGET):$(REMOTE)/
	@ssh $(SSH_OPTS) $(TARGET) 'chmod 600 $(REMOTE)/.env'

##----------------------------------------------------------------------------------------------------------------------
##@ Maintenance

upgrade: upgrade-os upgrade-pihole reboot ## Upgrade OS + kernel + Pi-hole, reboot, wait for DNS

upgrade-os: ## Upgrade OS packages and kernel (no reboot)
	$(SSH) 'sudo apt-get update && $(APT) full-upgrade && $(APT) autoremove'

upgrade-pihole: ## Upgrade Pi-hole (no reboot)
	$(SSH) 'sudo pihole -up'

reboot: ## Reboot and wait until DNS answers again
	-@ssh $(SSH_OPTS) $(TARGET) 'sudo systemctl reboot'
	@$(MAKE) --no-print-directory wait
	@$(MAKE) --no-print-directory check

gravity: ## Update blocklists now
	$(SSH) 'sudo pihole -g'

status: ## Pi-hole status, versions, next gravity run, reboot-required flag
	@$(SSH) 'pihole status; echo; pihole version; echo; \
		systemctl list-timers pihole-gravity.timer --no-pager; echo; \
		uptime; uname -r; \
		if [ -f /var/run/reboot-required ]; then echo "*** Reboot required ***"; fi'

check: ## Confirm the Pi resolves normal domains and blocks ad domains
	@ssh $(SSH_OPTS) $(TARGET) 'printf "  pi-hole.net     -> %s\n" "$$(dig +short +time=2 @$(IP) pi-hole.net | head -1)"; \
		printf "  doubleclick.net -> %s  (0.0.0.0 = blocked)\n" "$$(dig +short +time=2 @$(IP) doubleclick.net | head -1)"'

ssh: ## Open a shell on the Pi
	@ssh $(SSH_OPTS) $(TARGET)

wait:
	@echo "==> Waiting for $(HOST) to answer DNS on $(IP)"
	@sleep 20
	@until ssh $(SSH_OPTS) -o ConnectTimeout=5 -o BatchMode=yes $(TARGET) 'dig +short +time=2 +tries=1 @$(IP) pi-hole.net' 2>/dev/null | grep -qE '^[0-9]+\.'; do sleep 5; done
	@echo "==> $(HOST) is back"
