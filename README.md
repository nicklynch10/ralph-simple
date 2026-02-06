# Ralph for Kimi Code CLI - Production CI/CD Agent

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![PowerShell 7](https://img.shields.io/badge/PowerShell-7+-blue.svg)](https://github.com/PowerShell/PowerShell)

Ralph is a **24/7 autonomous CI/CD agent** that runs [Kimi Code CLI](https://github.com/moonshotai/kimi-cli) repeatedly until all PRD (Product Requirements Document) items are complete. Designed for production-grade reliability with process isolation, automatic recovery, and comprehensive health monitoring.

> **Core Philosophy**: Like a CI/CD pipeline that never sleeps, Ralph continuously works through your product requirements, verifying each change before moving to the next.

Based on the [Ralph pattern](https://ghuntley.com/ralph) by Geoffrey Huntley.

---

## ⚡ Quick Start (3 Steps)

### 1. Install Prerequisites

```powershell
# PowerShell 7 (required)
winget install Microsoft.PowerShell

# Kimi CLI
pip install kimi-cli
kimi config set api_key <your-key>

# Git
winget install Git.Git
```

### 2. Initialize Workspace

```powershell
# Clone Ralph
git clone https://github.com/nicklynch10/ralph-simple.git

# Copy to your project
copy ralph-simple\*.ps1 C:\path\to\your\project\

# Initialize
cd C:\path\to\your\project
.\ralph.ps1 init
```

### 3. Run Ralph

```powershell
# Check everything is ready
.\ralph.ps1 doctor

# Run interactively
.\ralph.ps1 run

# Or start 24/7 daemon
.\ralph.ps1 daemon start
```

---

## 📖 Command Reference

### Core Commands

| Command | Description | Example |
|---------|-------------|---------|
| `init` | Initialize workspace | `ralph init [--template node-react]` |
| `doctor` | Check/fix issues | `ralph doctor [--fix]` |
| `bead` | Create task bead | `ralph bead "Add login" [--verifier "npm test"]` |
| `run` | Run main loop | `ralph run [iterations]` |
| `daemon` | Manage daemon | `ralph daemon <start\|stop\|status\|logs>` |
| `status` | Show status | `ralph status [--json]` |
| `logs` | View logs | `ralph logs [lines]` |

### Detailed Usage

#### `ralph init` - Initialize Workspace

```powershell
# Basic initialization
.\ralph.ps1 init

# Initialize with template
.\ralph.ps1 init --template node-react

# Initialize in specific directory
.\ralph.ps1 init ./my-project
```

**Creates:**
- `.ralph/` - Configuration directory
- `prd.json` - Product requirements template
- `KIMI.md` - Agent instructions
- `progress.txt` - Progress log
- `.gitignore` - Git ignore file

**Templates:**
- `node-react` - React + TypeScript + Vite
- `node-next` - Next.js application
- `python-flask` - Python Flask API
- `python-django` - Python Django app
- `go-cli` - Go CLI tool
- `generic` - Minimal setup (default)

#### `ralph doctor` - Diagnostics

```powershell
# Check health
.\ralph.ps1 doctor

# Check and auto-fix issues
.\ralph.ps1 doctor --fix
```

**Checks:**
- PowerShell 7+ installed
- Kimi CLI installed and authenticated
- Git installed and configured
- Workspace structure valid
- PRD JSON valid
- Daemon status

#### `ralph bead` - Create Task

```powershell
# Create simple bead
.\ralph.ps1 bead "Add user login page"

# Create bead with custom verifier
.\ralph.ps1 bead "Fix API bug" --verifier "npm test"

# Create bead with timeout
.\ralph.ps1 bead "Complex feature" --verifier "npm run e2e" --timeout 3600
```

**Auto-detects project type** and adds appropriate verifiers:
- Node.js: `npm run build`, `npm test`
- Go: `go build`, `go test`
- Python: `python -m py_compile`

#### `ralph run` - Run Main Loop

```powershell
# Run 10 iterations (default)
.\ralph.ps1 run

# Run specific iterations
.\ralph.ps1 run 20

# Run once (for daemon)
.\ralph.ps1 run 1
```

#### `ralph daemon` - Manage Daemon

```powershell
# Start daemon
.\ralph.ps1 daemon start

# Check status
.\ralph.ps1 daemon status

# View logs
.\ralph.ps1 daemon logs

# Stop daemon
.\ralph.ps1 daemon stop
```

#### `ralph status` - Show Status

```powershell
# Human-readable status
.\ralph.ps1 status

# JSON output for automation
.\ralph.ps1 status --json
```

#### `ralph logs` - View Logs

```powershell
# Show last 20 lines
.\ralph.ps1 logs

# Show last 50 lines
.\ralph.ps1 logs 50
```

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         Ralph Command Interface                          │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ralph init ──────┐                                                      │
│  ralph doctor ────┤                                                      │
│  ralph bead ──────┼──► ralph-core.ps1 (shared functions)                │
│  ralph run ───────┤       ├──► Kimi CLI                                 │
│  ralph daemon ────┤       ├──► Git                                      │
│  ralph status ────┘       └──► prd.json                                 │
│  ralph logs                                                              │
│                                                                          │
│  Memory: git history + prd.json + progress.txt + bead files             │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### File Structure

```
.
├── ralph.ps1              # Main command interface
├── ralph-core.ps1         # Shared functions
├── ralph-daemon.ps1       # Background daemon
├── install-service.ps1    # Windows Service installer
├── ralph.sh               # Linux/Mac version
├── KIMI.md                # Agent instructions
├── prd.json               # Your product requirements
├── progress.txt           # Execution log
└── .ralph/
    ├── logs/              # Log files
    └── beads/             # Task beads (daemon mode)
```

---

## 🚀 Running Modes

### 1. Interactive Mode (`ralph run`)

Best for: Development, testing, one-off runs

```powershell
# Run with default 10 iterations
.\ralph.ps1 run

# Run with specific iteration count
.\ralph.ps1 run 20
```

**Characteristics:**
- Runs in foreground
- Real-time output
- Stops when terminal closes
- Good for development

### 2. Daemon Mode (`ralph daemon`)

Best for: 24/7 autonomous operation

```powershell
# Start daemon
.\ralph.ps1 daemon start

# Check status
.\ralph.ps1 daemon status

# View logs
.\ralph.ps1 daemon logs

# Stop daemon
.\ralph.ps1 daemon stop
```

**Characteristics:**
- Runs continuously in background
- Survives terminal closure
- Process isolation per bead
- Automatic stuck bead recovery
- Log rotation
- 2-hour timeout per bead

### 3. Windows Service Mode (`install-service.ps1`)

Best for: True 24/7 operation, system-level service

```powershell
# Install as Windows Service (requires Admin)
.\install-service.ps1 -Install

# Check status
.\install-service.ps1 -Status

# Restart service
.\install-service.ps1 -Restart

# Remove service
.\install-service.ps1 -Uninstall
```

**Characteristics:**
- Runs as SYSTEM (before user login)
- Starts automatically on boot
- Automatic restart on failure
- Logs to Windows Event Log
- Most reliable for production

---

## 📊 Health Monitoring

### Quick Status Check

```powershell
# Full diagnostic
.\ralph.ps1 doctor

# Quick status only
.\ralph.ps1 status

# View logs
.\ralph.ps1 logs
```

### Sample Output

```
Ralph Diagnostics
=================

Checking prerequisites...
✓ PowerShell 7.4.0
✓ Kimi CLI (v1.2.3)
✓ Git installed

Checking workspace structure...
✓ prd.json exists
✓ KIMI.md exists
✓ .ralph/ directory exists

Checking daemon status...
✓ Daemon running (PID: 12345)

=================
✓ All checks passed! Ralph is ready.
```

---

## 🔧 Troubleshooting

### PowerShell 7 Not Found

```powershell
# Install PowerShell 7
winget install Microsoft.PowerShell

# Or download from GitHub
https://github.com/PowerShell/PowerShell/releases
```

### Kimi CLI Not Found

```powershell
# Install
pip install kimi-cli

# Authenticate
kimi config set api_key <your-key>
```

### Workspace Not Initialized

```powershell
# Initialize workspace
.\ralph.ps1 init

# Check health
.\ralph.ps1 doctor
```

### Daemon Won't Start

```powershell
# Check for issues
.\ralph.ps1 doctor --fix

# Try running in foreground
.\ralph.ps1 run 1
```

---

## ⚙️ Configuration

### PRD Format

```json
{
  "project": "MyApp",
  "branchName": "ralph/feature-branch",
  "description": "Feature description",
  "userStories": [
    {
      "id": "US-001",
      "title": "Add user authentication",
      "description": "As a user, I want to log in...",
      "acceptanceCriteria": [
        "Login form validates email",
        "Password must be 8+ characters",
        "Tests pass"
      ],
      "priority": 1,
      "passes": false
    }
  ]
}
```

---

## 🛡️ Reliability Features

- **Process Isolation** - Each bead runs in separate process
- **Stuck Bead Detection** - Auto-reset beads stuck >2 hours
- **Log Rotation** - Prevents disk space issues
- **Retry Logic** - Retries failed beads up to 3 times
- **UTF-8 BOM Handling** - Proper encoding handling
- **Graceful Shutdown** - Clean exit on Ctrl+C

---

## 🤝 Contributing

Contributions welcome! Areas for improvement:

- Additional templates
- MCP server integrations
- CI/CD workflow templates
- Language/framework support

---

## 📝 Credits

- Original Ralph pattern by [Geoffrey Huntley](https://ghuntley.com/ralph)
- Original Ralph implementation by [Snarktank](https://github.com/snarktank/ralph)
- Production-grade improvements by [nicklynch10](https://github.com/nicklynch10)

---

## 📄 License

MIT License - see LICENSE file.
