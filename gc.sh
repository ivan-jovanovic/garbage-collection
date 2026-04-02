#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────
# gc.sh — Standalone GC + multi-review cleanup pipeline
#
# Reads gc.yml from the target project to discover files via glob
# patterns, then processes each file through:
#   1. GC analysis (dead code, duplication, complexity, stale comments)
#   2. Codex second opinion on findings (optional)
#   3. Make changes based on combined feedback
#   4. Self-review + fix
#   5. Codex code review + fix (optional)
#   6. Gate + report
#
# Usage:
#   /path/to/gc.sh                              # Uses ./gc.yml, default group
#   /path/to/gc.sh --group api                  # Target a specific file group
#   /path/to/gc.sh --path controllers           # Target a directory directly
#   /path/to/gc.sh --path src/lib/utils.py      # Target a file directly
#   /path/to/gc.sh --config path/to/gc.yml      # Explicit config path
#   /path/to/gc.sh --dry-run                    # Preview file list only
#   /path/to/gc.sh --skip-codex                 # Skip Codex steps
#   /path/to/gc.sh --resume-from src/foo.py     # Start from a specific file
#
# Background execution:
#   nohup /path/to/gc.sh > gc-pipeline.log 2>&1 &
#   tmux new -d -s gc '/path/to/gc.sh'
# ──────────────────────────────────────────────────────────────────
set -eo pipefail

# ── Resolve script location ────────────────────────────────────
GC_HOME="$(cd "$(dirname "$0")" && pwd)"

# ── Portable timeout (macOS has no GNU timeout) ────────────────
if ! command -v timeout &>/dev/null; then
    timeout() {
        local secs="$1"; shift
        "$@" &
        local cmd_pid=$!
        ( sleep "$secs" && kill -TERM "$cmd_pid" 2>/dev/null ) &
        local watcher_pid=$!
        wait "$cmd_pid" 2>/dev/null
        local rc=$?
        kill "$watcher_pid" 2>/dev/null
        wait "$watcher_pid" 2>/dev/null
        [[ $rc -eq 143 ]] && return 124
        return $rc
    }
fi

# ── Portable mapfile (macOS ships Bash 3.2) ────────────────────
if ! declare -F mapfile >/dev/null 2>&1; then
    mapfile() {
        local trim_newlines=false
        local array_name="$1"
        local line
        local i=0

        if [[ "$1" == "-t" ]]; then
            trim_newlines=true
            array_name="$2"
        fi

        eval "$array_name=()"
        while IFS= read -r line; do
            local quoted_line
            quoted_line=$(printf '%q' "$line")
            eval "${array_name}[${i}]=$quoted_line"
            i=$((i + 1))
        done
    }
fi

# ── Defaults ───────────────────────────────────────────────────
CONFIG_FILE="gc.yml"
GROUP="default"
DRY_RUN=false
SKIP_CODEX=false
SINGLE_FILE=""
PATH_TARGET=""
RESUME_FROM=""

# ── Parse arguments ────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --config)       CONFIG_FILE="$2"; shift 2 ;;
        --group)        GROUP="$2"; shift 2 ;;
        --path)         PATH_TARGET="$2"; shift 2 ;;
        --file)         SINGLE_FILE="$2"; shift 2 ;;
        --dry-run)      DRY_RUN=true; shift ;;
        --skip-codex)   SKIP_CODEX=true; shift ;;
        --resume-from)  RESUME_FROM="$2"; shift 2 ;;
        -h|--help)
            cat <<'EOF'
gc.sh [OPTIONS]

Target selection:
  --path <path>           Process a file or recursively process a directory
  --group <name>          File group from config (default: "default")
                          If neither is given, uses files.default from gc.yml

Run controls:
  --config <path>         Path to gc.yml (default: ./gc.yml)
  --dry-run               Preview file list, don't execute
  --skip-codex            Skip Codex second-opinion and review steps
  --resume-from <path>    Start from a specific file in the resolved file list
  --file <path>           Deprecated alias for --path <file>
  -h, --help              Show help
EOF
            exit 0
            ;;
        *) echo "Unknown argument: $1"; exit 1 ;;
    esac
done

# ── Pre-flight checks ─────────────────────────────────────────
check_cmd() {
    if ! command -v "$1" &>/dev/null; then
        echo "ERROR: '$1' not found in PATH. $2"
        exit 1
    fi
}

check_cmd claude "Install: https://docs.anthropic.com/en/docs/claude-code"
check_cmd yq     "Install: brew install yq / pip install yq"

if [[ "$SKIP_CODEX" == false ]]; then
    check_cmd codex "Install: npm install -g @openai/codex — or use --skip-codex"
fi

# ── Locate and validate config ─────────────────────────────────
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "ERROR: Config file not found: $CONFIG_FILE"
    echo ""
    echo "Create one by copying the example:"
    echo "  cp ${GC_HOME}/gc.example.yml ./gc.yml"
    echo ""
    echo "Then edit it for your project."
    exit 1
fi

CONFIG_FILE="$(cd "$(dirname "$CONFIG_FILE")" && pwd)/$(basename "$CONFIG_FILE")"
PROJECT_DIR="$(dirname "$CONFIG_FILE")"
cd "$PROJECT_DIR"

echo "Project: $PROJECT_DIR"
echo "Config:  $CONFIG_FILE"

if [[ -n "$PATH_TARGET" && -n "$SINGLE_FILE" ]]; then
    echo "ERROR: Use either --path or --file, not both."
    exit 1
fi

if [[ -n "$PATH_TARGET" && "$GROUP" != "default" ]]; then
    echo "ERROR: Use either --path or --group, not both."
    exit 1
fi

if [[ -n "$SINGLE_FILE" && "$GROUP" != "default" ]]; then
    echo "ERROR: Use either --file or --group, not both."
    exit 1
fi

if [[ -n "$SINGLE_FILE" ]]; then
    echo "WARNING: --file is deprecated; use --path instead."
    PATH_TARGET="$SINGLE_FILE"
fi

# ── Parse config ───────────────────────────────────────────────
yq_read() {
    yq eval "$1" "$CONFIG_FILE"
}

yq_read_default() {
    local val
    val=$(yq eval "$1" "$CONFIG_FILE")
    if [[ "$val" == "null" || -z "$val" ]]; then
        echo "$2"
    else
        echo "$val"
    fi
}

# Timeouts
STEP_TIMEOUT=$(yq_read_default '.timeouts.step' '600')
CODEX_TIMEOUT=$(yq_read_default '.timeouts.codex' '120')

# Max turns
MAX_TURNS_ANALYSIS=$(yq_read_default '.max_turns.analysis' '25')
MAX_TURNS_CODEX=$(yq_read_default '.max_turns.codex' '15')
MAX_TURNS_CHANGES=$(yq_read_default '.max_turns.changes' '30')
MAX_TURNS_REVIEW=$(yq_read_default '.max_turns.review' '25')
MAX_TURNS_GATE=$(yq_read_default '.max_turns.gate' '20')

# Gate
GATE_COMMAND=$(yq_read_default '.gate.command' '')
GATE_REQUIRED=$(yq_read_default '.gate.required' 'true')

# Codex
CODEX_ENABLED=$(yq_read_default '.codex.enabled' 'true')
[[ "$SKIP_CODEX" == true ]] && CODEX_ENABLED=false

# ── Discover files from globs ──────────────────────────────────
discover_files() {
    local group="$1"
    local pattern_count
    pattern_count=$(yq eval ".files.${group} | length" "$CONFIG_FILE")

    if [[ "$pattern_count" == "0" || "$pattern_count" == "null" ]]; then
        echo "ERROR: No file group '${group}' found in config." >&2
        echo "Available groups:" >&2
        yq eval '.files | keys | .[]' "$CONFIG_FILE" >&2
        return 1
    fi

    # Collect exclude patterns
    local exclude_args=()
    local exclude_count
    exclude_count=$(yq eval '.exclude | length' "$CONFIG_FILE" 2>/dev/null || echo "0")
    if [[ "$exclude_count" != "0" && "$exclude_count" != "null" ]]; then
        for i in $(seq 0 $((exclude_count - 1))); do
            local ex_pattern
            ex_pattern=$(yq eval ".exclude[$i]" "$CONFIG_FILE")
            exclude_args+=(! -path "$ex_pattern")
        done
    fi

    # Expand each glob pattern
    local all_files=()
    for i in $(seq 0 $((pattern_count - 1))); do
        local pattern
        pattern=$(yq eval ".files.${group}[$i]" "$CONFIG_FILE")

        # Use find with the glob pattern
        while IFS= read -r f; do
            [[ -n "$f" ]] && all_files+=("$f")
        done < <(find . -type f -path "./$pattern" "${exclude_args[@]}" 2>/dev/null | sed 's|^\./||' | sort)
    done

    # Deduplicate and sort
    printf '%s\n' "${all_files[@]}" | sort -u
}

is_excluded_file() {
    local rel_path="$1"
    local exclude_count

    exclude_count=$(yq eval '.exclude | length' "$CONFIG_FILE" 2>/dev/null || echo "0")
    if [[ "$exclude_count" == "0" || "$exclude_count" == "null" ]]; then
        return 1
    fi

    for i in $(seq 0 $((exclude_count - 1))); do
        local ex_pattern
        ex_pattern=$(yq eval ".exclude[$i]" "$CONFIG_FILE")
        if [[ "$rel_path" == $ex_pattern ]]; then
            return 0
        fi
    done

    return 1
}

normalize_target_path() {
    local input="$1"
    local abs_path

    if [[ "$input" == /* ]]; then
        abs_path="$input"
    else
        abs_path="$PROJECT_DIR/$input"
    fi

    if [[ ! -e "$abs_path" ]]; then
        echo "ERROR: Path not found: $input" >&2
        return 1
    fi

    abs_path="$(cd "$(dirname "$abs_path")" && pwd)/$(basename "$abs_path")"

    case "$abs_path" in
        "$PROJECT_DIR")
            echo "."
            ;;
        "$PROJECT_DIR"/*)
            echo "${abs_path#$PROJECT_DIR/}"
            ;;
        *)
            echo "ERROR: Path must be inside the project directory: $input" >&2
            return 1
            ;;
    esac
}

discover_path_files() {
    local input="$1"
    local rel_target
    local exclude_args=()
    local exclude_count

    rel_target=$(normalize_target_path "$input") || return 1

    if [[ -f "$rel_target" ]]; then
        if is_excluded_file "$rel_target"; then
            echo "ERROR: Path is excluded by config: $rel_target" >&2
            return 1
        fi

        printf '%s\n' "$rel_target"
        return 0
    fi

    if [[ ! -d "$rel_target" ]]; then
        echo "ERROR: Path is neither a file nor a directory: $input" >&2
        return 1
    fi

    exclude_count=$(yq eval '.exclude | length' "$CONFIG_FILE" 2>/dev/null || echo "0")
    if [[ "$exclude_count" != "0" && "$exclude_count" != "null" ]]; then
        for i in $(seq 0 $((exclude_count - 1))); do
            local ex_pattern
            ex_pattern=$(yq eval ".exclude[$i]" "$CONFIG_FILE")
            exclude_args+=(! -path "$ex_pattern")
        done
    fi

    find "$rel_target" -type f "${exclude_args[@]}" 2>/dev/null | sed 's|^\./||' | sort -u
}

if [[ -n "$PATH_TARGET" ]]; then
    mapfile -t FILES < <(discover_path_files "$PATH_TARGET")
    TARGET_MODE="path"
    TARGET_LABEL="$PATH_TARGET"
else
    mapfile -t FILES < <(discover_files "$GROUP")
    TARGET_MODE="group"
    TARGET_LABEL="$GROUP"
fi

if [[ ${#FILES[@]} -eq 0 ]]; then
    if [[ "$TARGET_MODE" == "path" ]]; then
        echo "ERROR: No files matched for path '${TARGET_LABEL}'."
        echo "Check that the path exists and is not excluded by gc.yml."
    else
        echo "ERROR: No files matched for group '${GROUP}'."
        echo "Check your glob patterns in gc.yml."
    fi
    exit 1
fi

# Handle --resume-from
if [[ -n "$RESUME_FROM" ]]; then
    SKIP=true
    FILTERED=()
    for f in "${FILES[@]}"; do
        [[ "$f" == "$RESUME_FROM" ]] && SKIP=false
        [[ "$SKIP" == false ]] && FILTERED+=("$f")
    done
    FILES=("${FILTERED[@]}")
    echo "Resuming from $RESUME_FROM (${#FILES[@]} files remaining)"
fi

# ── Setup ──────────────────────────────────────────────────────
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
LOG_DIR="$PROJECT_DIR/.gc-logs/${TIMESTAMP}"
TOOLS_READONLY="Read,Glob,Grep,Bash"
TOOLS_FULL="Read,Edit,Write,Glob,Grep,Bash"

echo ""
echo "╔════════════════════════════════════════════════════════╗"
echo "║  Garbage Collection Pipeline                          ║"
echo "╠════════════════════════════════════════════════════════╣"
echo "║  Project:    $(basename "$PROJECT_DIR")"
echo "║  Target:     ${TARGET_MODE}: ${TARGET_LABEL}"
echo "║  Files:      ${#FILES[@]}"
echo "║  Gate:       ${GATE_COMMAND:-none}"
echo "║  Codex:      $CODEX_ENABLED"
echo "║  Dry run:    $DRY_RUN"
echo "║  Logs:       $LOG_DIR"
echo "╚════════════════════════════════════════════════════════╝"
echo ""

if [[ "$DRY_RUN" == true ]]; then
    echo "Files that would be processed:"
    for f in "${FILES[@]}"; do echo "  - $f"; done
    echo ""
    echo "Run without --dry-run to execute."
    exit 0
fi

# ── Git setup ──────────────────────────────────────────────────
if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    echo "ERROR: Must run inside a git repository."
    echo "The pipeline uses git diff for self-review, Codex review, and final reporting."
    exit 1
fi

# Require a clean baseline so the final diff reflects only GC changes.
if ! git diff --quiet HEAD 2>/dev/null; then
    echo "ERROR: Working tree has uncommitted changes."
    echo "Commit or stash them first, then re-run."
    exit 1
fi

mkdir -p "$LOG_DIR"

# Ensure logs dir is ignored
if [[ -f .gitignore ]] && ! grep -q '.gc-logs' .gitignore 2>/dev/null; then
    echo '.gc-logs/' >> .gitignore
elif [[ ! -f .gitignore ]]; then
    echo '.gc-logs/' > .gitignore
fi

# ── Helper: run a pipeline step ────────────────────────────────
STEP_SESSION_ID=""

run_step() {
    local step_num="$1"
    local step_name="$2"
    local prompt="$3"
    local session_id="$4"
    local tools="$5"
    local max_turns="$6"
    local log_prefix="$7"

    echo "  [${step_num}] ${step_name}..."

    local cmd_args=(-p "$prompt" --output-format json --allowedTools "$tools" --max-turns "$max_turns")
    if [[ "$session_id" != "new" ]]; then
        cmd_args+=(--resume "$session_id")
    fi

    if timeout "$STEP_TIMEOUT" claude "${cmd_args[@]}" \
        >"${log_prefix}-output.json" \
        2>"${log_prefix}-stderr.log"; then

        STEP_SESSION_ID=$(jq -r '.session_id // empty' "${log_prefix}-output.json" 2>/dev/null || true)
        if [[ -z "$STEP_SESSION_ID" ]]; then
            echo "    WARNING: No session ID in output"
            return 1
        fi
        return 0
    else
        local exit_code=$?
        if [[ $exit_code -eq 124 ]]; then
            echo "    TIMED OUT after ${STEP_TIMEOUT}s"
        else
            echo "    FAILED (exit code $exit_code)"
        fi
        return 1
    fi
}

# ── Process each file ──────────────────────────────────────────
SUCCEEDED=()
FAILED=()
TOTAL=${#FILES[@]}
CURRENT=0

for file in "${FILES[@]}"; do
    CURRENT=$((CURRENT + 1))
    FILE_BASE="$(basename "$file" | sed 's/\.[^.]*$//')"
    FILE_LOG="$LOG_DIR/${FILE_BASE}"
    mkdir -p "$FILE_LOG"

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  [$CURRENT/$TOTAL] $file"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    FILE_START=$(date +%s)

    # ── Step 1: GC Analysis ────────────────────────────────────
    if ! run_step "1/6" "GC Analysis" \
"You are performing a focused garbage collection / cleanup analysis on: $file

Read the file carefully. Then search the ENTIRE project (all directories) to verify usage of functions, classes, and imports before flagging anything as unused.

Analyze for:
1. **Dead Code** — Unused functions, methods, variables, imports. Grep across the full project to confirm.
2. **Duplication** — Similar code blocks that could be consolidated.
3. **Unnecessary Complexity** — Over-abstraction, premature generalization, overly clever code.
4. **Stale Comments/TODOs** — Outdated or redundant comments, old TODOs.

For each finding include file path, line numbers, and code snippets.

Organize by confidence:
- **Safe to Remove**: Clearly dead/unused, verified across the project
- **Simplify**: Works but more complex than needed, with suggested simplification
- **Inconsistent Patterns**: Different ways of doing the same thing (note the dominant pattern)
- **Verify Before Removing**: Might be used dynamically or externally

This is ANALYSIS ONLY — do NOT make any code changes." \
        "new" "$TOOLS_READONLY" "$MAX_TURNS_ANALYSIS" "$FILE_LOG/step1"; then

        echo "  FAILED at GC analysis — skipping file"
        FAILED+=("$file")
        continue
    fi
    SID="$STEP_SESSION_ID"

    # ── Step 2: Codex second opinion / action plan ─────────────
    if [[ "$CODEX_ENABLED" == true ]]; then
        if ! run_step "2/6" "Consulting Codex" \
"Now consult Codex for a second opinion on the GC findings.

Write a clear, self-contained summary of ALL findings (Codex has no context from this conversation), then run this bash command.

IMPORTANT: Use timeout to prevent hanging. Run exactly:

timeout ${CODEX_TIMEOUT} codex exec --full-auto \"<YOUR_SUMMARY_HERE>

Give your honest opinion as a senior engineer:
1. Do you agree with each finding? Which are safe to action?
2. Are any findings risky or wrong?
3. Did the analysis miss anything in the file?
4. What priority order for the changes?

Be direct. We want pragmatic assessment, not perfection.\"

If the codex command times out or fails, skip it and proceed with the GC findings as-is.

After Codex responds, assess its feedback:
- **Worth considering**: Valid, actionable points
- **Disagree**: Where Codex lacks context or is wrong

Produce a FINAL ACTION PLAN: a prioritized list of specific, safe changes combining GC findings with Codex feedback." \
            "$SID" "$TOOLS_READONLY" "$MAX_TURNS_CODEX" "$FILE_LOG/step2"; then

            echo "    Codex consultation failed (non-fatal, continuing with GC findings only)"
        fi
    else
        echo "  [2/6] Skipping Codex consultation"

        if ! run_step "2/6" "Generating action plan" \
"Based on the GC analysis above, produce a FINAL ACTION PLAN: a prioritized list of specific changes to make. Only include changes that are clearly safe and behavior-preserving. Group them by type (dead code removal, simplification, etc.)." \
            "$SID" "$TOOLS_READONLY" 10 "$FILE_LOG/step2"; then
            echo "    Action plan generation failed (non-fatal)"
        fi
    fi

    # ── Step 3: Make Changes ───────────────────────────────────
    if ! run_step "3/6" "Making changes" \
"Execute the action plan. Make all code changes identified as safe and worthwhile.

Rules:
- BEHAVIOR-PRESERVING ONLY. Nothing should work differently after changes.
- Before removing anything, verify one more time it is truly unused (grep the project).
- Be precise — change exactly what needs to change, nothing more.
- Do NOT change formatting, naming conventions, or add comments/docstrings unless flagged.
- After making changes, list each change with file and line numbers." \
        "$SID" "$TOOLS_FULL" "$MAX_TURNS_CHANGES" "$FILE_LOG/step3"; then

        echo "  FAILED making changes — skipping to next file"
        FAILED+=("$file")
        continue
    fi

    # ── Step 4: Self-Review + Fix ──────────────────────────────
    if ! run_step "4/6" "Self-review" \
"Critically self-review the changes you just made.

Run git diff to see all uncommitted changes, then ask:
1. Could anything be simpler?
2. Did you leave unused code, debug statements, or dead imports?
3. Are there inconsistencies in your changes?
4. Did you miss anything from the action plan?
5. Did you accidentally change behavior?
6. Are the changes correct — no typos, no wrong variable names?

If you find issues, FIX THEM immediately. Do not just report — make the fixes.
Show a brief summary of adjustments made (or confirm no issues found)." \
        "$SID" "$TOOLS_FULL" "$MAX_TURNS_REVIEW" "$FILE_LOG/step4"; then

        echo "    Self-review failed (non-fatal, continuing)"
    fi

    # ── Step 5: Codex Code Review + Fix (optional) ─────────────
    if [[ "$CODEX_ENABLED" == true ]]; then
        if ! run_step "5/6" "Codex code review" \
"Ask Codex to review the uncommitted changes.

IMPORTANT: Use timeout to prevent hanging. Run exactly:

timeout ${CODEX_TIMEOUT} codex review --uncommitted \"Focus on: 1. Bugs or logic errors? 2. Is this the simplest approach? 3. Code added but not needed? 4. Code modified unnecessarily? 5. Security issues? 6. Anything missing? IMPORTANT: Looking for GOOD ENOUGH, not perfect. Only flag issues a senior dev would fix before merging.\"

If the codex command times out or fails, skip the review and move on.

After Codex responds:
- Fix genuine issues (bugs, logic errors, unnecessary changes) immediately
- Ignore nitpicks and style preferences
- Show what Codex found and what you fixed (if anything)" \
            "$SID" "$TOOLS_FULL" "$MAX_TURNS_REVIEW" "$FILE_LOG/step5"; then

            echo "    Codex code review failed (non-fatal, continuing)"
        fi
    else
        echo "  [5/6] Skipping Codex code review"
    fi

    # ── Step 6: Gate + Report ──────────────────────────────────
    GATE_INSTRUCTION=""
    if [[ -n "$GATE_COMMAND" ]]; then
        if [[ "$GATE_REQUIRED" == true ]]; then
            GATE_INSTRUCTION="1. Run: ${GATE_COMMAND}
2. If the gate fails and it is caused by your changes, fix it and re-run. If unrelated, note it and proceed.
3. Once the gate passes, summarize what changed and leave everything uncommitted."
        else
            GATE_INSTRUCTION="1. Run: ${GATE_COMMAND}
2. If it fails, note the failure but proceed anyway (gate is advisory).
3. Summarize what changed and leave everything uncommitted."
        fi
    else
        GATE_INSTRUCTION="No gate command configured — skip directly to summarizing the changes."
    fi

    if ! run_step "6/6" "Gate + report" \
"First check if there are any uncommitted changes with git diff.

If there are NO changes, just say 'No changes needed for $file' and stop.

If there ARE changes:
${GATE_INSTRUCTION}

At the end:
- Leave changes uncommitted
- Show a concise summary of the files and edits involved
- Do not create commits or branches" \
        "$SID" "$TOOLS_FULL" "$MAX_TURNS_GATE" "$FILE_LOG/step6"; then

        echo "  FAILED at gate/report"
        FAILED+=("$file")
        continue
    fi

    FILE_END=$(date +%s)
    FILE_DURATION=$(( FILE_END - FILE_START ))
    MINUTES=$(( FILE_DURATION / 60 ))
    SECONDS_REM=$(( FILE_DURATION % 60 ))
    echo "  Completed in ${MINUTES}m ${SECONDS_REM}s"
    SUCCEEDED+=("$file")
done

# ── Final full gate ────────────────────────────────────────────
if [[ -n "$GATE_COMMAND" && ${#SUCCEEDED[@]} -gt 0 ]]; then
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Final full gate"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    timeout "$STEP_TIMEOUT" claude -p \
"Run ${GATE_COMMAND} to verify everything works together after all changes. Show the full output.

If it fails:
- Analyze whether the failure is caused by the refactoring changes
- If yes, fix it
- If unrelated, note it

Report the final gate result clearly: PASS or FAIL." \
        --output-format json \
        --allowedTools "$TOOLS_FULL" \
        --max-turns 30 \
        >"$LOG_DIR/final-gate-output.json" \
        2>"$LOG_DIR/final-gate-stderr.log" || {
        echo "  WARNING: Final gate had issues — check $LOG_DIR/final-gate-output.json"
    }
fi

# ── Summary ────────────────────────────────────────────────────
echo ""
echo "╔════════════════════════════════════════════════════════╗"
echo "║  Pipeline Complete                                    ║"
echo "╠════════════════════════════════════════════════════════╣"
echo "║  Project:    $(basename "$PROJECT_DIR")"
echo "║  Succeeded:  ${#SUCCEEDED[@]}/${TOTAL} files"
for f in "${SUCCEEDED[@]:-}"; do
    [[ -n "$f" ]] && echo "║    + $f"
done
if [[ ${#FAILED[@]} -gt 0 ]]; then
    echo "║  Failed:     ${#FAILED[@]}/${TOTAL} files"
    for f in "${FAILED[@]}"; do
        echo "║    x $f"
    done
fi
echo "║  Logs:       $LOG_DIR"
echo "╚════════════════════════════════════════════════════════╝"
echo ""
echo "Next steps:"
echo "  1. Review status:   git status"
echo "  2. Review diff:     git diff"
echo "  3. Commit manually if the changes look correct"
echo ""
