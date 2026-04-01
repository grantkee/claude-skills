SKILLS_LOCAL := $(HOME)/.claude/skills
SKILLS_REPO  := skills

RSYNC_FLAGS := -av --exclude='.DS_Store' --exclude='__pycache__' --exclude='*.pyc'

.PHONY: help import import-clean install clean-install import-skill install-skill list diff

help: ## Show all targets with descriptions
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | awk -F ':.*## ' '{printf "  %-18s %s\n", $$1, $$2}'

import: ## Copy all local skills into the repo (additive)
	rsync $(RSYNC_FLAGS) $(SKILLS_LOCAL)/ $(SKILLS_REPO)/

import-clean: ## Mirror local skills into the repo (deletes extras)
	rsync $(RSYNC_FLAGS) --delete $(SKILLS_LOCAL)/ $(SKILLS_REPO)/

install: ## Copy repo skills to local skills directory (additive)
	rsync $(RSYNC_FLAGS) $(SKILLS_REPO)/ $(SKILLS_LOCAL)/

clean-install: ## Mirror repo skills to local (deletes extras) — prompts for confirmation
	@echo "This will DELETE any local skills not in the repo."
	@read -p "Continue? [y/N] " confirm && [ "$$confirm" = "y" ] || { echo "Aborted."; exit 1; }
	rsync $(RSYNC_FLAGS) --delete $(SKILLS_REPO)/ $(SKILLS_LOCAL)/

import-skill: ## Import a single skill (SKILL=name)
	@[ -n "$(SKILL)" ] || { echo "Usage: make import-skill SKILL=name"; exit 1; }
	@[ -d "$(SKILLS_LOCAL)/$(SKILL)" ] || { echo "Skill '$(SKILL)' not found in $(SKILLS_LOCAL)"; exit 1; }
	rsync $(RSYNC_FLAGS) $(SKILLS_LOCAL)/$(SKILL)/ $(SKILLS_REPO)/$(SKILL)/

install-skill: ## Install a single skill (SKILL=name)
	@[ -n "$(SKILL)" ] || { echo "Usage: make install-skill SKILL=name"; exit 1; }
	@[ -d "$(SKILLS_REPO)/$(SKILL)" ] || { echo "Skill '$(SKILL)' not found in $(SKILLS_REPO)"; exit 1; }
	rsync $(RSYNC_FLAGS) $(SKILLS_REPO)/$(SKILL)/ $(SKILLS_LOCAL)/$(SKILL)/

list: ## List skills in both locations
	@echo "=== Local ($(SKILLS_LOCAL)) ==="
	@ls -1 $(SKILLS_LOCAL) 2>/dev/null | grep -v '\.DS_Store' || echo "  (none)"
	@echo ""
	@echo "=== Repo ($(SKILLS_REPO)) ==="
	@ls -1 $(SKILLS_REPO) 2>/dev/null | grep -v '\.DS_Store' || echo "  (none)"

diff: ## Dry-run showing what import would change
	rsync $(RSYNC_FLAGS) --dry-run $(SKILLS_LOCAL)/ $(SKILLS_REPO)/
