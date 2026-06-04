# 🚀 Antigravity CLI - Premium AI-Native Terminal Configs

Welcome to my personal configuration suite for the **Antigravity CLI**! This repository holds a bleeding-edge, highly-optimized, and aesthetically stunning status bar and terminal title customization designed to turn your terminal into a premium, information-rich AI workspace.

It is heavily optimized for modern, GPU-accelerated terminal emulators supporting truecolor and Nerd Fonts (specifically **Ghostty** with **Catppuccin Mocha**).

---

## ✨ Features

*   **🎨 Truecolor Catppuccin Mocha Theme:** Customized using precise Hex-to-RGB escape sequences, seamlessly blending with standard Mocha terminal/editor themes.
*   **📂 Direct Path Awareness:** Displays your current directory elegantly in the status bar (e.g. ` ~` or ` ~/workspace/project`), with smart home-directory truncation to save valuable line space.
*   **🌳 Dual VCS Context (Git & Yadm):** Automatically shows your Git branch and modified file count (` master (3Δ)`). If you are in your home folder, it automatically falls back to tracking **Yadm** dotfile changes!
*   **🧠 Dynamic Context Bar with Warning Thresholds:**
    *   **🟢 Green:** Context usage under `35%`
    *   **🟡 Yellow (Warning):** Context usage between `35%` and `50%`
    *   **🔴 Red (Critical):** Context usage at `50%` or above
*   **󰌨 Live Token Usage:** Displays total accumulated tokens (`󰌨 103.7k in / 38.8k out`) using optimized pure-Bash formatting arithmetic (no external program lag).
*   **💻 System Performance Stats:** Real-time system monitoring:
    *   `󰍛 % RAM` (parsed directly from `/proc/meminfo` via zero-overhead Bash built-ins)
    *   `󰋊 % DISK` (monitors disk space/quota on `/`)
*   **🆔 Identity & Sandboxing:** Clear badges indicating Sandbox state (` ON` / ` OFF`), first-8 digits of your AI session UUID (`🆔 7316533b`), and VM hostname.
*   **🖥️ Rich Tab Titles:** A fully enriched terminal window/tab title showing `[Model] EMOJI State | Directory (Branch) | ctx %`.
*   **⚡ Zero-Latency Performance:** High-performance design. The statusline and title scripts extract all session metadata in a **single `jq` invocation**, utilizing pure Bash arithmetic for all calculations to prevent terminal lag during fast commands.

---

## 📂 Repository Structure

The files in this repository are structured to mimic their exact destinations in your home directory, making it straightforward to copy or symlink them into place:

```text
antigravity-config/
├── README.md                      # This documentation guide
└── .gemini/                       # Destination: ~/.gemini/
    └── antigravity-cli/           # Destination: ~/.gemini/antigravity-cli/
        ├── settings.json          # Antigravity CLI configuration and hook registration
        ├── statusline.sh          # Custom bottom status bar script
        └── title.sh               # Custom window/tab title script
```

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
This hook dynamically alters your terminal tab name as the agent works, keeping you informed of model state changes even when you are working inside background splits.
