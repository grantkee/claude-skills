# Claude Skills

Consolidated Claude Code skills synced across devices.

## Setup

```bash
git clone git@github.com:grantkee/claude-skills.git
cd claude-skills
```

## Usage

### Import skills from local machine into the repo

```bash
make import              # additive — keeps extras in repo
make import-clean        # mirror — repo matches local exactly
make import-skill SKILL=review   # single skill
```

### Install skills from the repo to local machine

```bash
make install             # additive — keeps extras locally
make clean-install       # mirror — local matches repo exactly (prompts first)
make install-skill SKILL=review  # single skill
```

### Inspect

```bash
make list    # show skills in both locations
make diff    # dry-run of what import would change
make help    # all available targets
```

## Typical Workflow

**Primary device** — where you author/edit skills:

```bash
# edit skills in ~/.claude/skills/ as usual, then:
make import
git add -A && git commit -m "update skills" && git push
```

**Secondary device** — pull and install:

```bash
git pull
make install
```

## Directory Structure

```
claude-skills/
├── skills/          # synced skills (one subdirectory per skill)
│   ├── debug-e2e/
│   ├── review/
│   └── skill-creator/
├── Makefile         # sync tooling
└── README.md
```
