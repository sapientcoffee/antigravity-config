#!/bin/bash
set -euo pipefail

# ─── Truecolor Palette (Catppuccin Mocha) ────────────────────────────────────
R="\033[0m"         # Reset
B="\033[1m"         # Bold
D="\033[2m"         # Dim
I="\033[3m"         # Italic

# Catppuccin Macchiato Accent Colors
CLR_MAUVE="\033[38;2;198;160;246m"
CLR_GREEN="\033[38;2;166;218;149m"
CLR_YELLOW="\033[38;2;238;212;159m"
CLR_SKY="\033[38;2;145;215;227m"
CLR_BLUE="\033[38;2;138;173;244m"
CLR_RED="\033[38;2;237;135;150m"
CLR_PEACH="\033[38;2;245;169;127m"
CLR_WHITE="\033[38;2;202;211;245m"
CLR_GRAY="\033[38;2;110;115;141m"     # Overlay0
CLR_SURFACE="\033[38;2;73;77;100m"    # Surface1 (dimmer)
CLR_CYAN="\033[38;2;145;215;227m"

# ─── Read JSON from stdin Safely ─────────────────────────────────────────────
DATA=$(cat)
if [[ ! "$DATA" =~ ^[[:space:]]*\{ ]]; then
  DATA='{"agent_state":"idle"}'
fi

# ─── Parse JSON from stdin (Single jq pass for performance) ──────────────────
{
  read -r STATE
  read -r USED_PCT
  read -r VCS_BRANCH
  read -r VCS_DIRTY
  read -r SANDBOX
  read -r ARTIFACT_COUNT
  read -r SUBAGENTS_COUNT
  read -r BG_TASKS_COUNT
  read -r MODEL
  read -r COLS
  read -r SESSION_ID
  read -r TOKENS_IN
  read -r TOKENS_OUT
  read -r TOKENS_SIZE
  read -r CWD
  read -r PENDING_INPUT
  read -r CONFIRM_PENDING
  read -r AGENT_NAME
  read -r ALLOW_NET
  read -r VCS_TYPE
  read -r PRODUCT
  read -r VERSION
  read -r PLAN_TIER
  read -r EMAIL
  read -r CACHE_READ_TOKENS
  read -r VCS_CLIENT
  read -r _ # Dummy read for END token
} <<< "$(
  echo "$DATA" | jq -r '
    (.agent_state // "idle"),
    (.context_window.used_percentage // 0),
    (.vcs.branch // ""),
    (.vcs.dirty // false),
    (.sandbox.enabled // false),
    (if .artifacts | type == "array" then (.artifacts | length) else (.artifact_count // 0) end),
    (if .subagents | type == "array" then (.subagents | length) else 0 end),
    (if .background_tasks | type == "array" then (.background_tasks | length) else (.task_count // 0) end),
    (.model.display_name // ""),
    (.terminal_width // 80),
    (.session_id // .conversation_id // ""),
    (.context_window.total_input_tokens // 0),
    (.context_window.total_output_tokens // 0),
    (.context_window.context_window_size // 0),
    (.cwd // ""),
    (.pending_input_count // 0),
    (.tool_confirmation_pending // false),
    (if .agent | type == "object" then (.agent.name // "") elif .agent | type == "string" then .agent else "" end),
    (.sandbox.allow_network // false),
    (.vcs.type // "git"),
    (.product // ""),
    (.version // ""),
    (.plan_tier // ""),
    (.email // ""),
    (.context_window.current_usage.cache_read_input_tokens // 0),
    (.vcs.client // ""),
    "END"
  ' 2>/dev/null || printf "idle\n0\n\nfalse\nfalse\n0\n0\n0\n\n80\n\n0\n0\n0\n\n0\nfalse\n\nfalse\ngit\n\n\n\n\n0\n\nEND"
)"

# ─── Computed Values & Sanitization ──────────────────────────────────────────
PCT_FMT=$(LC_NUMERIC=C printf "%.1f" "$USED_PCT")
PCT_INT=${USED_PCT%.*}; PCT_INT=${PCT_INT:-0}

# ─── Token Formatting Helper (Pure Bash arithmetic) ──────────────────────────
format_tokens() {
  local count=$1
  if [ "$count" -ge 1000000 ]; then
    local div=$((count / 100000))
    echo "$((div / 10)).$((div % 10))M"
  elif [ "$count" -ge 1000 ]; then
    local div=$((count / 100))
    echo "$((div / 10)).$((div % 10))k"
  else
    echo "$count"
  fi
}

# Helper to calculate printable string length (stripping escape codes)
visible_len() {
  local str="$1"
  local stripped
  stripped=$(echo -e "$str" | sed -E 's/\x1bP[^\x1b]*\x1b\\//g; s/\x1b\][^\x07]*\x07//g; s/\x1b\[[0-9;]*[a-zA-Z]//g' | tr -d '\n' | tr -d '\r')
  echo "${#stripped}"
}

# Divider for Line 1 modules (dimmed gray bullet)
DIVIDER="  ${CLR_SURFACE}•${R}  "

# 1. Directory Module
format_dir() {
  local dir="${1:-}"
  if [ -z "$dir" ]; then
    echo ""
    return
  fi

  # Replace $HOME with ~
  if [[ "$dir" == "$HOME" ]]; then
    dir="~"
  elif [[ "$dir" == "$HOME/"* ]]; then
    dir="~${dir#$HOME}"
  fi

  # Truncate to last 3 levels
  local IFS='/'
  read -ra parts <<< "$dir"
  local count=${#parts[@]}
  if [ "$count" -gt 3 ]; then
    dir="…/${parts[$((count-3))]}/${parts[$((count-2))]}/${parts[$((count-1))]}"
  fi

  # Append lock icon if read-only
  if [ ! -w "$1" ]; then
    dir="${dir} "
  fi

  echo -n "$dir"
}

DIR_STR=$(format_dir "$CWD")
DIR_MOD="${CLR_CYAN}${B}  ${DIR_STR}${R}"

# 2. Git Module
format_git() {
  local branch="${1:-}"
  local dirty="${2:-false}"
  if [ -z "$branch" ]; then
    return
  fi

  local git_str="${CLR_MAUVE}${B}  ${branch}${R}"

  # Check ahead/behind if we are in a Git repo
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    local status_sb
    status_sb=$(git status -sb 2>/dev/null | head -n 1)
    if [[ "$status_sb" =~ \[ahead\ ([0-9]+)\] ]]; then
      git_str="${git_str} ⇡${BASH_REMATCH[1]}"
    elif [[ "$status_sb" =~ \[behind\ ([0-9]+)\] ]]; then
      git_str="${git_str} ⇣${BASH_REMATCH[1]}"
    elif [[ "$status_sb" =~ \[ahead\ ([0-9]+),\ behind\ ([0-9]+)\] ]]; then
      git_str="${git_str} ⇡${BASH_REMATCH[1]}⇣${BASH_REMATCH[2]}"
    fi
  fi

  if [ "$dirty" = "true" ]; then
    git_str="${git_str}${CLR_YELLOW}*${R}"
  fi

  echo -n "$git_str"
}

# Fallback Git detection if CLI JSON did not provide it
if [ -z "$VCS_BRANCH" ] || [ "$VCS_BRANCH" = "null" ]; then
  VCS_BRANCH=""
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    VCS_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
    VCS_TYPE="git"
  fi
fi

if [ -n "$VCS_BRANCH" ] && [ "${VCS_DIRTY:-}" != "true" ]; then
  if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
    VCS_DIRTY="true"
  fi
fi

GIT_MOD=""
if [ -n "$VCS_BRANCH" ]; then
  GIT_MOD="${DIVIDER}$(format_git "$VCS_BRANCH" "$VCS_DIRTY")"
fi

# 3. Google Cloud Project Module
# Style: Bold Blue. Format: 󰅟 [project_name]
GCP_MOD=""
ACTIVE_CFG=$(cat "$HOME/.config/gcloud/active_config" 2>/dev/null || echo "default")
CFG_FILE="$HOME/.config/gcloud/configurations/config_${ACTIVE_CFG}"
if [ -f "$CFG_FILE" ]; then
  GCP_PROJECT=$(awk -F '=[[:space:]]*' '/^[[:space:]]*project[[:space:]]*=/ {print $2}' "$CFG_FILE" | tr -d '[:space:]')
  GCP_ACCOUNT=$(awk -F '=[[:space:]]*' '/^[[:space:]]*account[[:space:]]*=/ {print $2}' "$CFG_FILE" | tr -d '[:space:]')
  if [ -n "$GCP_PROJECT" ] && [ -n "$GCP_ACCOUNT" ]; then
    if [ -d "$HOME/.config/gcloud/legacy_credentials/$GCP_ACCOUNT" ] || [ -f "$HOME/.config/gcloud/credentials.db" ]; then
      GCP_MOD="${DIVIDER}${CLR_BLUE}${B}󰅟  ${GCP_PROJECT}${R}"
    fi
  fi
fi

# 4. Kubernetes Context Module
# Style: Bold Green. Format: 󱃾  [context_name]
K8S_MOD=""
K8S_CONFIG="$HOME/.kube/config"
if [ -f "$K8S_CONFIG" ]; then
  CUR_CTX=$(awk '/^current-context:/ {print $2}' "$K8S_CONFIG" | tr -d '[:space:]')
  if [ -n "$CUR_CTX" ]; then
    if [[ "$CUR_CTX" =~ ^gke_[^_]+_(.+)$ ]]; then
      CUR_CTX="${BASH_REMATCH[1]}"
      CUR_CTX="${CUR_CTX//_//}"
    fi
    K8S_MOD="${DIVIDER}${CLR_GREEN}${B}󱃾  ${CUR_CTX}${R}"
  fi
fi

# 5. Tmux Session Module
# Style: Bold Peach. Format:   [session_name]
TMUX_MOD=""
if [ -n "${TMUX:-}" ]; then
  TMUX_SESS=$(tmux display-message -p '#S' 2>/dev/null || echo "tmux")
  if [ -n "$TMUX_SESS" ]; then
    TMUX_MOD="${DIVIDER}${CLR_PEACH}${B}  ${TMUX_SESS}${R}"
  fi
fi

LINE1_LEFT="${DIR_MOD}${GIT_MOD}${GCP_MOD}${K8S_MOD}${TMUX_MOD}"
LINE1_LEFT_LEN=$(visible_len "$LINE1_LEFT")

# 4. Timestamp (Right-aligned)
# Style: Dimmed Gray. Format: 24-hour format with timezone (e.g., 17:04:44 PDT)
TIMESTAMP_STR=$(date +"%H:%M:%S %Z")
TIMESTAMP="${CLR_GRAY}${TIMESTAMP_STR}${R}"
TIMESTAMP_LEN=$(visible_len "$TIMESTAMP")

# Determine terminal width (dynamic calculation)
COLS=${COLS:-80}
GAP=$((COLS - LINE1_LEFT_LEN - TIMESTAMP_LEN - 4))
SPACES=""
if [ "$GAP" -gt 0 ]; then
  for ((i = 0; i < GAP; i++)); do
    SPACES="${SPACES} "
  done
fi

LINE1="  ${LINE1_LEFT}${SPACES}${TIMESTAMP}  "


# ─── LINE 2: Antigravity Core Operations ──────────────────────────────────────

# 1. Model & Status Module
# Format: [󰚩 3.5 Flash (High)  •  󰦛 IDLE]
M_NAME="${MODEL:-Gemini 3.5 Flash}"
M_NAME="${M_NAME#Gemini }"
M_NAME="${M_NAME#gemini }"

if [ "$CONFIRM_PENDING" = "true" ]; then
  STATUS_BADGE="${CLR_WHITE}[󰚩  ${M_NAME}  ${CLR_SURFACE}•${R}  ${CLR_RED}${B}󰒃  CONFIRMING${CLR_WHITE}]${R}"
else
  case "$STATE" in
    idle)     STATUS_BADGE="${CLR_WHITE}[󰚩  ${M_NAME}  ${CLR_SURFACE}•${R}  ${CLR_GRAY}󰦵  WATCHING${CLR_WHITE}]${R}" ;;
    working|thinking|tool_use|initializing)
              STATUS_BADGE="${CLR_WHITE}[󰚩  ${M_NAME}  ${CLR_SURFACE}•${R}  ${CLR_GREEN}${B}󱑮  WORKING${CLR_WHITE}]${R}" ;;
    *)        STATUS_BADGE="${CLR_WHITE}[󰚩  ${M_NAME}  ${CLR_SURFACE}•${R}  ${CLR_WHITE}󰖦  $(echo "$STATE" | tr '[:lower:]' '[:upper:]')${CLR_WHITE}]${R}" ;;
  esac
fi

# 2. Context Visualizer Module
# Format: [ctx [▓▓▓.......] 5.1% (53.7k/1.6M) (󱐋 31.2k cached)]
BAR_LEN=10
FILLED=$((PCT_INT * BAR_LEN / 100))
BAR=""
for ((i = 0; i < BAR_LEN; i++)); do
  if [ "$i" -lt "$FILLED" ]; then
    BAR="${BAR}▓"
  else
    BAR="${BAR}."
  fi
done

if [ "$PCT_INT" -ge 80 ]; then
  BAR_COLOR="$CLR_RED"
elif [ "$PCT_INT" -ge 50 ]; then
  BAR_COLOR="$CLR_YELLOW"
else
  BAR_COLOR="$CLR_GREEN"
fi

IN_FMT=$(format_tokens "$TOKENS_IN")
SIZE_FMT=$(format_tokens "$TOKENS_SIZE")

CACHE_STR=""
if [ "$CACHE_READ_TOKENS" -gt 0 ]; then
  CACHE_FMT=$(format_tokens "$CACHE_READ_TOKENS")
  CACHE_STR=" (󱐋 ${CACHE_FMT} cached)"
fi

CTX_BADGE="${CLR_WHITE}[ctx [${BAR_COLOR}${BAR}${R}] ${CLR_WHITE}${B}${PCT_FMT}%${R} (${CLR_WHITE}${IN_FMT}/${SIZE_FMT}${R})${CACHE_STR}]${R}"

# 3. Local Resource Pressures (Load Average)
LOAD_BADGE=""
if [ -f "/proc/loadavg" ]; then
  ONE_MIN_LOAD=$(awk '{print $1}' /proc/loadavg)
  LOAD_INT=${ONE_MIN_LOAD%.*}
  LOAD_INT=${LOAD_INT:-0}
  
  if [ "$LOAD_INT" -ge 8 ]; then
    LOAD_BADGE="  ${CLR_RED}${B}󰐎  ${ONE_MIN_LOAD}${R}"
  elif [ "$LOAD_INT" -ge 4 ]; then
    LOAD_BADGE="  ${CLR_YELLOW}󰐎  ${ONE_MIN_LOAD}${R}"
  else
    LOAD_BADGE="  ${CLR_SURFACE}󰐎  ${ONE_MIN_LOAD}${R}"
  fi
fi

# 4. Dynamic Metrics Module (Strictly Conditional / Hide Zero-Values)
# Count configured MCP servers
MCP_AVAIL=$(jq -s 'map(.mcpServers | keys) | flatten | length' ~/.gemini/antigravity-cli/plugins/*/mcp_config.json 2>/dev/null || echo 0)

ACTIVE_METRICS=""
if [ "$BG_TASKS_COUNT" -gt 0 ]; then
  ACTIVE_METRICS="󰖷  ${BG_TASKS_COUNT} Task$([ "$BG_TASKS_COUNT" -eq 1 ] && echo "" || echo "s")"
fi

if [ "$ARTIFACT_COUNT" -gt 0 ]; then
  if [ -n "$ACTIVE_METRICS" ]; then ACTIVE_METRICS="${ACTIVE_METRICS}  ${CLR_SURFACE}•${R}  "; fi
  ACTIVE_METRICS="${ACTIVE_METRICS}󰏖  ${ARTIFACT_COUNT} Artifact$([ "$ARTIFACT_COUNT" -eq 1 ] && echo "" || echo "s")"
fi

if [ "$MCP_AVAIL" -gt 0 ]; then
  if [ -n "$ACTIVE_METRICS" ]; then ACTIVE_METRICS="${ACTIVE_METRICS}  ${CLR_SURFACE}•${R}  "; fi
  ACTIVE_METRICS="${ACTIVE_METRICS}󰚥  ${MCP_AVAIL} MCP"
fi

if [ "$SUBAGENTS_COUNT" -gt 0 ]; then
  if [ -n "$ACTIVE_METRICS" ]; then ACTIVE_METRICS="${ACTIVE_METRICS}  ${CLR_SURFACE}•${R}  "; fi
  ACTIVE_METRICS="${ACTIVE_METRICS}󰉊  ${SUBAGENTS_COUNT} Subagent$([ "$SUBAGENTS_COUNT" -eq 1 ] && echo "" || echo "s")"
fi

METRICS_BADGE=""
if [ -n "$ACTIVE_METRICS" ]; then
  # Style: Bold Orange/Peach to highlight background operations holding state
  METRICS_BADGE=" ${CLR_PEACH}[${B}${ACTIVE_METRICS}${R}${CLR_PEACH}]${R}"
fi

LINE2="  ${STATUS_BADGE} ${CTX_BADGE}${LOAD_BADGE}${METRICS_BADGE}"


# ─── Render Statusline ────────────────────────────────────────────────────────
echo -e "${LINE1}"
echo -e "${LINE2}"
