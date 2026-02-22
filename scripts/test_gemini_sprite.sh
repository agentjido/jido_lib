#!/usr/bin/env bash
#
# test_gemini_sprite.sh
#
# Pressure-test the full PrBot flow using ONLY the Sprites CLI + gh + git
# and one provider CLI in stream-JSON mode.
#
# Validates: sprite lifecycle, env injection, gh auth, git clone, branch,
# provider streaming prompt, provider code change, commit, push, PR, comment.
#
# Usage:
#   ./test_gemini_sprite.sh https://github.com/OWNER/REPO/issues/123
#
# Options:
#   --keep-sprite       Don't destroy the sprite on exit (for debugging)
#   --sprite-name NAME  Use a custom sprite name (default: jido-test-<runid>)
#   --org ORG           Sprites organization
#   --dry-run           Validate everything but skip mutating GitHub operations
#   --verbose           Print raw JSON lines in addition to parsed progress
#
# Required env vars (auto-sourced from jido_lib/.env):
#   Shared: SPRITES_TOKEN (or sprite login), GH_TOKEN or GITHUB_TOKEN
#   Gemini: GEMINI_API_KEY (or GOOGLE_API_KEY)
#
set -euo pipefail

PROVIDER="gemini"
PROVIDER_LABEL="Gemini"
SCRIPT_NAME="test_gemini_sprite.sh"

# ─── Source .env if present ─────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for envfile in "$SCRIPT_DIR/jido_lib/.env" "$SCRIPT_DIR/.env"; do
  if [[ -f "$envfile" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$envfile"
    set +a
  fi
done

# ─── Color helpers ──────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fail()  { echo -e "${RED}[FAIL]${NC}  $*"; }
step()  { echo -e "\n${CYAN}━━━ $* ━━━${NC}"; }

# ─── Defaults ───────────────────────────────────────────────────────────────
KEEP_SPRITE=false
DRY_RUN=false
VERBOSE=false
SPRITE_NAME=""
ORG_FLAG=""
RUN_ID=$(openssl rand -hex 6)
BRANCH_PREFIX="jido/prbot"
WORKSPACE_DIR=""
REPO_DIR=""

ARTIFACTS=()
LAST_STREAM_ARTIFACT=""
LAST_STREAM_RESULT_TEXT=""
LAST_STREAM_EVENT_COUNT="0"

# ─── Parse args ─────────────────────────────────────────────────────────────
ISSUE_URL=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --keep-sprite)   KEEP_SPRITE=true; shift ;;
    --dry-run)       DRY_RUN=true; shift ;;
    --verbose)       VERBOSE=true; shift ;;
    --sprite-name)   SPRITE_NAME="$2"; shift 2 ;;
    --org)           ORG_FLAG="-o $2"; shift 2 ;;
    -h|--help)
      head -26 "$0" | grep '^#' | sed 's/^# \?//'
      exit 0
      ;;
    https://*)       ISSUE_URL="$1"; shift ;;
    *)               fail "Unknown argument: $1"; exit 1 ;;
  esac
done

if [[ -z "$ISSUE_URL" ]]; then
  fail "Usage: $0 <github-issue-url> [options]"
  fail "Example: $0 https://github.com/agentjido/jido_chat/issues/20"
  exit 1
fi

# ─── Parse issue URL ───────────────────────────────────────────────────────
if [[ "$ISSUE_URL" =~ github\.com/([^/]+)/([^/]+)/issues/([0-9]+) ]]; then
  OWNER="${BASH_REMATCH[1]}"
  REPO="${BASH_REMATCH[2]}"
  ISSUE_NUMBER="${BASH_REMATCH[3]}"
else
  fail "Invalid GitHub issue URL: $ISSUE_URL"
  exit 1
fi

[[ -z "$SPRITE_NAME" ]] && SPRITE_NAME="jido-test-${RUN_ID}"

info "Provider: ${PROVIDER_LABEL}"
info "Issue:    ${OWNER}/${REPO}#${ISSUE_NUMBER}"
info "Run ID:   ${RUN_ID}"
info "Sprite:   ${SPRITE_NAME}"

# ─── Helpers ────────────────────────────────────────────────────────────────
shorten() {
  local text="$1"
  local max_len="${2:-160}"

  text="$(echo "$text" | tr '\r\n' ' ' | sed -E 's/[[:space:]]+/ /g')"
  if [[ ${#text} -le $max_len ]]; then
    printf '%s' "$text"
  else
    printf '%s…' "${text:0:max_len}"
  fi
}

shell_quote() {
  printf "'%s'" "$(printf "%s" "$1" | sed "s/'/'\\\\''/g")"
}

# ─── Helper: run command in sprite ─────────────────────────────────────────
sprite_exec() {
  local cmd="$1"
  local dir="${2:-}"

  local env_pairs=""
  local val=""

  for var in \
    GH_TOKEN GITHUB_TOKEN \
    ANTHROPIC_BASE_URL ANTHROPIC_AUTH_TOKEN ANTHROPIC_API_KEY CLAUDE_CODE_API_KEY \
    ANTHROPIC_DEFAULT_HAIKU_MODEL ANTHROPIC_DEFAULT_SONNET_MODEL ANTHROPIC_DEFAULT_OPUS_MODEL \
    AMP_API_KEY AMP_URL \
    OPENAI_API_KEY \
    GEMINI_API_KEY GOOGLE_API_KEY GOOGLE_GENAI_USE_VERTEXAI GOOGLE_GENAI_USE_GCA GOOGLE_CLOUD_PROJECT GOOGLE_CLOUD_LOCATION; do
    val="${!var:-}"
    if [[ -n "$val" ]]; then
      [[ -n "$env_pairs" ]] && env_pairs="${env_pairs},"
      env_pairs="${env_pairs}${var}=${val}"
    fi
  done

  [[ -n "$env_pairs" ]] && env_pairs="${env_pairs},"
  env_pairs="${env_pairs}GH_PROMPT_DISABLED=1,GIT_TERMINAL_PROMPT=0,CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1,API_TIMEOUT_MS=3000000"

  local path_bootstrap='export PATH="$PATH:$HOME/.local/bin:$HOME/.npm/bin:$HOME/.npm-global/bin"; if command -v npm >/dev/null 2>&1; then _npm_prefix="$(npm config get prefix 2>/dev/null || true)"; if [ -n "$_npm_prefix" ] && [ "$_npm_prefix" != "undefined" ]; then PATH="$PATH:${_npm_prefix}/bin"; fi; fi; export PATH'
  local wrapped_cmd="${path_bootstrap}; ${cmd}"

  local -a exec_args=(sprite exec)
  # shellcheck disable=SC2206
  [[ -n "$ORG_FLAG" ]] && exec_args+=($ORG_FLAG)
  exec_args+=(-s "$SPRITE_NAME")
  [[ -n "$dir" ]] && exec_args+=(-dir "$dir")
  exec_args+=(-env "$env_pairs" -- sh -c "$wrapped_cmd")

  [[ "$VERBOSE" == true ]] && info "EXEC: $cmd" >&2
  "${exec_args[@]}" 2>&1
}

provider_binary() {
  case "$PROVIDER" in
    claude|amp|codex|gemini) echo "$PROVIDER" ;;
    *) echo "$PROVIDER" ;;
  esac
}

provider_npm_package() {
  case "$PROVIDER" in
    amp) echo "@sourcegraph/amp" ;;
    codex) echo "@openai/codex" ;;
    gemini) echo "@google/gemini-cli" ;;
    *) echo "" ;;
  esac
}

provider_step_9_title() {
  case "$PROVIDER" in
    claude) echo "Step 9: Provision Claude CLI for stream-JSON (non-interactive)" ;;
    amp) echo "Step 9: Provision Amp CLI for stream-JSON (non-interactive)" ;;
    codex) echo "Step 9: Provision Codex CLI for JSON streaming (non-interactive)" ;;
    gemini) echo "Step 9: Provision Gemini CLI for stream-JSON (non-interactive)" ;;
    *) echo "Step 9: Provision Provider CLI" ;;
  esac
}

provider_step_10_title() {
  case "$PROVIDER" in
    claude) echo "Step 10: Claude Code Change (stream-JSON)" ;;
    amp) echo "Step 10: Amp Code Change (stream-JSON)" ;;
    codex) echo "Step 10: Codex Code Change (JSONL)" ;;
    gemini) echo "Step 10: Gemini Code Change (stream-JSON)" ;;
    *) echo "Step 10: Provider Code Change" ;;
  esac
}

require_provider_env() {
  case "$PROVIDER" in
    claude)
      if [[ -z "${ANTHROPIC_AUTH_TOKEN:-}" && -z "${ANTHROPIC_API_KEY:-}" ]]; then
        fail "Claude requires ANTHROPIC_AUTH_TOKEN (or ANTHROPIC_API_KEY)"
        exit 1
      fi
      [[ -n "${ANTHROPIC_BASE_URL:-}" ]] || warn "ANTHROPIC_BASE_URL not set; defaulting to https://api.z.ai/api/anthropic"
      ;;
    amp)
      if [[ -z "${AMP_API_KEY:-}" ]]; then
        fail "Amp requires AMP_API_KEY"
        exit 1
      fi
      ;;
    codex)
      if [[ -z "${OPENAI_API_KEY:-}" ]]; then
        fail "Codex requires OPENAI_API_KEY"
        exit 1
      fi
      ;;
    gemini)
      if [[ -z "${GEMINI_API_KEY:-}" && -n "${GOOGLE_API_KEY:-}" ]]; then
        GEMINI_API_KEY="${GOOGLE_API_KEY}"
        export GEMINI_API_KEY
        warn "GEMINI_API_KEY not set; mirroring GOOGLE_API_KEY for Gemini CLI compatibility"
      fi

      if [[ -z "${GEMINI_API_KEY:-}" && "${GOOGLE_GENAI_USE_VERTEXAI:-}" != "true" && "${GOOGLE_GENAI_USE_GCA:-}" != "true" ]]; then
        fail "Gemini requires GEMINI_API_KEY (recommended), or GOOGLE_GENAI_USE_VERTEXAI=true, or GOOGLE_GENAI_USE_GCA=true"
        exit 1
      fi
      if [[ "${GOOGLE_GENAI_USE_VERTEXAI:-}" == "true" ]]; then
        if [[ -z "${GOOGLE_API_KEY:-}" && ( -z "${GOOGLE_CLOUD_PROJECT:-}" || -z "${GOOGLE_CLOUD_LOCATION:-}" ) ]]; then
          fail "Vertex mode requires GOOGLE_API_KEY or GOOGLE_CLOUD_PROJECT + GOOGLE_CLOUD_LOCATION"
          exit 1
        fi
      fi
      ;;
    *)
      fail "Unknown provider: $PROVIDER"
      exit 1
      ;;
  esac
}

ensure_provider_cli_in_sprite() {
  local bin
  local npm_pkg
  local cli_check

  bin="$(provider_binary)"
  npm_pkg="$(provider_npm_package)"

  cli_check=$(sprite_exec "command -v ${bin} >/dev/null 2>&1 && ${bin} --version 2>&1 | head -1 || echo MISSING") || true

  if echo "$cli_check" | grep -q "MISSING"; then
    if [[ -z "$npm_pkg" ]]; then
      fail "${bin} CLI not found inside sprite"
      exit 1
    fi

    warn "${bin} not found inside sprite; attempting install via npm (${npm_pkg})"
    sprite_exec "command -v npm >/dev/null 2>&1" || {
      fail "npm is required inside sprite to install ${bin} (${npm_pkg})"
      exit 1
    }

    INSTALL_OUTPUT=$(sprite_exec "npm install -g ${npm_pkg} 2>&1") || {
      fail "Failed to install ${bin}: $(shorten "$INSTALL_OUTPUT" 300)"
      exit 1
    }
    ok "Installed ${bin} via npm"
  fi

  cli_check=$(sprite_exec "command -v ${bin} >/dev/null 2>&1 && ${bin} --version 2>&1 | head -1 || echo MISSING")
  if echo "$cli_check" | grep -q "MISSING"; then
    fail "${bin} CLI not found inside sprite after install attempt"
    exit 1
  fi
  ok "${bin}: $cli_check"

  case "$PROVIDER" in
    claude)
      local help_output
      help_output=$(sprite_exec "claude --help 2>&1")
      echo "$help_output" | grep -q -- "--output-format" || {
        fail "claude --help missing --output-format"; exit 1
      }
      echo "$help_output" | grep -q -- "stream-json" || {
        fail "claude --help missing stream-json support"; exit 1
      }
      ok "Claude stream-json flags detected"
      ;;
    amp)
      local amp_help
      amp_help=$(sprite_exec "amp --help 2>&1")
      echo "$amp_help" | grep -q -- "--execute" || {
        fail "amp --help missing --execute"; exit 1
      }
      echo "$amp_help" | grep -q -- "--stream-json" || {
        fail "amp --help missing --stream-json"; exit 1
      }
      ok "Amp stream-json flags detected"
      ;;
    codex)
      local codex_help
      codex_help=$(sprite_exec "codex exec --help 2>&1")
      echo "$codex_help" | grep -q -- "--json" || {
        fail "codex exec --help missing --json"; exit 1
      }
      ok "Codex JSONL flag detected"
      ;;
    gemini)
      local gemini_help
      gemini_help=$(sprite_exec "gemini --help 2>&1")
      echo "$gemini_help" | grep -q -- "--output-format" || {
        fail "gemini --help missing --output-format"; exit 1
      }
      echo "$gemini_help" | grep -q -- "stream-json" || {
        fail "gemini --help missing stream-json"; exit 1
      }
      ok "Gemini stream-json flags detected"
      ;;
  esac
}

configure_claude_runtime() {
  local zai_check
  local provision_check

  zai_check=$(sprite_exec 'if [ -n "${ANTHROPIC_BASE_URL:-}" ] && { [ -n "${ANTHROPIC_AUTH_TOKEN:-}" ] || [ -n "${ANTHROPIC_API_KEY:-}" ]; }; then echo present; else echo missing; fi')
  if echo "$zai_check" | grep -q "missing"; then
    fail "Claude requires ANTHROPIC_BASE_URL and token env visible in sprite"
    exit 1
  fi
  ok "Claude auth config visible inside sprite"

  info "Provisioning Claude config files for non-interactive usage..."

  sprite_exec 'node -e '\''
const fs = require("fs");
const path = require("path");
const filePath = path.join(process.env.HOME, ".claude.json");
let existing = {};
try { existing = JSON.parse(fs.readFileSync(filePath, "utf-8")); } catch (e) {}
const config = {
  ...existing,
  hasCompletedOnboarding: true,
  hasTrustDialogAccepted: true,
  hasTrustDialogHooksAccepted: true,
  numStartups: (existing.numStartups || 0) + 1
};
fs.writeFileSync(filePath, JSON.stringify(config, null, 2), "utf-8");
console.log("OK");
'\''' || { fail "Failed to write ~/.claude.json"; exit 1; }
  ok "~/.claude.json written"

  sprite_exec 'mkdir -p ~/.claude && echo "2025-01-01" > ~/.claude/.acceptedTos' || {
    fail "Failed to write ~/.claude/.acceptedTos"
    exit 1
  }
  ok "~/.claude/.acceptedTos written"

  sprite_exec 'node -e '\''
const fs = require("fs");
const path = require("path");
const settingsPath = path.join(process.env.HOME, ".claude", "settings.json");
let settings = {};
try {
  settings = JSON.parse(fs.readFileSync(settingsPath, "utf-8"));
} catch (e) {}
settings.env = {
  ...(settings.env || {}),
  ANTHROPIC_AUTH_TOKEN: process.env.ANTHROPIC_AUTH_TOKEN || process.env.ANTHROPIC_API_KEY || "",
  ANTHROPIC_BASE_URL: process.env.ANTHROPIC_BASE_URL || "https://api.z.ai/api/anthropic",
  API_TIMEOUT_MS: "3000000",
  CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: "1"
};
fs.mkdirSync(path.dirname(settingsPath), { recursive: true });
fs.writeFileSync(settingsPath, JSON.stringify(settings, null, 2), "utf-8");
console.log("OK");
'\''' || { fail "Failed to update ~/.claude/settings.json"; exit 1; }
  ok "~/.claude/settings.json updated"

  provision_check=$(sprite_exec '
OK=true
test -f ~/.claude.json || { echo "MISSING: ~/.claude.json"; OK=false; }
test -f ~/.claude/.acceptedTos || { echo "MISSING: ~/.claude/.acceptedTos"; OK=false; }
test -f ~/.claude/settings.json || { echo "MISSING: ~/.claude/settings.json"; OK=false; }
$OK && echo "ALL_PRESENT"
')
  if ! echo "$provision_check" | grep -q "ALL_PRESENT"; then
    fail "Claude provisioning incomplete: $provision_check"
    exit 1
  fi
  ok "All Claude runtime files present"
}

bootstrap_codex_auth() {
  if sprite_exec "codex login status >/dev/null 2>&1"; then
    ok "Codex auth already configured inside sprite"
    return
  fi

  info "Bootstrapping Codex auth from OPENAI_API_KEY..."
  sprite_exec 'if [ -z "${OPENAI_API_KEY:-}" ]; then echo "MISSING_OPENAI_API_KEY"; exit 1; fi; printenv OPENAI_API_KEY | codex login --with-api-key >/dev/null 2>&1' || {
    fail "codex login --with-api-key failed"
    exit 1
  }

  sprite_exec "codex login status >/dev/null 2>&1" || {
    fail "Codex login status still failing after bootstrap"
    exit 1
  }
  ok "Codex auth configured inside sprite"
}

prepare_provider_runtime() {
  case "$PROVIDER" in
    claude)
      configure_claude_runtime
      ;;
    codex)
      bootstrap_codex_auth
      ;;
    amp|gemini)
      ok "No additional ${PROVIDER_LABEL} runtime bootstrap required"
      ;;
  esac
}

write_sprite_prompt_file() {
  local prompt="$1"
  local prompt_file="$2"
  local dir="$3"
  local prompt_q

  prompt_q="$(shell_quote "$prompt_file")"
  sprite_exec "cat > ${prompt_q} << 'JIDO_PROMPT_EOF'
${prompt}
JIDO_PROMPT_EOF" "$dir" >/dev/null
}

provider_smoke_command() {
  local prompt_file="$1"
  local pf_q
  pf_q="$(shell_quote "$prompt_file")"

  case "$PROVIDER" in
    claude)
      echo "if command -v timeout >/dev/null 2>&1; then timeout 120 claude -p --output-format stream-json --include-partial-messages --no-session-persistence --verbose --dangerously-skip-permissions --tools '' \\\"\$(cat ${pf_q})\\\"; else claude -p --output-format stream-json --include-partial-messages --no-session-persistence --verbose --dangerously-skip-permissions --tools '' \\\"\$(cat ${pf_q})\\\"; fi"
      ;;
    amp)
      echo "if command -v timeout >/dev/null 2>&1; then timeout 120 amp -x --stream-json --dangerously-allow-all --no-color < ${pf_q}; else amp -x --stream-json --dangerously-allow-all --no-color < ${pf_q}; fi"
      ;;
    codex)
      echo "if command -v timeout >/dev/null 2>&1; then timeout 120 codex exec --json --full-auto - < ${pf_q}; else codex exec --json --full-auto - < ${pf_q}; fi"
      ;;
    gemini)
      echo "if command -v timeout >/dev/null 2>&1; then timeout 120 gemini --output-format stream-json \\\"\$(cat ${pf_q})\\\"; else gemini --output-format stream-json \\\"\$(cat ${pf_q})\\\"; fi"
      ;;
    *)
      fail "Unknown provider in smoke command: $PROVIDER"
      exit 1
      ;;
  esac
}

provider_change_command() {
  local prompt_file="$1"
  local pf_q
  pf_q="$(shell_quote "$prompt_file")"

  case "$PROVIDER" in
    claude)
      echo "if command -v timeout >/dev/null 2>&1; then timeout 180 claude -p --output-format stream-json --include-partial-messages --no-session-persistence --verbose --dangerously-skip-permissions \\\"\$(cat ${pf_q})\\\"; else claude -p --output-format stream-json --include-partial-messages --no-session-persistence --verbose --dangerously-skip-permissions \\\"\$(cat ${pf_q})\\\"; fi"
      ;;
    amp)
      echo "if command -v timeout >/dev/null 2>&1; then timeout 180 amp -x --stream-json --dangerously-allow-all --no-color < ${pf_q}; else amp -x --stream-json --dangerously-allow-all --no-color < ${pf_q}; fi"
      ;;
    codex)
      echo "if command -v timeout >/dev/null 2>&1; then timeout 180 codex exec --json --dangerously-bypass-approvals-and-sandbox - < ${pf_q}; else codex exec --json --dangerously-bypass-approvals-and-sandbox - < ${pf_q}; fi"
      ;;
    gemini)
      echo "if command -v timeout >/dev/null 2>&1; then timeout 180 gemini --output-format stream-json --approval-mode yolo \\\"\$(cat ${pf_q})\\\"; else gemini --output-format stream-json --approval-mode yolo \\\"\$(cat ${pf_q})\\\"; fi"
      ;;
    *)
      fail "Unknown provider in change command: $PROVIDER"
      exit 1
      ;;
  esac
}

provider_smoke_prompt() {
  case "$PROVIDER" in
    claude) echo "Return exactly one line: JIDO_${PROVIDER_LABEL^^}_SMOKE_OK. Do not use tools. Do not ask questions." ;;
    amp) echo "Return exactly one line: JIDO_AMP_SMOKE_OK. Do not ask questions." ;;
    codex) echo "Return exactly one line: JIDO_CODEX_SMOKE_OK. Do not ask questions." ;;
    gemini) echo "Return exactly one line: JIDO_GEMINI_SMOKE_OK. Do not ask questions." ;;
    *) echo "Return exactly one line: JIDO_SMOKE_OK. Do not ask questions." ;;
  esac
}

provider_change_prompt() {
  local timestamp="$1"

  cat <<PROMPT
Create a file called .jido-smoke-test.md with exactly this content and nothing else:

# Jido PrBot Smoke Test (${PROVIDER_LABEL})

Automated smoke test confirming the full PrBot pipeline works end-to-end.

- Provider: ${PROVIDER_LABEL}
- Run ID: ${RUN_ID}
- Issue: ${OWNER}/${REPO}#${ISSUE_NUMBER}
- Timestamp: ${timestamp}

This file can be safely deleted.

Do not ask follow-up questions.
Do not wait for confirmation.
If any detail is ambiguous, choose a reasonable default and proceed.
PROMPT
}

extract_result_text_from_artifact() {
  local artifact="$1"

  jq -Rr '
    fromjson? |
    if . == null then empty
    elif (.type == "result" and (.result | type == "string")) then .result
    elif (.type == "assistant" and (.message.content | type == "array")) then ([.message.content[]? | select(.type == "text") | .text] | join(""))
    elif (.output_text | type == "string") then .output_text
    elif (.text | type == "string") then .text
    elif (.delta | type == "string") then .delta
    elif (.message | type == "string") then .message
    elif (.event.delta.text | type == "string") then .event.delta.text
    else empty
    end
  ' "$artifact" 2>/dev/null | awk 'NF {last=$0} END {print last}'
}

stream_artifact_indicates_success() {
  local artifact="$1"

  case "$PROVIDER" in
    amp|claude|gemini)
      jq -Rre '
        fromjson? |
        select(
          (.type == "result" and ((.subtype // "") == "success" or (.is_error == false)))
        )
      ' "$artifact" >/dev/null 2>&1
      ;;
    codex)
      jq -Rre '
        fromjson? |
        select(.type == "turn.completed")
      ' "$artifact" >/dev/null 2>&1
      ;;
    *)
      jq -Rre '
        fromjson? |
        select(.type == "result" and ((.subtype // "") == "success"))
      ' "$artifact" >/dev/null 2>&1
      ;;
  esac
}

print_stream_progress_line() {
  local phase="$1"
  local line="$2"
  local parsed=""
  local type=""
  local nested=""
  local text=""

  parsed=$(printf '%s\n' "$line" | jq -Rr '
    fromjson? |
    if . == null then empty
    else
      [
        (.type // .event.type // .name // .kind // "event"),
        (.event.type // ""),
        (
          if (.event.delta.text? // "") != "" then .event.delta.text
          elif (.message.content? | type == "array") then ([.message.content[]? | select(.type == "text") | .text] | join(""))
          elif (.result? | type == "string") then .result
          elif (.text? | type == "string") then .text
          elif (.delta? | type == "string") then .delta
          elif (.message? | type == "string") then .message
          elif (.output_text? | type == "string") then .output_text
          else ""
          end
        )
      ] | @tsv
    end
  ' 2>/dev/null)

  if [[ -z "$parsed" ]]; then
    if [[ "$VERBOSE" == true ]]; then
      info "[${PROVIDER_LABEL}][${phase}] non-json $(shorten "$line" 140)"
    fi
    return 0
  fi

  IFS=$'\t' read -r type nested text <<<"$parsed"
  text="$(shorten "$text" 160)"

  case "$type" in
    stream_event|assistant|result|session_started|session_completed|session_failed|error|warning|tool_call|tool_result|output_text_delta|output_text_final|thinking_delta)
      if [[ -n "$text" ]]; then
        info "[${PROVIDER_LABEL}][${phase}] ${type}${nested:+:${nested}} ${text}"
      else
        info "[${PROVIDER_LABEL}][${phase}] ${type}${nested:+:${nested}}"
      fi
      ;;
    *)
      if [[ "$VERBOSE" == true ]]; then
        if [[ -n "$text" ]]; then
          info "[${PROVIDER_LABEL}][${phase}] ${type}${nested:+:${nested}} ${text}"
        else
          info "[${PROVIDER_LABEL}][${phase}] ${type}${nested:+:${nested}}"
        fi
      fi
      ;;
  esac

  if [[ "$VERBOSE" == true ]]; then
    echo "[RAW][${PROVIDER}/${phase}] $line"
  fi
}

run_stream_json() {
  local phase="$1"
  local cmd="$2"
  local dir="${3:-}"
  local artifact="/tmp/jido_${PROVIDER}_${RUN_ID}_${phase}.jsonl"
  local max_attempts=2
  local attempt=1

  ARTIFACTS+=("$artifact")

  while (( attempt <= max_attempts )); do
    : > "$artifact"

    if (( attempt == 1 )); then
      info "Streaming ${PROVIDER_LABEL} ${phase} JSONL -> ${artifact}"
    else
      warn "Retrying ${PROVIDER_LABEL} ${phase} stream (${attempt}/${max_attempts})"
    fi

    local rc
    set +e
    if [[ -n "$dir" ]]; then
      sprite_exec "$cmd" "$dir" | tee "$artifact" | while IFS= read -r line; do
        print_stream_progress_line "$phase" "$line"
      done
    else
      sprite_exec "$cmd" | tee "$artifact" | while IFS= read -r line; do
        print_stream_progress_line "$phase" "$line"
      done
    fi
    rc=${PIPESTATUS[0]}
    set -e

    LAST_STREAM_ARTIFACT="$artifact"
    LAST_STREAM_EVENT_COUNT="$(wc -l < "$artifact" | tr -d '[:space:]')"
    LAST_STREAM_RESULT_TEXT="$(extract_result_text_from_artifact "$artifact")"

    if [[ "$rc" -ne 0 ]] && stream_artifact_indicates_success "$artifact"; then
      warn "${PROVIDER_LABEL} ${phase} exited rc=${rc} but stream indicates success; continuing"
      rc=0
    fi

    if [[ "$rc" -eq 0 ]]; then
      ok "${PROVIDER_LABEL} ${phase} stream completed (${LAST_STREAM_EVENT_COUNT} lines)"
      if [[ -n "$LAST_STREAM_RESULT_TEXT" ]]; then
        info "${PROVIDER_LABEL} ${phase} result: $(shorten "$LAST_STREAM_RESULT_TEXT" 180)"
      fi
      return 0
    fi

    if (( attempt < max_attempts )) && grep -qi "connection closed" "$artifact"; then
      warn "${PROVIDER_LABEL} ${phase} stream ended with transient connection error; retrying..."
      sleep 2
      attempt=$((attempt + 1))
      continue
    fi

    fail "${PROVIDER_LABEL} ${phase} command failed with rc=${rc}"
    warn "Artifact: ${artifact}"
    tail -n 30 "$artifact" >&2 || true
    return "$rc"
  done

  return 1
}

# ─── Cleanup trap ───────────────────────────────────────────────────────────
SPRITE_CREATED=false
BRANCH_NAME=""
PR_URL=""
TIMESTAMP=""
INTERRUPTED=false

interrupt_handler() {
  local sig="${1:-INT}"
  trap - INT TERM
  INTERRUPTED=true
  echo ""
  warn "Received ${sig}; stopping current run..."
  pkill -TERM -P $$ 2>/dev/null || true
  sleep 1
  pkill -KILL -P $$ 2>/dev/null || true
  exit 130
}

cleanup() {
  if [[ "$KEEP_SPRITE" == true ]]; then
    warn "Keeping sprite '${SPRITE_NAME}' alive (--keep-sprite)"
    return
  fi
  if [[ "$SPRITE_CREATED" == true ]]; then
    step "Teardown"
    info "Destroying sprite '${SPRITE_NAME}'..."
    local -a destroy_args=(sprite destroy)
    # shellcheck disable=SC2206
    [[ -n "$ORG_FLAG" ]] && destroy_args+=($ORG_FLAG)
    destroy_args+=(-s "$SPRITE_NAME" --force)
    "${destroy_args[@]}" 2>&1 || warn "Sprite destroy failed (may already be gone)"
    ok "Sprite destroyed"
  fi
}
trap 'interrupt_handler INT' INT
trap 'interrupt_handler TERM' TERM
trap cleanup EXIT

# ═══════════════════════════════════════════════════════════════════════════
# STEP 1: Validate host environment
# ═══════════════════════════════════════════════════════════════════════════
step "Step 1: Validate Host Environment"

command -v sprite &>/dev/null || { fail "sprite CLI not found in PATH"; exit 1; }
ok "sprite CLI found: $(which sprite)"

command -v gh &>/dev/null && ok "gh CLI found on host: $(which gh)" \
  || warn "gh CLI not found on host (will check inside sprite)"

command -v git &>/dev/null && ok "git CLI found on host: $(which git)" \
  || warn "git CLI not found on host"

HOST_PROVIDER_BIN="$(provider_binary)"
if command -v "$HOST_PROVIDER_BIN" &>/dev/null; then
  ok "${PROVIDER_LABEL} CLI found on host: $(which "$HOST_PROVIDER_BIN")"
else
  warn "${PROVIDER_LABEL} CLI not found on host (script only requires it inside sprite)"
fi

[[ -n "${SPRITES_TOKEN:-}" ]] && ok "SPRITES_TOKEN is set" \
  || warn "SPRITES_TOKEN not set — assuming 'sprite login' session exists"

GH_TOKEN_VALUE="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
if [[ -z "$GH_TOKEN_VALUE" ]]; then
  fail "Neither GH_TOKEN nor GITHUB_TOKEN is set"
  fail "Set one of these to a GitHub PAT with repo + issues scope"
  exit 1
fi
ok "GitHub token is set (${#GH_TOKEN_VALUE} chars)"

require_provider_env
ok "${PROVIDER_LABEL} env contract validated"

info "Validating issue exists via gh on host..."
if command -v gh &>/dev/null; then
  ISSUE_TITLE=$(GH_TOKEN="$GH_TOKEN_VALUE" gh issue view "$ISSUE_NUMBER" \
    --repo "${OWNER}/${REPO}" --json title --jq .title 2>&1) || {
    fail "Could not fetch issue from host: $ISSUE_TITLE"; exit 1
  }
  ok "Issue found: \"${ISSUE_TITLE}\""
else
  warn "Skipping host-side issue validation (no gh on host)"
fi

# ═══════════════════════════════════════════════════════════════════════════
# STEP 2: Create Sprite
# ═══════════════════════════════════════════════════════════════════════════
step "Step 2: Provision Sprite"

info "Creating sprite '${SPRITE_NAME}'..."
CREATE_OUTPUT=$(sprite create $ORG_FLAG "$SPRITE_NAME" -skip-console 2>&1) || {
  fail "Failed to create sprite: $CREATE_OUTPUT"; exit 1
}
SPRITE_CREATED=true
ok "Sprite '${SPRITE_NAME}' created"
[[ "$VERBOSE" == true ]] && echo "$CREATE_OUTPUT"

info "Verifying sprite appears in list..."
LIST_OUTPUT=$(sprite list $ORG_FLAG 2>&1)
echo "$LIST_OUTPUT" | grep -q "$SPRITE_NAME" && ok "Sprite confirmed in list" \
  || warn "Sprite not found in list output (may be org-scoped)"

WORKSPACE_DIR="/work/jido-test-${RUN_ID}"
info "Creating workspace: ${WORKSPACE_DIR}"
sprite_exec "mkdir -p ${WORKSPACE_DIR}" || { fail "Failed to create workspace directory"; exit 1; }
ok "Workspace created"

# ═══════════════════════════════════════════════════════════════════════════
# STEP 3: Validate runtime inside sprite
# ═══════════════════════════════════════════════════════════════════════════
step "Step 3: Validate Runtime Inside Sprite"

GIT_CHECK=$(sprite_exec "command -v git >/dev/null 2>&1 && git --version || echo MISSING")
echo "$GIT_CHECK" | grep -q "MISSING" && { fail "git not found inside sprite"; exit 1; }
ok "git: $GIT_CHECK"

GH_CHECK=$(sprite_exec "command -v gh >/dev/null 2>&1 && gh --version | head -1 || echo MISSING")
echo "$GH_CHECK" | grep -q "MISSING" && { fail "gh CLI not found inside sprite"; exit 1; }
ok "gh: $GH_CHECK"

# ═══════════════════════════════════════════════════════════════════════════
# STEP 4: Validate GitHub auth inside sprite
# ═══════════════════════════════════════════════════════════════════════════
step "Step 4: Validate GitHub Auth Inside Sprite"

TOKEN_CHECK=$(sprite_exec 'if [ -n "${GH_TOKEN:-}" ] || [ -n "${GITHUB_TOKEN:-}" ]; then echo present; else echo missing; fi')
echo "$TOKEN_CHECK" | grep -q "missing" && {
  fail "GitHub token not visible inside sprite"; exit 1
}
ok "GitHub token visible inside sprite"

AUTH_CHECK=$(sprite_exec "gh auth status -h github.com 2>&1 || gh auth status 2>&1" 2>&1)
AUTH_RC=$?
if [[ $AUTH_RC -eq 0 ]] || echo "$AUTH_CHECK" | grep -qi "logged in"; then
  ok "gh auth status: authenticated"
else
  warn "gh auth status returned non-zero (rc=$AUTH_RC)"
  info "Testing direct gh API call..."
  API_TEST=$(sprite_exec "gh api user --jq .login 2>&1")
  if [[ -n "$API_TEST" ]] && ! echo "$API_TEST" | grep -qi "error\|fail"; then
    ok "gh API works — authenticated as: $API_TEST"
  else
    fail "gh authentication not working inside sprite"; exit 1
  fi
fi

# ═══════════════════════════════════════════════════════════════════════════
# STEP 5: Fetch issue details inside sprite
# ═══════════════════════════════════════════════════════════════════════════
step "Step 5: Fetch Issue Details Inside Sprite"

SPRITE_ISSUE_TITLE=$(sprite_exec "gh issue view ${ISSUE_NUMBER} --repo ${OWNER}/${REPO} --json title --jq .title") || {
  fail "Failed to fetch issue title inside sprite"; exit 1
}
SPRITE_ISSUE_STATE=$(sprite_exec "gh issue view ${ISSUE_NUMBER} --repo ${OWNER}/${REPO} --json state --jq .state") || {
  fail "Failed to fetch issue state inside sprite"; exit 1
}

ok "Issue title: \"${SPRITE_ISSUE_TITLE}\""
ok "Issue state: ${SPRITE_ISSUE_STATE}"

if [[ "$VERBOSE" == true ]]; then
  sprite_exec "gh issue view ${ISSUE_NUMBER} --repo ${OWNER}/${REPO} --json title,body,labels,author,state,url" || true
fi

# ═══════════════════════════════════════════════════════════════════════════
# STEP 6: Clone repo inside sprite
# ═══════════════════════════════════════════════════════════════════════════
step "Step 6: Clone Repository Inside Sprite"

REPO_DIR="${WORKSPACE_DIR}/${REPO}"
info "Cloning ${OWNER}/${REPO} into ${REPO_DIR}..."
sprite_exec "git clone https://github.com/${OWNER}/${REPO}.git ${REPO_DIR}" >/dev/null || {
  fail "git clone failed"; exit 1
}
ok "Repository cloned"

VERIFY_CLONE=$(sprite_exec "ls ${REPO_DIR}/.git/HEAD && echo CLONE_OK || echo CLONE_FAIL")
echo "$VERIFY_CLONE" | grep -q "CLONE_OK" && ok "Clone verified (.git/HEAD exists)" \
  || { fail "Clone verification failed"; exit 1; }

# ═══════════════════════════════════════════════════════════════════════════
# STEP 7: Configure git identity inside sprite
# ═══════════════════════════════════════════════════════════════════════════
step "Step 7: Configure Git Identity & Credentials"

sprite_exec "git config user.email 'jido-bot@agentjido.com' && git config user.name 'Jido Bot'" "$REPO_DIR" || {
  fail "Failed to configure git identity"; exit 1
}
ok "Git identity configured"

sprite_exec "gh auth setup-git" "$REPO_DIR" || {
  fail "Failed to configure gh as git credential helper"; exit 1
}
ok "gh auth setup-git configured"

# ═══════════════════════════════════════════════════════════════════════════
# STEP 8: Resolve base branch & create PR branch
# ═══════════════════════════════════════════════════════════════════════════
step "Step 8: Create PR Branch"

BASE_BRANCH=$(sprite_exec "gh repo view ${OWNER}/${REPO} --json defaultBranchRef -q .defaultBranchRef.name" "$REPO_DIR") || {
  fail "Failed to resolve default branch"; exit 1
}
BASE_BRANCH=$(echo "$BASE_BRANCH" | tr -d '[:space:]')
ok "Base branch: ${BASE_BRANCH}"

info "Syncing base branch..."
sprite_exec "git fetch origin ${BASE_BRANCH} && git checkout ${BASE_BRANCH} && git pull --ff-only origin ${BASE_BRANCH}" "$REPO_DIR" >/dev/null || {
  fail "Failed to sync base branch"; exit 1
}
ok "Base branch synced"

BRANCH_NAME="${BRANCH_PREFIX}/issue-${ISSUE_NUMBER}-${RUN_ID}"

BRANCH_EXISTS=$(sprite_exec "
if git show-ref --verify --quiet refs/heads/${BRANCH_NAME}; then
  echo exists
elif git ls-remote --exit-code --heads origin ${BRANCH_NAME} >/dev/null 2>&1; then
  echo exists
else
  echo missing
fi" "$REPO_DIR")

if echo "$BRANCH_EXISTS" | grep -q "exists"; then
  fail "Branch ${BRANCH_NAME} already exists"; exit 1
fi

sprite_exec "git checkout -b ${BRANCH_NAME}" "$REPO_DIR" >/dev/null || {
  fail "Failed to create branch ${BRANCH_NAME}"; exit 1
}
ok "Branch created: ${BRANCH_NAME}"

BASE_SHA=$(sprite_exec "git rev-parse ${BASE_BRANCH}" "$REPO_DIR") || {
  fail "Failed to get base SHA"; exit 1
}
BASE_SHA=$(echo "$BASE_SHA" | tr -d '[:space:]')
ok "Base SHA: ${BASE_SHA:0:12}"

# ═══════════════════════════════════════════════════════════════════════════
# STEP 9: Provider provisioning + stream-json validation
# ═══════════════════════════════════════════════════════════════════════════
step "$(provider_step_9_title)"

ensure_provider_cli_in_sprite
prepare_provider_runtime

SMOKE_PROMPT_FILE="/tmp/jido_${PROVIDER}_smoke_prompt_${RUN_ID}.txt"
SMOKE_PROMPT="$(provider_smoke_prompt)"
write_sprite_prompt_file "$SMOKE_PROMPT" "$SMOKE_PROMPT_FILE" "$REPO_DIR"

info "Running ${PROVIDER_LABEL} smoke prompt in stream mode..."
SMOKE_CMD="$(provider_smoke_command "$SMOKE_PROMPT_FILE")"
run_stream_json "smoke" "$SMOKE_CMD" "$REPO_DIR" || {
  fail "${PROVIDER_LABEL} smoke command failed"
  exit 1
}

if [[ -n "$LAST_STREAM_RESULT_TEXT" ]]; then
  ok "${PROVIDER_LABEL} smoke returned text"
else
  warn "${PROVIDER_LABEL} smoke returned no final text (events captured: ${LAST_STREAM_EVENT_COUNT})"
fi

# ═══════════════════════════════════════════════════════════════════════════
# STEP 10: Provider performs code change
# ═══════════════════════════════════════════════════════════════════════════
step "$(provider_step_10_title)"

TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
CHANGE_PROMPT_FILE="/tmp/jido_${PROVIDER}_change_prompt_${RUN_ID}.txt"
CHANGE_PROMPT="$(provider_change_prompt "$TIMESTAMP")"
write_sprite_prompt_file "$CHANGE_PROMPT" "$CHANGE_PROMPT_FILE" "$REPO_DIR"

info "Running ${PROVIDER_LABEL} code-change prompt in stream mode..."
CHANGE_CMD="$(provider_change_command "$CHANGE_PROMPT_FILE")"
run_stream_json "change" "$CHANGE_CMD" "$REPO_DIR" || {
  fail "${PROVIDER_LABEL} code-change command failed"
  exit 1
}

VERIFY_FILE=$(sprite_exec "test -f .jido-smoke-test.md && wc -c < .jido-smoke-test.md || echo 0" "$REPO_DIR")
VERIFY_FILE=$(echo "$VERIFY_FILE" | tr -d '[:space:]')
if [[ "$VERIFY_FILE" -gt 0 ]] 2>/dev/null; then
  ok "${PROVIDER_LABEL} created .jido-smoke-test.md (${VERIFY_FILE} bytes)"
else
  fail "${PROVIDER_LABEL} did not create the expected file"
  sprite_exec "ls -la" "$REPO_DIR" >&2
  exit 1
fi

# ═══════════════════════════════════════════════════════════════════════════
# STEP 11: Commit
# ═══════════════════════════════════════════════════════════════════════════
step "Step 11: Commit Changes"

DIRTY_CHECK=$(sprite_exec "git status --porcelain" "$REPO_DIR")
if [[ -z "$DIRTY_CHECK" ]]; then
  fail "Working tree is clean — no changes to commit"; exit 1
fi
ok "Working tree has changes"
[[ "$VERBOSE" == true ]] && echo "$DIRTY_CHECK"

sprite_exec "git add -A && git commit -m 'test(smoke): sprite ${PROVIDER_LABEL} PrBot plumbing test #${ISSUE_NUMBER}'" "$REPO_DIR" >/dev/null || {
  fail "git commit failed"; exit 1
}
ok "Changes committed"

COMMIT_COUNT=$(sprite_exec "git rev-list --count ${BASE_SHA}..HEAD" "$REPO_DIR")
COMMIT_COUNT=$(echo "$COMMIT_COUNT" | tr -d '[:space:]')
ok "Commits since base: ${COMMIT_COUNT}"

COMMIT_SHA=$(sprite_exec "git rev-parse HEAD" "$REPO_DIR")
COMMIT_SHA=$(echo "$COMMIT_SHA" | tr -d '[:space:]')
ok "Commit SHA: ${COMMIT_SHA:0:12}"

# ═══════════════════════════════════════════════════════════════════════════
# STEP 12: Push branch
# ═══════════════════════════════════════════════════════════════════════════
step "Step 12: Push Branch"

ORIGIN_URL=$(sprite_exec "git remote get-url origin" "$REPO_DIR")
if ! echo "$ORIGIN_URL" | grep -q "${OWNER}/${REPO}"; then
  fail "Remote origin mismatch: $ORIGIN_URL (expected ${OWNER}/${REPO})"; exit 1
fi
ok "Remote origin verified: $ORIGIN_URL"

if [[ "$DRY_RUN" == true ]]; then
  warn "DRY RUN: Would push branch ${BRANCH_NAME}"
else
  info "Pushing ${BRANCH_NAME}..."
  PUSH_OUTPUT=$(sprite_exec "git push -u origin ${BRANCH_NAME}" "$REPO_DIR" 2>&1) || {
    fail "git push failed: $PUSH_OUTPUT"; exit 1
  }
  ok "Branch pushed"
  [[ "$VERBOSE" == true ]] && echo "$PUSH_OUTPUT"
fi

# ═══════════════════════════════════════════════════════════════════════════
# STEP 13: Create pull request
# ═══════════════════════════════════════════════════════════════════════════
step "Step 13: Create Pull Request"

PR_TITLE="Fix #${ISSUE_NUMBER}: ${SPRITE_ISSUE_TITLE}"
PR_BODY_FILE="/tmp/jido_pr_body_${RUN_ID}.md"

sprite_exec "cat > ${PR_BODY_FILE} << 'JIDO_PR_BODY_EOF'
## Automated PR from Jido PrBot (smoke test: ${PROVIDER_LABEL})

Resolves issue #${ISSUE_NUMBER}
Issue URL: ${ISSUE_URL}
Run ID: ${RUN_ID}
Branch: ${BRANCH_NAME}
Provider: ${PROVIDER_LABEL}
JIDO_PR_BODY_EOF" "$REPO_DIR" || {
  fail "Failed to write PR body file"; exit 1
}
ok "PR body written"

if [[ "$DRY_RUN" == true ]]; then
  warn "DRY RUN: Would create PR '${PR_TITLE}'"
  warn "  base=${BASE_BRANCH} head=${BRANCH_NAME}"
else
  info "Creating PR..."
  PR_OUTPUT=$(sprite_exec "gh pr create --repo ${OWNER}/${REPO} --base ${BASE_BRANCH} --head ${BRANCH_NAME} --title '${PR_TITLE}' --body-file ${PR_BODY_FILE}" "$REPO_DIR" 2>&1) || {
    fail "gh pr create failed: $PR_OUTPUT"; exit 1
  }

  PR_URL=$(echo "$PR_OUTPUT" | grep -oE 'https://github\.com/[^ ]+/pull/[0-9]+' | head -1)
  if [[ -z "$PR_URL" ]]; then
    PR_URL=$(sprite_exec "gh pr list --repo ${OWNER}/${REPO} --head ${BRANCH_NAME} --state open --json url --jq '.[0].url'" "$REPO_DIR")
  fi

  if [[ -n "$PR_URL" ]]; then
    ok "PR created: ${PR_URL}"
  else
    warn "PR created but could not extract URL"
    [[ "$VERBOSE" == true ]] && echo "$PR_OUTPUT"
  fi
fi

# ═══════════════════════════════════════════════════════════════════════════
# STEP 14: Comment on issue with PR link
# ═══════════════════════════════════════════════════════════════════════════
step "Step 14: Comment Issue With PR Link"

COMMENT_BODY_FILE="/tmp/jido_pr_issue_comment_${RUN_ID}.md"

sprite_exec "cat > ${COMMENT_BODY_FILE} << 'JIDO_ISSUE_PR_EOF'
✅ Automated PR created for this issue.

- PR: ${PR_URL:-[dry-run]}
- Branch: \`${BRANCH_NAME}\`
- Commit: \`${COMMIT_SHA:0:12}\`
- Run ID: \`${RUN_ID}\`
- Sprite: \`${SPRITE_NAME}\`
- Provider: \`${PROVIDER_LABEL}\`
- Timestamp: ${TIMESTAMP}

_Posted by \`${SCRIPT_NAME}\` smoke test._
JIDO_ISSUE_PR_EOF" "$REPO_DIR" || {
  fail "Failed to write issue comment body"; exit 1
}
ok "Issue comment body written"

if [[ "$DRY_RUN" == true ]]; then
  warn "DRY RUN: Would comment on ${OWNER}/${REPO}#${ISSUE_NUMBER}"
else
  info "Posting comment to ${OWNER}/${REPO}#${ISSUE_NUMBER}..."
  COMMENT_OUTPUT=$(sprite_exec "gh issue comment ${ISSUE_NUMBER} --repo ${OWNER}/${REPO} --body-file ${COMMENT_BODY_FILE}" "$REPO_DIR" 2>&1)
  COMMENT_RC=$?

  if [[ $COMMENT_RC -eq 0 ]]; then
    ok "Comment posted successfully!"
    [[ -n "$COMMENT_OUTPUT" ]] && info "Comment URL: $COMMENT_OUTPUT"
  else
    fail "gh issue comment failed (rc=$COMMENT_RC): $COMMENT_OUTPUT"
    exit 1
  fi
fi

# ═══════════════════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════════════════
step "Summary"

echo ""
ok "All checks passed! ✅"
echo ""
info "What was validated:"
echo "   1. Host env: SPRITES_TOKEN, GH_TOKEN/GITHUB_TOKEN"
echo "   2. Sprite lifecycle: create → exec → (destroy on exit)"
echo "   3. Env var forwarding via sprite exec -env"
echo "   4. Runtime binaries inside sprite: git, gh, $(provider_binary)"
echo "   5. GitHub auth inside sprite: gh auth status"
echo "   6. gh issue view from inside sprite"
echo "   7. git clone from inside sprite"
echo "   8. git config identity + gh auth setup-git"
echo "   9. ${PROVIDER_LABEL} stream-JSON smoke prompt"
echo "  10. ${PROVIDER_LABEL} stream-JSON code change"
echo "  11. git add + git commit"
echo "  12. git push -u origin"
echo "  13. gh pr create"
echo "  14. gh issue comment --body-file (PR link back to issue)"
echo ""
info "Provider: ${PROVIDER_LABEL}"
info "Sprite:   ${SPRITE_NAME}"
info "Run ID:   ${RUN_ID}"
info "Branch:   ${BRANCH_NAME}"
[[ -n "${PR_URL:-}" ]] && info "PR:       ${PR_URL}"

if [[ "${#ARTIFACTS[@]}" -gt 0 ]]; then
  info "Stream JSON artifacts:"
  for artifact in "${ARTIFACTS[@]}"; do
    info "  ${artifact}"
  done
fi

if [[ "$KEEP_SPRITE" == true ]]; then
  warn "Sprite kept alive — destroy manually with:"
  warn "  sprite destroy -s ${SPRITE_NAME} --force"
fi
