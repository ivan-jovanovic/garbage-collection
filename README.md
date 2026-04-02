# Garbage Collection Pipeline

`gc.sh` is a standalone, language-agnostic code cleanup pipeline that uses **Claude Code** (and optionally **Codex**) to find and remove dead code, simplify complexity, and clean up technical debt.

## Core Purpose

The tool addresses a fundamental question: "What dead code, duplication, and unnecessary complexity has accumulated in this codebase, and how do I clean it up safely — file by file, with verification at every step?"

## Key Features

**6-Step Pipeline**: Each matched file is processed through a full cleanup cycle:
1. **GC Analysis** — Dead code, duplication, complexity, stale comments (read-only)
2. **Second opinion** — Codex reviews the findings (optional, skippable)
3. **Make changes** — Executes the action plan (behavior-preserving only)
4. **Self-review** — Claude reviews its own diff and fixes issues
5. **Code review** — Codex reviews the diff (optional, skippable)
6. **Gate + commit** — Runs your test suite, then commits that iteration's changes

**What Gets Analyzed**: The pipeline scans for unused functions, methods, variables, and imports; duplicated logic across the full project; over-abstraction and premature generalization; stale comments and TODOs; and inconsistent patterns.

**Configuration**: All settings live in a `gc.yml` file in your project root:
- Named file groups with glob patterns and exclusions
- Quality gate command (test suite)
- Codex integration toggle
- Commit behavior (auto-commit, prefix, scope derivation)
- Advanced tuning for timeouts and max turns

## Usage

```bash
# 1. Create a gc.yml config in your project
cp /path/to/garbage-collection/gc.example.yml ./gc.yml

# 2. Preview what files will be processed
/path/to/gc.sh --dry-run

# 3. Run the pipeline
/path/to/gc.sh

# Target a specific file group
/path/to/gc.sh --group api

# Target a file or directory directly
/path/to/gc.sh --path src/utils/parser.py
/path/to/gc.sh --path controllers

# Skip Codex steps
/path/to/gc.sh --skip-codex

# Leave changes uncommitted
/path/to/gc.sh --no-commit

# Resume from a specific file
/path/to/gc.sh --path controllers --resume-from controllers/user_controller.py

# Background execution
nohup /path/to/gc.sh > gc.log 2>&1 &
```

## Output Includes

- A dedicated branch with one commit per processed file
- Per-file logs in `.gc-logs/<timestamp>/` with JSON output and stderr for every step
- A final full gate run verifying all changes work together
- A summary of succeeded and failed files with next-step instructions

**Interactive slash commands** are also available for ad-hoc use. Symlink `.claude/commands/` into your project to access `/gc`, `/self-review`, `/ask-for-code-review`, and `/consult-idea` during a Claude Code conversation.

## Requirements

- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) (`claude`)
- [`yq`](https://github.com/mikefarah/yq) for YAML parsing (`brew install yq`)
- [`jq`](https://stedolan.github.io/jq/) for JSON parsing (`brew install jq`)
- [Codex](https://github.com/openai/codex) (optional — `npm install -g @openai/codex`)

## Current Limitations

- All changes are strictly **behavior-preserving**. The pipeline does not add features, refactor architecture, or change how anything works.
- Cross-file duplication is **detected** across the full project but only **acted on** within the target scope. Consolidation across module boundaries is flagged for manual follow-up.
- The pipeline requires a **clean git working tree**. Commit or stash local changes before running.
- Pre-made example configs exist for Python, Node, and Go (`examples/`), but the tool works with any language.
