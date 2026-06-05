#!/bin/bash
set -euo pipefail

# ─── Truecolor Palette (Catppuccin Mocha) ────────────────────────────────────
R="\033[0m"         # Reset
B="\033[1m"         # Bold
D="\033[2m"         # Dim
I="\033[3m"         # Italic

# Foreground Colors
CLR_MAUVE="\033[38;2;203;166;247m"
CLR_GREEN="\033[38;2;166;227;161m"
CLR_YELLOW="\033[38;2;249;226;175m"
CLR_SKY="\033[38;2;137;220;235m"
CLR_BLUE="\033[38;2;137;180;250m"
CLR_RED="\033[38;2;243;139;168m"
CLR_PEACH="\033[38;2;250;179;135m"
CLR_WHITE="\033[38;2;205;214;244m"
CLR_GRAY="\033[38;2;108;112;134m"     # Overlay0
CLR_SURFACE="\033[38;2;88;91;112m"    # Surface1 (dimmer)

# ─── Parse JSON from stdin (Single jq pass for performance) ──────────────────
# Read stdin safely with fallback for empty or non-JSON payloads
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
  read -r SUBAGENTS_DETAILS
  read -r BG_TASKS_DETAILS
  read -r ARTIFACTS_DETAILS
  read -r _ # Dummy read for END token to prevent trailing newline trimming issues
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
    (if .subagents | type == "array" and (.subagents | length) > 0 then ([.subagents[] | (.name // "agent") + ":" + (.status // "idle")] | join(",")) else "" end),
    (if .background_tasks | type == "array" and (.background_tasks | length) > 0 then ([.background_tasks[] | .name // "task"] | join(",")) else "" end),
    (if .artifacts | type == "array" and (.artifacts | length) > 0 then ([.artifacts[] | .type // "file"] | join(",")) else "" end),
    "END"
  ' 2>/dev/null || printf "idle\n0\n\nfalse\nfalse\n0\n0\n0\n\n80\n\n0\n0\n\n0\nfalse\n\nfalse\ngit\n\n\n\n\n0\n\n\n\nEND"
)"

# ─── Computed Values & Sanitization ──────────────────────────────────────────
PCT_FMT=$(LC_NUMERIC=C printf "%.1f" "$USED_PCT")
PCT_INT=${USED_PCT%.*}; PCT_INT=${PCT_INT:-0}

# ─── Compute System Stats (Pure Bash /proc/meminfo read - extremely fast) ────
MEM_PCT=0
if [ -r /proc/meminfo ]; then
  mem_total=0
  mem_avail=0
  while read -r name value unit; do
    if [ "$name" = "MemTotal:" ]; then
      mem_total=$value
    elif [ "$name" = "MemAvailable:" ]; then
      mem_avail=$value
      break
    fi
  done < /proc/meminfo
  if [ "$mem_total" -gt 0 ]; then
    MEM_PCT=$(( 100 * (mem_total - mem_avail) / mem_total ))
  fi
fi

DISK_PCT=0
if hash df 2>/dev/null; then
  DISK_PCT=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%' || echo 0)
fi

# ─── Compute Code Changes (Git/Yadm status porcelain) ─────────────────────────
CHANGES_STR=""
changes_count=0
if [ -n "$VCS_BRANCH" ]; then
  changes_count=$(git status --porcelain 2>/dev/null | wc -l | tr -d '[:space:]')
  if [[ "$changes_count" =~ ^[0-9]+$ ]] && [ "$changes_count" -gt 0 ]; then
    CHANGES_STR="${changes_count}Δ"
  fi
else
  if [ "$CWD" = "$HOME" ] && hash yadm 2>/dev/null; then
    changes_count=$(yadm status --porcelain 2>/dev/null | wc -l | tr -d '[:space:]')
    if [[ "$changes_count" =~ ^[0-9]+$ ]] && [ "$changes_count" -gt 0 ]; then
      CHANGES_STR="${changes_count}Δ"
    fi
  fi
fi

# ─── Compute AI Workspace Resources (Skills, MCP, Context Files, Subagents) ──
# Count available skills
SKILLS_AVAIL=$(find ~/.gemini/antigravity-cli/plugins/ -mindepth 3 -maxdepth 3 -type d -path "*/skills/*" 2>/dev/null | wc -l || echo 0)

# Count configured MCP servers
MCP_AVAIL=$(jq -s 'map(.mcpServers | keys) | flatten | length' ~/.gemini/antigravity-cli/plugins/*/mcp_config.json 2>/dev/null || echo 0)

# Subagents types available
SUBAGENTS_AVAIL=2

# Count context files (available vs dirty/used)
FILES_DIRTY=0
FILES_AVAIL=0
if [ -n "$VCS_BRANCH" ]; then
  FILES_DIRTY=$(git status --porcelain 2>/dev/null | wc -l | tr -d '[:space:]')
  FILES_AVAIL=$(git ls-files 2>/dev/null | wc -l | tr -d '[:space:]')
else
  if [ "$CWD" = "$HOME" ] && hash yadm 2>/dev/null; then
    FILES_DIRTY=$(yadm status --porcelain 2>/dev/null | wc -l | tr -d '[:space:]')
    FILES_AVAIL=$(yadm list 2>/dev/null | wc -l | tr -d '[:space:]')
  else
    FILES_DIRTY=0
    FILES_AVAIL=$(find . -maxdepth 3 -not -path '*/.*' -type f 2>/dev/null | wc -l | tr -d '[:space:]')
  fi
fi
if [[ ! "$FILES_DIRTY" =~ ^[0-9]+$ ]]; then FILES_DIRTY=0; fi
if [[ ! "$FILES_AVAIL" =~ ^[0-9]+$ ]]; then FILES_AVAIL=0; fi

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
  # Strip escape sequences: \033[38;2;...m or \033[0m or \033[1m etc.
  stripped=$(echo -e "$str" | sed -E 's/\x1bP[^\x1b]*\x1b\\//g; s/\x1b\][^\x07]*\x07//g; s/\x1b\[[0-9;]*[a-zA-Z]//g' | tr -d '\n' | tr -d '\r')
  echo "${#stripped}"
}

# ─── State Indicator (Emoji + Bold Colored text) ─────────────────────────────
if [ "$CONFIRM_PENDING" = "true" ]; then
  S="${CLR_RED}${B}🚨 CONFIRM REQ${R}"
else
  case "$STATE" in
    idle)     S="${CLR_GREEN}${B}😴 IDLE${R}" ;;
    thinking) S="${CLR_YELLOW}${B}🤔 THINKING${R}" ;;
    working)  S="${CLR_SKY}${B}⚙️ WORKING${R}" ;;
    tool_use) S="${CLR_RED}${B}🔧 TOOL${R}" ;;
    *)        S="${CLR_WHITE}${B}⏳ $(echo "$STATE" | tr '[:lower:]' '[:upper:]')${R}" ;;
  esac
fi

# ─── Model & Agent Persona ───────────────────────────────────────────────────
M=""
if [ -n "$MODEL" ]; then
  M_NAME="$MODEL"
  if [[ "$M_NAME" == *" (High)"* ]]; then
    M_NAME="${M_NAME/ (High)/}"
  fi
  if [ -n "$AGENT_NAME" ]; then
    M="${CLR_GRAY} ╱ ${CLR_MAUVE}󰚩 ${M_NAME} ${CLR_SKY}(👤 ${AGENT_NAME})${R}"
  else
    M="${CLR_GRAY} ╱ ${CLR_MAUVE}󰚩 ${M_NAME}${R}"
  fi
fi

# ─── Directory ───────────────────────────────────────────────────────────────
DIR_STR=""
if [ -n "$CWD" ]; then
  if [[ "$CWD" == "$HOME" ]]; then
    DIR_STR="~"
  elif [[ "$CWD" == "$HOME/"* ]]; then
    DIR_STR="~${CWD#$HOME}"
  else
    DIR_STR="$CWD"
  fi
fi

D_STR=""
if [ -n "$DIR_STR" ]; then
  D_STR="${CLR_GRAY} ╱ ${CLR_SKY} ${DIR_STR}${R}"
fi

# ─── VCS / Git/JJ/Fig Branch ─────────────────────────────────────────────────
V=""
VCS_ICON=""
if [ "$VCS_TYPE" = "jj" ]; then
  VCS_ICON=""
elif [ "$VCS_TYPE" = "fig" ]; then
  VCS_ICON=""
fi

if [ -n "$VCS_BRANCH" ]; then
  client_lbl=""
  if [ -n "$VCS_CLIENT" ]; then
    client_lbl=" [${VCS_CLIENT}]"
  fi
  if [ "$VCS_DIRTY" = "true" ]; then
    if [ -n "$CHANGES_STR" ]; then
      V="${CLR_GRAY} ╱ ${CLR_BLUE}${VCS_ICON} ${VCS_BRANCH}${client_lbl}${CLR_YELLOW}* ${CLR_RED}(${CHANGES_STR})${R}"
    else
      V="${CLR_GRAY} ╱ ${CLR_BLUE}${VCS_ICON} ${VCS_BRANCH}${client_lbl}${CLR_YELLOW}*${R}"
    fi
  else
    V="${CLR_GRAY} ╱ ${CLR_BLUE}${VCS_ICON} ${VCS_BRANCH}${client_lbl}${R}"
  fi
elif [ -n "$CHANGES_STR" ]; then
  V="${CLR_GRAY} ╱ ${CLR_BLUE}${VCS_ICON} yadm${CLR_YELLOW}* ${CLR_RED}(${CHANGES_STR})${R}"
fi

# ─── Sandbox Badge (Aware of allow_network) ──────────────────────────────────
if [ "$SANDBOX" = "true" ]; then
  if [ "$ALLOW_NET" = "true" ]; then
    SB="${CLR_GRAY}sandbox ${CLR_GREEN}${B} ON ${CLR_SKY}(🌐 net)${R}"
  else
    SB="${CLR_GRAY}sandbox ${CLR_GREEN}${B} ON ${CLR_YELLOW}(🔒 loc)${R}"
  fi
else
  SB="${CLR_GRAY}sandbox ${CLR_SURFACE} OFF${R}"
fi

# ─── Context Bar (Smooth Unicode transition) ──────────────────────────────────
BAR_LEN=10
FILLED=$((PCT_INT * BAR_LEN / 100))
REMAINDER=$(( (PCT_INT * BAR_LEN) % 100 ))

if [ "$PCT_INT" -ge 50 ]; then
  BAR_COLOR="$CLR_RED"
elif [ "$PCT_INT" -ge 35 ]; then
  BAR_COLOR="$CLR_YELLOW"
else
  BAR_COLOR="$CLR_GREEN"
fi

BAR=""
for ((i = 0; i < BAR_LEN; i++)); do
  if [ "$i" -lt "$FILLED" ]; then
    BAR="${BAR}█"
  elif [ "$i" -eq "$FILLED" ]; then
    if [ "$REMAINDER" -ge 75 ]; then
      BAR="${BAR}▓"
    elif [ "$REMAINDER" -ge 50 ]; then
      BAR="${BAR}▒"
    elif [ "$REMAINDER" -ge 25 ]; then
      BAR="${BAR}░"
    else
      BAR="${BAR}·"
    fi
  else
    BAR="${BAR}·"
  fi
done

CTX="${CLR_GRAY}ctx ${BAR_COLOR}${BAR} ${CLR_WHITE}${B}${PCT_FMT}%${R}"

# ─── Stats Formatting ────────────────────────────────────────────────────────
TOK_IN_FMT=$(format_tokens "$TOKENS_IN")
TOK_OUT_FMT=$(format_tokens "$TOKENS_OUT")
if [ "$CACHE_READ_TOKENS" -gt 0 ]; then
  CACHE_FMT=$(format_tokens "$CACHE_READ_TOKENS")
  TOK_FMT="${CLR_GRAY}tokens ${CLR_PEACH}󰌨 ${TOK_IN_FMT}/${TOK_OUT_FMT} ${CLR_GREEN}(󰛵 ${CACHE_FMT} cached)${R}"
else
  TOK_FMT="${CLR_GRAY}tokens ${CLR_PEACH}󰌨 ${TOK_IN_FMT}/${TOK_OUT_FMT}${R}"
fi

MEM_FMT="${CLR_GRAY}ram ${CLR_PEACH}󰍛 ${MEM_PCT}%${R}"
DISK_FMT="${CLR_GRAY}disk ${CLR_PEACH}󰋊 ${DISK_PCT}%${R}"

# Artifacts detailed
ART_FMT="${CLR_GRAY}artifacts ${CLR_WHITE}${ARTIFACT_COUNT}${R}"
if [ "$ARTIFACT_COUNT" -gt 0 ] && [ -n "$ARTIFACTS_DETAILS" ]; then
  ART_FMT="${CLR_GRAY}artifacts ${CLR_WHITE}󰧮 ${ARTIFACT_COUNT} ${CLR_SKY}[${ARTIFACTS_DETAILS}]${R}"
fi

# Subagents detailed
SUB_FMT="${CLR_GRAY}subagents ${CLR_PEACH}👥 ${SUBAGENTS_COUNT}/${SUBAGENTS_AVAIL}${R}"
if [ "$SUBAGENTS_COUNT" -gt 0 ] && [ -n "$SUBAGENTS_DETAILS" ]; then
  SUB_FMT="${CLR_GRAY}subagents ${CLR_PEACH}👥 ${SUBAGENTS_COUNT}/${SUBAGENTS_AVAIL} ${CLR_SKY}[${SUBAGENTS_DETAILS}]${R}"
fi

# Background tasks detailed
BG_FMT="${CLR_GRAY}tasks ${CLR_WHITE}${BG_TASKS_COUNT}${R}"
if [ "$BG_TASKS_COUNT" -gt 0 ] && [ -n "$BG_TASKS_DETAILS" ]; then
  BG_FMT="${CLR_GRAY}tasks ${CLR_WHITE}⚙️ ${BG_TASKS_COUNT} ${CLR_SKY}[${BG_TASKS_DETAILS}]${R}"
fi

SKILLS_FMT="${CLR_GRAY}skills ${CLR_MAUVE}🎓 ${SKILLS_AVAIL}${R}"
MCP_FMT="${CLR_GRAY}mcp ${CLR_SKY}🔌 ${MCP_AVAIL}${R}"
FILES_FMT="${CLR_GRAY}files ${CLR_BLUE}📁 ${FILES_DIRTY}/${FILES_AVAIL}${R}"

QUEUE_FMT=""
if [ "$PENDING_INPUT" -gt 0 ]; then
  QUEUE_FMT="${CLR_GRAY}queue ${CLR_YELLOW}✉️ ${PENDING_INPUT}${R}"
fi

SESSION_STR=""
if [ -n "$SESSION_ID" ]; then
  SESSION_STR="${SESSION_ID:0:8}"
fi

SESS_FMT=""
if [ -n "$SESSION_STR" ]; then
  SESS_FMT="${CLR_GRAY}id ${CLR_SKY}🆔 ${SESSION_STR}${R}"
fi

HOSTNAME_STR=$(hostname 2>/dev/null || echo "localhost")
HOST_FMT="${CLR_GRAY}host ${CLR_SKY} ${HOSTNAME_STR}${R}"

# ─── Separators ──────────────────────────────────────────────────────────────
DOT="${CLR_GRAY} · ${R}"

# ─── Layout Assembly & Formatting ────────────────────────────────────────────
LINE1_LEFT="${S}${M}${D_STR}${V}"

# Append Product and Version on Wide Viewports
PROD_STR=""
if [ -n "$PRODUCT" ] && [ "$COLS" -ge 120 ]; then
  if [ -n "$VERSION" ]; then
    PROD_STR="${CLR_GRAY}${PRODUCT} v${VERSION}${R}"
  else
    PROD_STR="${CLR_GRAY}${PRODUCT}${R}"
  fi
fi
if [ -n "$PROD_STR" ]; then
  LINE1_LEFT="${PROD_STR}${CLR_GRAY} ╱ ${R}${LINE1_LEFT}"
fi

LINE1_RIGHT=""
if [ "$COLS" -ge 120 ]; then
  USER_STR=""
  if [ -n "$EMAIL" ]; then
    USER_STR="${CLR_GRAY}👤 ${EMAIL}${R}"
    if [ -n "$PLAN_TIER" ]; then
      USER_STR="${USER_STR} ${CLR_YELLOW}(💎 ${PLAN_TIER})${R}"
    fi
  fi
  if [ -n "$USER_STR" ]; then
    LINE1_RIGHT="${USER_STR}"
  fi
fi

if [ -n "$QUEUE_FMT" ]; then
  if [ -n "$LINE1_RIGHT" ]; then
    LINE1_RIGHT="${LINE1_RIGHT}${DOT}${QUEUE_FMT}"
  else
    LINE1_RIGHT="${QUEUE_FMT}"
  fi
fi

# Output according to terminal columns width (Responsive layout)
if [ "$COLS" -ge 120 ]; then
  # Wide double-line box with right-aligned dynamic horizontal separator
  LEN_LEFT=$(visible_len "$LINE1_LEFT")
  LEN_RIGHT=$(visible_len "$LINE1_RIGHT")
  GAP=$((COLS - LEN_LEFT - LEN_RIGHT - 6)) # 6 characters padding for frame

  BORDER_LINE=""
  if [ "$GAP" -gt 0 ]; then
    for ((i = 0; i < GAP; i++)); do
      BORDER_LINE="${BORDER_LINE}─"
    done
    LINE1_PRINT="${CLR_GRAY}╭─${R} ${LINE1_LEFT} ${CLR_GRAY}${BORDER_LINE}${R} ${LINE1_RIGHT} ${CLR_GRAY}─╮${R}"
  else
    LINE1_PRINT="${CLR_GRAY}╭─${R} ${LINE1_LEFT} ${LINE1_RIGHT} ${CLR_GRAY}─╮${R}"
  fi

  # Line 2 components
  LINE2_LEFT="${CTX}${DOT}${TOK_FMT}${DOT}${SKILLS_FMT}${DOT}${MCP_FMT}${DOT}${FILES_FMT}${DOT}${SUB_FMT}${DOT}${BG_FMT}${DOT}${ART_FMT}"
  LINE2_RIGHT="${SB}${DOT}${SESS_FMT}${DOT}${HOST_FMT}"

  LEN_L2_LEFT=$(visible_len "$LINE2_LEFT")
  LEN_L2_RIGHT=$(visible_len "$LINE2_RIGHT")
  GAP_L2=$((COLS - LEN_L2_LEFT - LEN_L2_RIGHT - 6))

  SPACES=""
  if [ "$GAP_L2" -gt 0 ]; then
    for ((i = 0; i < GAP_L2; i++)); do
      SPACES="${SPACES} "
    done
    LINE2_PRINT="${CLR_GRAY}╰─${R} ${LINE2_LEFT}${SPACES}${LINE2_RIGHT} ${CLR_GRAY}─╯${R}"
  else
    LINE2_PRINT="${CLR_GRAY}╰─${R} ${LINE2_LEFT} ${LINE2_RIGHT} ${CLR_GRAY}─╯${R}"
  fi

  echo -e "${LINE1_PRINT}"
  echo -e "${LINE2_PRINT}"

elif [ "$COLS" -ge 80 ]; then
  # Medium double-line layout
  LEN_LEFT=$(visible_len "$LINE1_LEFT")
  LEN_RIGHT=$(visible_len "$LINE1_RIGHT")
  GAP=$((COLS - LEN_LEFT - LEN_RIGHT - 6))

  BORDER_LINE=""
  if [ "$GAP" -gt 0 ]; then
    for ((i = 0; i < GAP; i++)); do
      BORDER_LINE="${BORDER_LINE}─"
    done
    LINE1_PRINT="${CLR_GRAY}╭─${R} ${LINE1_LEFT} ${CLR_GRAY}${BORDER_LINE}${R} ${LINE1_RIGHT} ${CLR_GRAY}─╮${R}"
  else
    LINE1_PRINT="${CLR_GRAY}╭─${R} ${LINE1_LEFT} ${LINE1_RIGHT} ${CLR_GRAY}─╮${R}"
  fi

  # Compact second line for medium screens
  LINE2_MED="${CTX}${DOT}${TOK_FMT}${DOT}${FILES_FMT}${DOT}${SUB_FMT}${DOT}${BG_FMT}${DOT}${SB}"
  LEN_L2=$(visible_len "$LINE2_MED")
  GAP_L2=$((COLS - LEN_L2 - 6))

  SPACES=""
  if [ "$GAP_L2" -gt 0 ]; then
    for ((i = 0; i < GAP_L2; i++)); do
      SPACES="${SPACES} "
    done
    LINE2_PRINT="${CLR_GRAY}╰─${R} ${LINE2_MED}${SPACES}${SESS_FMT} ${CLR_GRAY}─╯${R}"
  else
    LINE2_PRINT="${CLR_GRAY}╰─${R} ${LINE2_MED} ${SESS_FMT} ${CLR_GRAY}─╯${R}"
  fi

  echo -e "${LINE1_PRINT}"
  echo -e "${LINE2_PRINT}"

else
  # Narrow compact single-line fallbacks
  LINE2_NAR="${CTX}${DOT}${TOK_FMT}${DOT}${FILES_FMT}${DOT}${SUB_FMT}"
  if [ -n "$QUEUE_FMT" ]; then
    LINE2_NAR="${LINE2_NAR}${DOT}${QUEUE_FMT}"
  fi
  echo -e "${LINE1_LEFT}"
  echo -e "${LINE2_NAR}"
fi
