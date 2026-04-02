---
description: Garbage collection - clean up technical debt and entropy
allowed-tools: bash
argument-hint: "[file, directory, or 'all']"
---

# Garbage Collection — Clean Up Technical Debt

You are performing a focused cleanup pass on the codebase. Your goal is to reduce entropy and technical debt by removing what's not needed and simplifying what's left. This is strictly a behavior-preserving operation — nothing should work differently after your changes.

## Scope

Determine what to review:
- If the user provided a file or directory as $ARGUMENTS, focus on that
- If the user passed "all", review the main source directories of the project
- If nothing was provided, ask the user what to target

## Analysis

Go through the target files carefully and check for the following:

### 1. Dead Code

- **Unused functions, methods, classes, or variables** — defined but never called or referenced
- **Unused imports** — imported but never used in the file
- **Dead exports** — exported from a module but never imported anywhere else in the project
- **Commented-out code** — old code left in comments that serves no purpose
- **Dead dependencies** — packages in dependency files (package.json, requirements.txt, go.mod, etc.) that are installed but never imported anywhere in the codebase

### 2. Duplication and Pattern Inconsistency

- **Duplicated logic** — similar or identical code blocks that could be consolidated into a single function or utility
- **Inconsistent patterns** — different ways of doing the same thing across the codebase:
  - Import styles (default vs named, relative vs absolute paths)
  - How external services/APIs are called (direct fetch vs wrapper, different HTTP clients)
  - Error handling approaches (try/catch vs .catch, different error formats)
  - Logging patterns (different loggers, inconsistent log levels or formats)
  - Configuration access (env vars read directly vs config module)
- Identify which pattern is the dominant/preferred one and flag the outliers

### 3. Unnecessary Complexity

- **Over-abstraction** — wrapper classes, factories, or patterns that add indirection without adding value
- **Premature generalization** — code built to handle cases that don't exist and may never exist
- **Overly clever code** — complex one-liners or convoluted logic that could be written more simply
- **Unnecessary intermediate variables, transformations, or layers**
- **Functions that do too much** — could be simplified by removing responsibilities that don't belong

### 4. Stale Comments and TODOs

- **Outdated comments** — comments that describe behavior the code no longer has
- **Stale TODOs** — TODO/FIXME/HACK comments referencing old issues, completed work, or things no longer relevant
- **Redundant comments** — comments that just restate what the code obviously does

## Report

Present your findings organized by confidence:

### Safe to Remove
Items that are clearly dead or unused. No risk of breakage.

### Simplify
Code that works but is more complex than it needs to be. Include a brief description of how to simplify it.

### Inconsistent Patterns
List each inconsistency found, which pattern is dominant, and which files are the outliers.

### Verify Before Removing
Items that appear unused but might be referenced dynamically, via reflection, or from outside the codebase (e.g., API endpoints, CLI handlers, template references). These need manual verification.

## Important Constraints

- **This is behavior-preserving only.** Do not change how anything works.
- **Do not refactor for style.** Formatting and naming conventions are not in scope unless they are part of a pattern inconsistency.
- **Present findings first.** Do not make any changes until the user reviews and approves.
- **Be specific.** Include file names, line numbers, and code snippets for every finding.
