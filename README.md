# Ralph for Kimi Code CLI - Production CI/CD Agent

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![PowerShell 7](https://img.shields.io/badge/PowerShell-7+-blue.svg)](https://github.com/PowerShell/PowerShell)

Ralph is a **24/7 autonomous CI/CD agent** that runs [Kimi Code CLI](https://github.com/moonshotai/kimi-cli) repeatedly until all PRD (Product Requirements Document) items are complete. Designed for production-grade reliability with process isolation, automatic recovery, and comprehensive health monitoring.

> **Core Philosophy**: Like a CI/CD pipeline that never sleeps, Ralph continuously works through your product requirements, verifying each change before moving to the next.

Based on the [Ralph pattern](https://ghuntley.com/ralph) by Geoffrey Huntley.

---

## ⚡ Quick Start

### Prerequisites

| Requirement | Version | Install Command |
|-------------|---------|-----------------|
| **PowerShell** | 7.0+ | `winget install Microsoft.PowerShell` |
| **Kimi CLI** | Latest | `pip install kimi-cli` |
| **Git** | 2.0+ | `winget install Git.Git` |

### Installation

```powershell
# Clone the repository
git clone https://github.com/nicklynch10/ralph-simple.git
cd ralph-simple

# Copy to your project
copy *.ps1 C:\path\to\your\project\
copy KIMI.md C:\path\to\your\project\
```

### Create Your PRD

Create a `prd.json` file in your project:

```json
{
  "project": "MyApp",
  "branchName": "ralph/feature-name",
  "description": "Feature description",
  "userStories": [
    {
      "id": "US-001",
      "title": "Add user authentication",
      "description": "As a user, I want to log in...",
      "acceptanceCriteria": [
        "Login form validates email format",
        "Password must be 8+ characters",
        "Typecheck passes",
        "Tests pass"
      ],
      "priority": 1,
      "passes": false
    }
  ]
}
```

### Run Ralph

```powershell
# Interactive mode (10 iterations)
.\ralph.ps1

# Run 20 iterations
.\ralph.ps1 20

# Check health
.\ralph.ps1 -Health

# Start production daemon (24/7)
.\ralph.ps1 -Daemon
```

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    Ralph v2.1 Production Architecture                    │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   ┌──────────────┐     ┌──────────────┐     ┌──────────────┐            │
│   │  ralph.ps1   │     │ralph-daemon  │     │ralph-health  │            │
│   │  (interactive│     │(24/7 service)│     │(monitoring)  │            │
│   └──────┬───────┘     └──────┬───────┘     └──────────────┘            │
│          │                    │                                          │
│          └─────────┬──────────┘                                          │
│                    │                                                     │
│           ┌────────▼────────┐                                            │
│           │   ralph-core    │  ← Shared functions (JSON, logging, git)   │
│           │    module       │                                            │
│           └────────┬────────┘                                            │
│                    │                                                     │
│    ┌───────────────┼───────────────┐                                    │
│    │               │               │                                    │
│    ▼               ▼               ▼                                    │
│ ┌──────┐      ┌──────┐      ┌──────────┐                               │
│ │Kimi  │      │ Git  │      │  prd.json│                               │
│ │CLI   │      │      │      │          │                               │
│ └──────┘      └──────┘      └──────────┘                               │
│                                                                          │
│  Memory: git history + prd.json + progress.txt + bead files             │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Key Components

| Component | Purpose | Use When |
|-----------|---------|----------|
| `ralph.ps1` | Interactive mode | Development, testing, one-off runs |
| `ralph-daemon.ps1` | 24/7 daemon | Production, CI/CD, long-running tasks |
| `ralph-health.ps1` | Health monitoring | Troubleshooting, maintenance |
| `install-service.ps1` | Windows Service | System-level 24/7 operation |
| `ralph-core.ps1` | Shared functions | Custom scripts, module import |

---

## 🚀 Running Modes

### 1. Interactive Mode (`ralph.ps1`)

Best for: Development, testing, one-off runs

```powershell
# Run with default 10 iterations
.\ralph.ps1

# Run with specific iteration count
.\ralph.ps1 20

# Show help
.\ralph.ps1 -Help
```

**Characteristics:**
- Runs in foreground
- Real-time output
- Stops when terminal closes
- Good for development

### 2. Production Daemon Mode (`ralph-daemon.ps1`)

Best for: 24/7 autonomous operation, CI/CD, long-running tasks

```powershell
# Start daemon in foreground (for testing)
.\ralph.ps1 -Daemon

# Start daemon as background job
Start-Process pwsh -ArgumentList "-File .\ralph-daemon.ps1" -WindowStyle Hidden

# Install as Windows scheduled task (runs on login)
.\ralph.ps1 -InstallTask
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
.\ralph.ps1 -Health

# Quick status only
.\ralph.ps1 -Status

# Check beads only
.\ralph-health.ps1 -Beads

# View recent logs
.\ralph-health.ps1 -Logs
```

### Automated Maintenance

```powershell
# Reset stuck beads
.\ralph.ps1 -ResetStuck

# Auto-fix common issues
.\ralph.ps1 -Health -Fix
```

### Sample Health Output

```
Ralph Health Check v2.1.0
======================================
Workspace: C:\Projects\MyApp

Prerequisites:
  [OK] Kimi CLI: v1.2.3
  [OK] Git: git version 2.40.0
  [OK] PowerShell: Version 7.4.0

Configuration:
  [OK] PRD File: 3/5 stories complete
  [OK] Prompt File: 3300 bytes
  [OK] Git Repository: Branch: ralph/feature, clean

Daemon Status:
  [RUNNING] Daemon Process: PID: 12345
  [Ready] Scheduled Task: Installed

Bead Status:
  Total: 5
  Pending: 2
  In Progress: 0
  Completed: 3
  Failed: 0

Overall Status: HEALTHY
```

---

## 🔧 Troubleshooting

### PowerShell 7 Not Found

**Problem:** `pwsh: The term 'pwsh' is not recognized`

**Solution:**
```powershell
# Install PowerShell 7
winget install Microsoft.PowerShell

# Or download from GitHub
https://github.com/PowerShell/PowerShell/releases
```

### UTF-8 BOM Errors

**Problem:** `ConvertFrom-Json: Unexpected UTF-8 BOM`

**Solution:** Ralph v2.1 handles BOM automatically. If you encounter this:

```powershell
# Fix a specific file
$content = Get-Content file.json -Raw -Encoding UTF8
if ($content[0] -eq "`ufeff") { $content = $content.Substring(1) }
$content | ConvertFrom-Json
```

### Daemon Not Starting

**Problem:** Daemon fails to start or immediately exits.

**Solution:**
```powershell
# Check for errors
.\ralph.ps1 -Health

# Try running in foreground to see errors
.\ralph.ps1 -Daemon

# Check prerequisites
kimi --version
git --version
pwsh --version
```

### Stuck Beads

**Problem:** Beads remain "in_progress" indefinitely.

**Solution:**
```powershell
# Check for stuck beads
.\ralph.ps1 -Status

# Reset stuck beads manually
.\ralph.ps1 -ResetStuck

# Or use health check with fix
.\ralph.ps1 -Health -Fix
```

### Kimi CLI Hanging

**Problem:** Kimi CLI process hangs and never completes.

**Solution:** The daemon has a 2-hour timeout. If Kimi hangs:
1. Check your internet connection
2. Verify API key: `kimi config get api_key`
3. Check Kimi status page
4. Restart daemon: `Get-Process *ralph* | Stop-Process; .\ralph.ps1 -Daemon`

---

## 📁 File Reference

### Core Files

| File | Purpose | When to Use |
|------|---------|-------------|
| `ralph.ps1` | Main entry point | Always - dispatches to other scripts |
| `ralph-core.ps1` | Core functions module | Import for custom scripts |
| `ralph-daemon.ps1` | Production daemon | 24/7 operation |
| `ralph-health.ps1` | Health monitoring | Troubleshooting |
| `install-service.ps1` | Windows Service installer | System-level service |
| `ralph.sh` | Linux/Mac version | Cross-platform support |
| `KIMI.md` | Agent instructions | Kimi reads this |

### Configuration Files

| File | Purpose | Format |
|------|---------|--------|
| `prd.json` | Product requirements | JSON |
| `test-plan.json` | Test coverage | JSON |
| `progress.txt` | Execution log | Markdown |
| `.last-branch` | Branch tracking | Plain text |

### Generated Directories

| Directory | Contents | Managed By |
|-----------|----------|------------|
| `.ralph/` | Configuration | Ralph |
| `.ralph/logs/` | Log files | Ralph (auto-rotated) |
| `.ralph/beads/` | Bead files (daemon) | Ralph daemon |
| `archive/` | Old runs | Ralph (on branch change) |

---

## ⚙️ Configuration

### Environment Variables

```powershell
# Optional: Set custom log directory
$env:RALPH_LOG_DIR = "D:\logs\ralph"

# Optional: Set bead timeout (minutes)
$env:RALPH_BEAD_TIMEOUT = 180

# Optional: Set poll interval (seconds)
$env:RALPH_POLL_INTERVAL = 60
```

### PRD Format

```json
{
  "project": "ProjectName",
  "branchName": "ralph/feature-branch",
  "description": "What this PRD implements",
  "testDriven": true,
  "userStories": [
    {
      "id": "US-001",
      "title": "Story title",
      "description": "As a user...",
      "acceptanceCriteria": ["Criteria 1", "Criteria 2"],
      "priority": 1,
      "passes": false,
      "notes": "",
      "testing": {
        "testFirst": true,
        "testTypes": ["unit", "e2e"],
        "browserTest": true
      }
    }
  ]
}
```

---

## 🛡️ Reliability Features

### Process Isolation
Each bead runs in a separate PowerShell process to prevent:
- Memory leaks from accumulating Kimi CLI instances
- File handle exhaustion
- Cascading failures from one corrupt bead

### Stuck Bead Detection
Automatically detects and resets beads stuck for >2 hours:
- Monitors `in_progress` beads
- Resets to `retry` status
- Tracks stuck count for analysis

### Log Rotation
Prevents disk space issues:
- 10MB max per log file
- 5 backup files retained
- Automatic compression

### Retry Logic
Failed beads are retried up to 3 times before marking as failed.

### UTF-8 BOM Handling
Properly handles JSON files with or without BOM:
- Reads files with `-Encoding UTF8`
- Strips BOM if present
- Writes without BOM

---

## 🤝 Contributing

Contributions welcome! Areas for improvement:

- Additional testing strategies
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
