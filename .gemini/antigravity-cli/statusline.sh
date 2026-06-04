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
{
  read -r STATE
  read -r USED_PCT
  read -r VCS_BRANCH
  read -r VCS_DIRTY
  read -r SANDBOX
  read -r ARTIFACTS
  read -r SUBAGENTS
  read -r BG_TASKS
  read -r MODEL
  read -r COLS
  read -r SESSION_ID
  read -r TOKENS_IN
  read -r TOKENS_OUT
  read -r CWD
} <<< "$(
  jq -r '
    (.agent_state // "idle"),
    (.context_window.used_percentage // 0),
    (.vcs.branch // ""),
    (.vcs.dirty // false),
    (.sandbox.enabled // false),
    (.artifact_count // 0),
    (if .subagents | type == "array" then (.subagents | length) else 0 end),
    (.task_count // 0),
    (.model.display_name // ""),
    (.terminal_width // 80),
    (.session_id // ""),
    (.context_window.total_input_tokens // 0),
    (.context_window.total_output_tokens // 0),
    (.cwd // "")
  ' 2>/dev/null || printf "idle\n0\n\nfalse\nfalse\n0\n0\n0\n\n80\n\n0\n0\n\n"
)"

# ─── Computed Values ─────────────────────────────────────────────────────────
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

# ─── Compute Code Changes (Git status porcelain) ─────────────────────────────
CHANGES_STR=""
if [ -n "$VCS_BRANCH" ]; then
  changes_count=$(git status --porcelain 2>/dev/null | wc -l || echo 0)
  if [ "$changes_count" -gt 0 ]; then
    CHANGES_STR="${changes_count}Δ"
  fi
else
  if [ "$CWD" = "$HOME" ] && hash yadm 2>/dev/null; then
    changes_count=$(yadm status --porcelain 2>/dev/null | wc -l || echo 0)
    if [ "$changes_count" -gt 0 ]; then
      CHANGES_STR="${changes_count}Δ"
    fi
  fi
fi

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

# ─── State Indicator (Emoji + Bold Colored text) ─────────────────────────────
case "$STATE" in
  idle)     S="${CLR_GREEN}${B}😴 IDLE${R}" ;;
  thinking) S="${CLR_YELLOW}${B}🤔 THINKING${R}" ;;
  working)  S="${CLR_SKY}${B}⚙️ WORKING${R}" ;;
  tool_use) S="${CLR_RED}${B}🔧 TOOL${R}" ;;
  *)        S="${CLR_WHITE}${B}⏳ $(echo "$STATE" | tr '[:lower:]' '[:upper:]')${R}" ;;
esac

# ─── Model ───────────────────────────────────────────────────────────────────
M=""
if [ -n "$MODEL" ]; then
  M_NAME="$MODEL"
  if [[ "$M_NAME" == *" (High)"* ]]; then
    M_NAME="${M_NAME/ (High)/}"
  fi
  M="${CLR_GRAY} ╱ ${CLR_MAUVE}󰚩 ${M_NAME}${R}"
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

# ─── VCS / Git Branch ────────────────────────────────────────────────────────
V=""
if [ -n "$VCS_BRANCH" ]; then
  if [ "$VCS_DIRTY" = "true" ]; then
    if [ -n "$CHANGES_STR" ]; then
      V="${CLR_GRAY} ╱ ${CLR_BLUE} ${VCS_BRANCH}${CLR_YELLOW}* ${CLR_RED}(${CHANGES_STR})${R}"
    else
      V="${CLR_GRAY} ╱ ${CLR_BLUE} ${VCS_BRANCH}${CLR_YELLOW}*${R}"
    fi
  else
    V="${CLR_GRAY} ╱ ${CLR_BLUE} ${VCS_BRANCH}${R}"
  fi
elif [ -n "$CHANGES_STR" ]; then
  V="${CLR_GRAY} ╱ ${CLR_BLUE} yadm${CLR_YELLOW}* ${CLR_RED}(${CHANGES_STR})${R}"
fi

# ─── Sandbox Badge ───────────────────────────────────────────────────────────
if [ "$SANDBOX" = "true" ]; then
  SB="${CLR_GRAY}sandbox ${CLR_GREEN}${B} ON${R}"
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
TOK_FMT="${CLR_GRAY}tokens ${CLR_PEACH}󰌨 ${TOK_IN_FMT}/${TOK_OUT_FMT}${R}"

MEM_FMT="${CLR_GRAY}ram ${CLR_PEACH}󰍛 ${MEM_PCT}%${R}"
DISK_FMT="${CLR_GRAY}disk ${CLR_PEACH}󰋊 ${DISK_PCT}%${R}"

ART_FMT="${CLR_GRAY}artifacts ${CLR_WHITE}${ARTIFACTS}${R}"
SUB_FMT="${CLR_GRAY}subagents ${CLR_WHITE}${SUBAGENTS}${R}"
BG_FMT="${CLR_GRAY}tasks ${CLR_WHITE}${BG_TASKS}${R}"

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

# ─── Layout Formatting ────────────────────────────────────────────────────────
LINE1="${S}${M}${D_STR}${V}"
LINE2="${CTX}${DOT}${TOK_FMT}${DOT}${MEM_FMT}${DOT}${DISK_FMT}${DOT}${ART_FMT}${DOT}${SUB_FMT}${DOT}${BG_FMT}${DOT}${SB}${DOT}${SESS_FMT}${DOT}${HOST_FMT}"

if [ "$COLS" -ge 120 ]; then
  echo -e "${LINE1}${CLR_GRAY}  │  ${R}${LINE2}"
elif [ "$COLS" -ge 80 ]; then
  LINE2_MED="${CTX}${DOT}${TOK_FMT}${DOT}${MEM_FMT}${DOT}${DISK_FMT}${DOT}${SB}${DOT}${SESS_FMT}"
  echo -e "${CLR_GRAY}╭─${R} ${LINE1}"
  echo -e "${CLR_GRAY}╰─${R} ${LINE2_MED}"
else
  LINE2_NAR="${CTX}${DOT}${TOK_FMT}${DOT}${MEM_FMT}"
  echo -e "${LINE1}"
  echo -e "${LINE2_NAR}"
fi
