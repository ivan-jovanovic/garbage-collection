# Garbage Collection Pipeline

Automated code cleanup pipeline that uses **Claude Code** (and optionally **Codex**) to find and remove dead code, simplify complexity, and clean up technical debt — file by file, with safety gates at every step.

## How it works

For each file matched by your glob patterns, the pipeline runs 6 steps:

1. **GC Analysis** — Dead code, duplication, complexity, stale comments (read-only)
2. **Second opinion** — Codex reviews the findings (optional, skippable)
3. **Make changes** — Executes the action plan (behavior-preserving only)
4. **Self-review** — Claude reviews its own diff and fixes issues
5. **Code review** — Codex reviews the diff (optional, skippable)
6. **Gate + report** — Runs your test suite and leaves changes uncommitted for review

Changes stay in your working tree. A final gate run verifies everything works together.

## Requirements

- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) (`claude`)
- [`yq`](https://github.com/mikefarah/yq) for YAML parsing (`brew install yq`)
- [`jq`](https://stedolan.github.io/jq/) for JSON parsing (`brew install jq`)
- [Codex](https://github.com/openai/codex) (optional — `npm install -g @openai/codex`)

## Quick start

```bash
# 1. Clone this repo
git clone <repo-url> ~/garbage-collection

# 2. Go to your project
cd /path/to/your-project

# 3. Create a gc.yml config (copy an example and edit it)
cp ~/garbage-collection/gc.example.yml ./gc.yml
# edit gc.yml for your project...

# 4. Preview what files will be processed
~/garbage-collection/gc.sh --dry-run

# 5. Run the pipeline
~/garbage-collection/gc.sh
```

## Configuration

All settings live in a `gc.yml` file in your project root. See [`gc.example.yml`](gc.example.yml) for the full reference.

Use `gc.yml` for project defaults and policy:
- file groups and exclusions
- the verification command
- default Codex usage

Use CLI flags for run-specific choices:
- which path or named group to target
- dry-run vs execute
- temporary overrides like skipping Codex
- resuming from a later file in the list

### Minimal config

```yaml
files:
  default:
    - "src/**/*.py"

gate:
  command: "pytest"

codex:
  enabled: false
```

Advanced tuning such as `timeouts.*` and `max_turns.*` is supported, but it is intentionally omitted from the minimal example. Most projects should rely on the built-in defaults unless they have a concrete runtime issue to solve.

The pipeline is intended to run in a clean git working tree. It uses `git diff` for self-review, optional Codex review, and final reporting.

### File groups

Define named scopes for directories or mixed file sets you run often, then target them with `--group`:

```yaml
files:
  default:
    - "src/**/*.py"
  api:
    - "api/**/*.py"
    - "api/**/*.ts"
  workers:
    - "workers/**/*.py"
```

```bash
gc.sh --group api       # Only process api files
gc.sh --group workers   # Only process worker files
gc.sh                   # Uses "default" group
```

### Direct path targeting

For one-off runs, target a file or directory directly with `--path`:

```bash
gc.sh --path controllers
gc.sh --path controllers/user_controller.py
gc.sh --path src/api/controllers --dry-run
```

If `--path` points to a directory, the script recursively collects files under it and still applies `exclude` rules from `gc.yml`. `--path` and `--group` are mutually exclusive.

### Exclude patterns

```yaml
exclude:
  - "**/__init__.py"
  - "**/node_modules/**"
  - "**/*.test.*"
```

## Usage

```
gc.sh [OPTIONS]

Options:
  --config <path>         Path to gc.yml (default: ./gc.yml)
  --path <path>           Process a file or recursively process a directory
  --group <name>          File group from config (default: "default")
  --file <path>           Deprecated alias for --path <file>
  --dry-run               Preview file list, don't execute
  --skip-codex            Skip Codex second-opinion and review steps
  --resume-from <path>    Start from a specific file in the resolved file list
  -h, --help              Show help
```

### Examples

```bash
# Dry run to see what would be processed
gc.sh --dry-run

# Run on default file group, no Codex
gc.sh --skip-codex

# Run on a directory directly
gc.sh --path controllers

# Run on a single file directly
gc.sh --path src/utils/parser.py

# Run on the "api" group
gc.sh --group api

# Resume from a later file in a directory run
gc.sh --path controllers --resume-from controllers/user_controller.py

# Background execution
nohup gc.sh > gc.log 2>&1 &
# or
tmux new -d -s gc 'gc.sh'
```

## Examples

Pre-made configs for common project types:

- [`examples/python.yml`](examples/python.yml)
- [`examples/node.yml`](examples/node.yml)
- [`examples/go.yml`](examples/go.yml)

## What it does NOT do

- Change behavior. All changes are strictly behavior-preserving.
- Touch formatting or style. No reformatting, no renaming.
- Add code. No new abstractions, no new comments, no new tests.
- Create commits or branches in v0.1. You review and commit manually.

## Future work

Planned but intentionally omitted from v0.1:

- Optional automated commit support, potentially including per-file commits after the workflow is validated in real usage.

## Interactive slash commands

The repo ships with Claude Code commands in `.claude/commands/` that you can use interactively during a conversation. To make them available in your project, symlink the directory:

```bash
# From your project root
ln -s /path/to/garbage-collection/.claude/commands .claude/commands/gc
```

Then in Claude Code you can use:

| Command | Description |
|---|---|
| `/gc [file\|dir\|all]` | Analyze dead code, duplication, complexity |
| `/self-review` | Self-evaluate work done in this session |
| `/ask-for-code-review` | Get Codex to review your uncommitted changes |
| `/consult-idea` | Get Codex second opinion on an idea |

These are the same prompts the pipeline script uses internally, exposed for ad-hoc use.

## Logs

All pipeline output is saved to `.gc-logs/<timestamp>/` in your project directory. This directory is automatically added to `.gitignore`.

Each file gets a subdirectory with JSON output and stderr logs for every step, useful for debugging failures or reviewing what Claude found.
