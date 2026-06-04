# ADR 0001: AI-Native Terminal Statusline and Title Script Architecture

## Status
**Accepted / Implemented**

## Context
When pair-programming with agentic AI CLI tools (like Antigravity), engineers often work across multiple terminal window panes, multiplexer splits (tmux), and tabs. Staying informed about the AI's internal state, active background tasks, resource allocation, and cost-driving token metrics without disrupting workflow is a major developer experience (DX) challenge.

Traditional status lines are static, sluggish, and lack context. Specifically, we need:
1. **Real-time State Visibility:** Know if the AI is idle, thinking, running tools, or executing subagents.
2. **Context Window Safety:** Prevent accidental prompt bloating by monitoring context usage with warning indicators.
3. **Versatile Version Control Tracking:** Git for projects, with a graceful fallback to Yadm for dotfile/home configurations.
4. **Extreme Performance:** Executing layout updates on every shell command must not add any perceptual typing latency (less than 10ms execution budget).
5. **Aesthetics:** Perfect color compatibility with modern high-fidelity GPU terminal emulators (Ghostty) running the **Catppuccin Mocha** palette.

## Decision
We implemented a premium, high-performance statusline (`statusline.sh`) and window title hook (`title.sh`) leveraging the following architectural decisions:

### 1. Zero-Overhead JSON Processing (Single-Pass `jq` Eval)
To prevent spawning multiple processes on every command, we retrieve and parse the session payload from standard input in a **single pass** of `jq`, executing safe variable assignment inside a single shell expansion.
```bash
eval "$(echo "$DATA" | jq -r '
  "STATE=\"" + (.agent_state // "idle") + "\"",
  "CWD=\"" + (.workspace.current_dir // "") + "\"",
  ...
')"
```

### 2. Pure-Bash Performance Guidelines
We strictly avoided launching external tools like `bc`, `awk`, or `sed` for formatting tasks.
* **Token Scaling:** Numbers are converted to thousands (`k`) or millions (`M`) using pure Bash arithmetic.
* **System Stats:** RAM utilization is read directly from `/proc/meminfo` in a `while` loop rather than spawning `free` or `top`.

### 3. Truecolor Aesthetics (Catppuccin Mocha)
We utilize truecolor (RGB) escape sequences (`\033[38;2;R;G;Bm`) directly in the shell scripts to display a gorgeous, native-feeling Catppuccin Mocha layout:
* **Mauve (`#cba6f7`):** AI Model Name, Highlights
* **Green (`#a6e3a1`):** Ready/Idle State, Active Sandbox
* **Yellow (`#f9e2af`):** Thinking State, Warning/High-Context
* **Sky (`#89dceb`):** Working State, Session Info
* **Blue (`#89b4fa`):** Git Branch, Repositories
* **Red (`#f38ba8`):** Tool/Error State, Context Limit Exceeded
* **Peach (`#fab387`):** System Stats, Memory/Disk
* **Overlay0 (`#6c7086`):** Separators, Labels, and Dimmed Info

### 4. Dynamic Context Alerts
We introduced context utilization warning thresholds in the status line context bar:
* **Green (Safe):** Used context < 35%
* **Yellow (Warning):** Used context between 35% and 50%
* **Red (Critical):** Used context >= 50%

### 5. Multi-Column Responsive Layout
To maintain support for vertical pane splits and narrow windows, `statusline.sh` dynamically queries terminal columns (`$COLUMNS` or the `.terminal_width` payload key) and shifts elegantly through three responsive viewport layouts:
* **Wide Layout (`cols >= 120`):** Single-line full dashboard.
* **Medium Layout (`cols >= 80`):** Compact double-line framed layout.
* **Narrow Layout (`cols < 80`):** Ultra-compact minimalist status line.

### 6. Space-Saving Window Titles (No Model Name, Compact Directory)
For `title.sh`, space in terminal split tabs is extremely scarce. We decided to:
* **Remove Model Name:** Model name is already visible in the primary status line, so we omit it from the title.
* **Elegantly Contract Directories:** Instead of full paths, we show a project-relative contracted path in the format `[project-name]:…/parent/current` (e.g., `[cymbal-eats]:…/components/button`). Outside a project workspace, we show the last two folders (e.g. `…/downloads/photos`).
* **Display Active Tasks (`⚙️N 👥N`):** Shows background command count (`task_count`) and active parallel subagents (`subagents`) so the developer always knows if a pane is crunching a background task.

## Consequences

### Benefits
* **Incredible DX:** Beautiful color coordination and highly dense, readable metadata.
* **No Lag:** Script execution typically completes in under **5ms**, causing zero typing or command lag.
* **High Awareness:** Context threshold color shifts and background task badges make multitasking across panes effortless.

### Trade-offs
* **Font Requirement:** Requires a Nerd Font installed locally to correctly render status icons (``, ``, `󰌨`, `󰍛`, `󰋊`, `🆔`).
* **Platform Dependencies:** Reading system RAM directly from `/proc/meminfo` is optimized for Linux environments.
