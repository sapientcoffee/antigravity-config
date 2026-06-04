#!/bin/bash
set -euo pipefail

# Read JSON payload from stdin
DATA=$(cat)

# Extract fields using jq safely
eval "$(echo "$DATA" | jq -r '
  "STATE=\"" + (.agent_state // "idle") + "\"",
  "CWD=\"" + (.workspace.current_dir // "") + "\"",
  "PROJECT_DIR=\"" + (.workspace.project_dir // "") + "\"",
  "BRANCH=\"" + (.vcs.branch // "") + "\"",
  "USED_PCT=\"" + ((.context_window.used_percentage // 0) | tostring) + "\"",
  "TASK_COUNT=\"" + ((if .background_tasks | type == "array" then (.background_tasks | length) else (.task_count // 0) end) | tostring) + "\"",
  "SUBAGENTS_COUNT=\"" + ((if .subagents | type == "array" then (.subagents | length) else 0 end) | tostring) + "\"",
  "CONFIRM_PENDING=\"" + ((.tool_confirmation_pending // false) | tostring) + "\"",
  "PENDING_INPUT=\"" + ((.pending_input_count // 0) | tostring) + "\""
' 2>/dev/null || echo 'STATE="idle" CWD="" PROJECT_DIR="" BRANCH="" USED_PCT="0" TASK_COUNT="0" SUBAGENTS_COUNT="0" CONFIRM_PENDING="false" PENDING_INPUT="0"')"

# Map state to emoji
if [ "$CONFIRM_PENDING" = "true" ]; then
  EMOJI="🚨"
  STATE="CONFIRM_REQ"
else
  case "$STATE" in
    initializing) EMOJI="🚀" ;;
    idle)         EMOJI="😴" ;;
    thinking)     EMOJI="🤔" ;;
    working)      EMOJI="⚙️" ;;
    tool_use)     EMOJI="🔧" ;;
    *)            EMOJI="🤖" ;;
  esac
fi

# Try to format CWD elegantly using Project-Relative paths
DIR_STR=""
PROJ_PATH="${PROJECT_DIR#file://}"
if [ -n "$CWD" ] && [ -n "$PROJ_PATH" ] && [[ "$CWD" == "$PROJ_PATH"* ]]; then
  # Compute relative path from project root
  REL_PATH="${CWD#$PROJ_PATH}"
  REL_PATH="${REL_PATH#/}" # Remove leading slash
  PROJ_NAME=$(basename "$PROJ_PATH")
  
  if [ -n "$REL_PATH" ]; then
    # If relative path contains multiple segments, display the last two to keep it extremely compact
    if [[ "$REL_PATH" == *"/"* ]]; then
      PARENT_DIR=$(basename "$(dirname "$REL_PATH")")
      CURRENT_DIR=$(basename "$REL_PATH")
      DIR_STR="[$PROJ_NAME]:…/$PARENT_DIR/$CURRENT_DIR"
    else
      DIR_STR="[$PROJ_NAME]/$REL_PATH"
    fi
  else
    DIR_STR="[$PROJ_NAME]"
  fi
else
  # Fallback to standard ~ format if not in a project
  if [ -n "$CWD" ]; then
    if [[ "$CWD" == "$HOME" ]]; then
      DIR_STR="~"
    else
      DIR_BASE=$(basename "$CWD")
      DIR_DIR=$(basename "$(dirname "$CWD")")
      if [ "$DIR_DIR" = "robedwards" ] || [ "$DIR_DIR" = "/" ] || [ -z "$DIR_DIR" ]; then
        DIR_STR="~/$DIR_BASE"
      else
        DIR_STR="…/$DIR_DIR/$DIR_BASE"
      fi
    fi
  else
    DIR_STR="unknown"
  fi
fi

# Format branch
BRANCH_STR=""
if [ -n "$BRANCH" ]; then
  BRANCH_STR=" ( $BRANCH)"
fi

# Format used percentage
PCT_FMT=$(LC_NUMERIC=C printf "%.1f" "$USED_PCT")

# Format task, subagent, and pending inputs indicators
TASKS_STR=""
if [ "$TASK_COUNT" -gt 0 ]; then
  TASKS_STR=" ⚙️$TASK_COUNT"
fi
if [ "$SUBAGENTS_COUNT" -gt 0 ]; then
  TASKS_STR="$TASKS_STR 👥$SUBAGENTS_COUNT"
fi
if [ "$PENDING_INPUT" -gt 0 ]; then
  TASKS_STR="$TASKS_STR ✉️$PENDING_INPUT"
fi

# Build the final title (No model name, state-focused, project-focused, compact directory, active tasks)
TITLE="$EMOJI $STATE | $DIR_STR$BRANCH_STR | ctx $PCT_FMT%$TASKS_STR"

echo "$TITLE"
