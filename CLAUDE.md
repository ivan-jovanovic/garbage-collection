# Garbage Collection Pipeline

This is a standalone, language-agnostic code cleanup tool that uses Claude Code and optionally Codex to find and remove dead code, simplify complexity, and clean up technical debt.

## Project Structure

```
gc.sh                          # Main pipeline script
gc.example.yml                 # Reference config (copy to your project as gc.yml)
examples/                      # Pre-made configs for Python, Node, Go
.claude/commands/              # Claude Code slash commands (usable interactively)
  gc.md                        # /gc — analyze dead code, duplication, complexity
  self-review.md               # /self-review — self-evaluate your own work
  ask-for-code-review.md       # /ask-for-code-review — get Codex to review changes
  consult-idea.md              # /consult-idea — get Codex second opinion on an idea
```

## How It Works

`gc.sh` reads a `gc.yml` config from the target project, discovers files via glob patterns, and processes each file through a 6-step pipeline:

1. **GC Analysis** (read-only) — dead code, duplication, complexity, stale comments
2. **Second opinion** — Codex reviews findings (optional)
3. **Make changes** — behavior-preserving cleanup
4. **Self-review** — Claude reviews its own diff
5. **Code review** — Codex reviews the diff (optional)
6. **Gate + commit** — runs test suite, commits per-file

## Usage

The script is meant to be run from inside the target project (which has a `gc.yml`):

```bash
/path/to/gc.sh --dry-run         # Preview files
/path/to/gc.sh                   # Run pipeline
/path/to/gc.sh --skip-codex      # Without Codex
/path/to/gc.sh --group api       # Target a file group
/path/to/gc.sh --file src/foo.py # Single file
```

## Slash Commands

The `.claude/commands/` directory contains interactive commands. When working inside this project (or any project that symlinks these commands), they're available as `/gc`, `/review`, `/self-review`, etc.
