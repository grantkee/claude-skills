SKILLS_LOCAL := $(HOME)/.claude/skills
SKILLS_REPO  := skills
AGENTS_LOCAL := $(HOME)/.claude/agents
AGENTS_REPO  := agents
AGENT_MEMORY := $(HOME)/.claude/agent-memory
CLAUDE_LOCAL := $(HOME)/.claude/CLAUDE.md
CLAUDE_REPO  := CLAUDE.md

RSYNC_FLAGS := -av --exclude='.DS_Store' --exclude='__pycache__' --exclude='*.pyc'

.PHONY: help import import-clean install clean-install import-skill install-skill \
        import-agents install-agents import-config install-config list diff

help: ## Show all targets with descriptions
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | awk -F ':.*## ' '{printf "  %-18s %s\n", $$1, $$2}'

import: ## Import all local skills, agents, and config into the repo (additive)
	rsync $(RSYNC_FLAGS) $(SKILLS_LOCAL)/ $(SKILLS_REPO)/
	rsync $(RSYNC_FLAGS) $(AGENTS_LOCAL)/ $(AGENTS_REPO)/
	cp $(CLAUDE_LOCAL) $(CLAUDE_REPO)

import-clean: ## Mirror local skills, agents, and config into the repo (deletes extras)
	rsync $(RSYNC_FLAGS) --delete $(SKILLS_LOCAL)/ $(SKILLS_REPO)/
	rsync $(RSYNC_FLAGS) --delete $(AGENTS_LOCAL)/ $(AGENTS_REPO)/
	cp $(CLAUDE_LOCAL) $(CLAUDE_REPO)

install: ## Install repo skills, agents, and config to local (additive)
	rsync $(RSYNC_FLAGS) $(SKILLS_REPO)/ $(SKILLS_LOCAL)/
	mkdir -p $(AGENTS_LOCAL)
	rsync $(RSYNC_FLAGS) $(AGENTS_REPO)/ $(AGENTS_LOCAL)/
	cp $(CLAUDE_REPO) $(CLAUDE_LOCAL)
	@for agent in $(AGENTS_REPO)/*.md; do \
		name=$$(basename "$$agent" .md); \
		mkdir -p "$(AGENT_MEMORY)/$$name"; \
	done

clean-install: ## Mirror repo to local for all components (deletes extras) — prompts for confirmation
	@echo "This will DELETE any local skills/agents not in the repo and overwrite CLAUDE.md."
	@read -p "Continue? [y/N] " confirm && [ "$$confirm" = "y" ] || { echo "Aborted."; exit 1; }
	rsync $(RSYNC_FLAGS) --delete $(SKILLS_REPO)/ $(SKILLS_LOCAL)/
	mkdir -p $(AGENTS_LOCAL)
	rsync $(RSYNC_FLAGS) --delete $(AGENTS_REPO)/ $(AGENTS_LOCAL)/
	cp $(CLAUDE_REPO) $(CLAUDE_LOCAL)
	@for agent in $(AGENTS_REPO)/*.md; do \
		name=$$(basename "$$agent" .md); \
		mkdir -p "$(AGENT_MEMORY)/$$name"; \
	done

import-skill: ## Import a single skill (SKILL=name)
	@[ -n "$(SKILL)" ] || { echo "Usage: make import-skill SKILL=name"; exit 1; }
	@[ -d "$(SKILLS_LOCAL)/$(SKILL)" ] || { echo "Skill '$(SKILL)' not found in $(SKILLS_LOCAL)"; exit 1; }
	rsync $(RSYNC_FLAGS) $(SKILLS_LOCAL)/$(SKILL)/ $(SKILLS_REPO)/$(SKILL)/

install-skill: ## Install a single skill (SKILL=name)
	@[ -n "$(SKILL)" ] || { echo "Usage: make install-skill SKILL=name"; exit 1; }
	@[ -d "$(SKILLS_REPO)/$(SKILL)" ] || { echo "Skill '$(SKILL)' not found in $(SKILLS_REPO)"; exit 1; }
	rsync $(RSYNC_FLAGS) $(SKILLS_REPO)/$(SKILL)/ $(SKILLS_LOCAL)/$(SKILL)/

import-agents: ## Import agents from local to repo
	rsync $(RSYNC_FLAGS) $(AGENTS_LOCAL)/ $(AGENTS_REPO)/

install-agents: ## Install agents from repo to local
	mkdir -p $(AGENTS_LOCAL)
	rsync $(RSYNC_FLAGS) $(AGENTS_REPO)/ $(AGENTS_LOCAL)/

import-config: ## Import CLAUDE.md from local to repo
	cp $(CLAUDE_LOCAL) $(CLAUDE_REPO)

install-config: ## Install CLAUDE.md from repo to local
	cp $(CLAUDE_REPO) $(CLAUDE_LOCAL)

list: ## List skills and agents in both locations
	@echo "=== Skills: Local ($(SKILLS_LOCAL)) ==="
	@ls -1 $(SKILLS_LOCAL) 2>/dev/null | grep -v '\.DS_Store' || echo "  (none)"
	@echo ""
	@echo "=== Skills: Repo ($(SKILLS_REPO)) ==="
	@ls -1 $(SKILLS_REPO) 2>/dev/null | grep -v '\.DS_Store' || echo "  (none)"
	@echo ""
	@echo "=== Agents: Local ($(AGENTS_LOCAL)) ==="
	@ls -1 $(AGENTS_LOCAL) 2>/dev/null | grep -v '\.DS_Store' || echo "  (none)"
	@echo ""
	@echo "=== Agents: Repo ($(AGENTS_REPO)) ==="
	@ls -1 $(AGENTS_REPO) 2>/dev/null | grep -v '\.DS_Store' || echo "  (none)"

diff: ## Dry-run showing what import would change for all components
	@echo "--- Skills ---"
	rsync $(RSYNC_FLAGS) --dry-run $(SKILLS_LOCAL)/ $(SKILLS_REPO)/
	@echo ""
	@echo "--- Agents ---"
	rsync $(RSYNC_FLAGS) --dry-run $(AGENTS_LOCAL)/ $(AGENTS_REPO)/ 2>/dev/null || echo "  (no local agents directory)"
	@echo ""
	@echo "--- CLAUDE.md ---"
	@diff $(CLAUDE_LOCAL) $(CLAUDE_REPO) || true
