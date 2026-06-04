# 🚀 Antigravity CLI - Premium AI-Native Terminal Configs

Welcome to my personal configuration suite for the **Antigravity CLI**! This repository holds a bleeding-edge, highly-optimized, and aesthetically stunning status bar and terminal title customization designed to turn your terminal into a premium, information-rich AI workspace.

It is heavily optimized for modern, GPU-accelerated terminal emulators supporting truecolor and Nerd Fonts (specifically **Ghostty** with **Catppuccin Mocha**).

---

## 🎨 Design Theme: Catppuccin Mocha Truecolor

Rather than relying on basic ANSI 16-color escapes, we utilize **truecolor (RGB) escape sequences** (`\033[38;2;R;G;Bm`). This guarantees a highly polished, consistent look that matches your Neovim, Tmux, and Starship colorways.

| Color | Hex | Escape Code Prefix | Applied Elements |
| :--- | :--- | :--- | :--- |
| **Mauve** | `#cba6f7` | `\033[38;2;203;166;247m` | AI Model Name, Section Highlights |
| **Green** | `#a6e3a1` | `\033[38;2;166;227;161m` | Ready/Idle State (`😴 idle`), Active Sandbox, Safe Context |
| **Yellow** | `#f9e2af` | `\033[38;2;249;226;175m` | Thinking State (`🤔 thinking`), Warning Context Limit |
| **Sky** | `#89dceb` | `\033[38;2;137;220;235m` | Working State (`⚙️ working`), Session Info |
| **Blue** | `#89b4fa` | `\033[38;2;137;180;250m` | Git Branch, Version Control Repositories |
| **Red** | `#f38ba8` | `\033[38;2;243;139;168m` | Tool State (`🔧 tool_use`), Critical Context Limit |
| **Peach** | `#fab387` | `\033[38;2;250;179;135m` | System Stats (RAM Utilization & Disk Space) |
| **Overlay0**| `#6c7086` | `\033[38;2;108;112;134m` | Dimmed labels, Separators (`│`, `╱`, `·`) |

---

## ✨ Features

*   **🎨 Catppuccin Mocha palette:** Native integration with truecolor terminal schemes.
*   **📂 Direct Path Awareness:** Displays your current directory elegantly in the status bar (e.g. ` ~` or ` ~/workspace/project`), with smart home-directory truncation to save valuable line space.
*   **🌳 Dual VCS Context (Git & Yadm):** Automatically shows your Git branch and modified file count (` master (3Δ)`). If you are in your home folder, it automatically falls back to tracking **Yadm** dotfile changes!
*   **🧠 Dynamic Context Bar with Warning Thresholds:**
    *   **🟢 Green (Safe):** Context usage under `35%`
    *   **🟡 Yellow (Warning):** Context usage between `35%` and `50%`
    *   **🔴 Red (Critical):** Context usage at `50%` or above
*   **󰌨 Live Token Usage:** Displays total accumulated tokens (`󰌨 103.7k in / 38.8k out`) using optimized pure-Bash formatting arithmetic (no external program lag).
*   **💻 System Performance Stats:** Real-time system monitoring:
    *   `󰍛 % RAM` (parsed directly from `/proc/meminfo` via zero-overhead Bash built-ins)
    *   `󰋊 % DISK` (monitors disk space/quota on `/`)
*   **🛠️ AI Resources & Workspace Context Tracking:** Real-time visibility into your AI enablement workspace:
    *   `🎓 skills`: Total available skills dynamically scanned from active plugins (e.g. `🎓 32`).
    *   `🔌 mcp`: Total active/configured MCP server endpoints (e.g. `🔌 4`).
    *   `📁 files`: Real-time ratio of modified context files vs total tracked workspace files (e.g. `📁 6/44`).
    *   `👥 subagents`: Active session subagents displayed as a ratio of active jobs to total available subagent types (e.g. `👥 1/2`).
*   **🆔 Identity & Sandboxing:** Clear badges indicating Sandbox state (` ON` / ` OFF`), first-8 digits of your AI session UUID (`🆔 7316533b`), and VM hostname.
*   **🖥️ Space-Saving Tab Titles:** An upgraded terminal window/tab title showing `Emoji State | Contracted-Directory (Branch) | ctx % [Background-Jobs]`. **Completely model-less** to save massive space in horizontal splits.
*   **⚡ Zero-Latency Performance:** High-performance design. The statusline and title scripts extract all session metadata in a **single `jq` invocation**, utilizing pure Bash arithmetic for all calculations to prevent terminal lag during fast commands.

---

## 📐 Responsive Layout Strategy

The bottom status line dynamically shifts layout styles depending on your active terminal size (columns count), which is incredibly helpful when working with multiple horizontal or vertical pane splits.

### 1. Wide Layout (columns >= 120)
*Single-line complete development dashboard:*
```text
● READY ╱  Gemini 3.5 Flash ╱  main (3Δ)  │  ctx █▓░░░ 5.9% (3.8k/0.5k) ·  42% RAM ·  18% DISK ·  ON · 🆔 7316533b ·  localhost
```

### 2. Medium Layout (columns >= 80 and < 120)
*Compact double-line framed layout for standard splits:*
```text
╭─ ● READY ╱  Gemini 3.5 Flash ╱  main (3Δ)
╰─ ctx █▓░░░ 5.9% ·  42% ·  18% ·  ON · 🆔 7316533b
```

### 3. Narrow Layout (columns < 80)
*Ultra-compact minimalist status line for small tiles:*
```text
● READY ╱  main
ctx 5.9% ·  42%
```

---

## 📂 Repository Structure

The files in this repository are structured to mimic their exact destinations in your home directory, making it straightforward to copy or symlink them into place:

```text
antigravity-config/
├── README.md                      # This documentation guide
├── docs/
│   └── adr/
│       └── 0001-ai-native-terminal-statusline-and-title.md  # Architectural Decision Record (ADR)
└── .gemini/                       # Destination: ~/.gemini/
    └── antigravity-cli/           # Destination: ~/.gemini/antigravity-cli/
        ├── settings.json          # Antigravity CLI configuration and hook registration
        ├── statusline.sh          # Custom bottom status bar script
        └── title.sh               # Custom window/tab title script
```

---

## 📐 Architecture Decision Records (ADRs)

For deep context on why specific code choices, performance trade-offs, and design parameters were made (e.g. single-pass `jq`, pure-Bash math, tab directory compaction), please read:
*   👉 **[ADR 0001: AI-Native Terminal Statusline and Title Script Architecture](docs/adr/0001-ai-native-terminal-statusline-and-title.md)**

---

## 🛠️ Installation & Setup

To deploy these configurations onto your system:

### 1. Prerequisite
Ensure you have a **Nerd Font** active in your terminal emulator (e.g. Cascadia Code, FiraCode Nerd Font, or JetBrainsMono Nerd Font) to render the status icons (``, ``, `󰌨`, `󰍛`, `󰋊`, ``, `🆔`).

### 2. Copy Configurations to Home Directory
Run the following commands to create the directories and copy the configurations into place:

```bash
# Create the config folder if it doesn't exist
mkdir -p ~/.gemini/antigravity-cli

# Copy settings and custom scripts
cp .gemini/antigravity-cli/settings.json ~/.gemini/antigravity-cli/settings.json
cp .gemini/antigravity-cli/statusline.sh ~/.gemini/antigravity-cli/statusline.sh
cp .gemini/antigravity-cli/title.sh ~/.gemini/antigravity-cli/title.sh

# Ensure the scripts are executable
chmod +x ~/.gemini/antigravity-cli/statusline.sh
chmod +x ~/.gemini/antigravity-cli/title.sh
```

Alternatively, you can create symbolic links to keep them synced with your local clone of this repository:

```bash
mkdir -p ~/.gemini/antigravity-cli
ln -sf $(pwd)/.gemini/antigravity-cli/settings.json ~/.gemini/antigravity-cli/settings.json
ln -sf $(pwd)/.gemini/antigravity-cli/statusline.sh ~/.gemini/antigravity-cli/statusline.sh
ln -sf $(pwd)/.gemini/antigravity-cli/title.sh ~/.gemini/antigravity-cli/title.sh
chmod +x .gemini/antigravity-cli/*
```

---

## 🔍 Code Walkthrough: How It Works

### `statusline.sh`
This script receives a JSON payload on `stdin` containing metadata from the active Antigravity session.
It parses all required parameters in **one pass** to optimize speed:

```bash
{
  read -r STATE; read -r USED_PCT; read -r VCS_BRANCH; ...
} <<< "$(
  jq -r '(.agent_state // "idle"), (.context_window.used_percentage // 0), ...'
)"
```

It then dynamically checks system stats (`/proc/meminfo` and `df -h /`), counts changes in your workspace using `git status` or `yadm status`, formats numbers with pure arithmetic helper functions, and prints a responsive terminal layout optimized for columns `>=120` (single-line), `>=80` (two-line framed layout), and `<80` (ultra-compact layout).

### `title.sh`
This hook dynamically alters your terminal tab/window name as the agent works. By stripping the model name and compressing intermediate directories (using a smart parent/current format like `[project-name]:…/parent/current`), it keeps you highly informed of model state changes even inside small background split panes.
