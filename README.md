# Ralph - 24/7 Autonomous CI/CD Agent

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![PowerShell 7](https://img.shields.io/badge/PowerShell-7+-blue.svg)](https://github.com/PowerShell/PowerShell)

**Ralph is a continuous, autonomous CI/CD agent** that runs 24/7, processing work items (beads) from your PRD until all requirements are complete. Think of it as a CI/CD pipeline that never sleeps.

> **⚠️ IMPORTANT**: Ralph is designed to run **continuously as a daemon**, NOT as a cron job or scheduled task. It manages its own scheduling, retry logic, and recovery. Starting it multiple times or using cron defeats its self-healing architecture.

**Core Design**: Start once, run forever. Ralph automatically picks up the next bead, processes it, and moves on. No external scheduling needed.

---

## Quick Start (Production Setup)

### 1. Install Prerequisites

```powershell
# PowerShell 7 (required)
winget install Microsoft.PowerShell

# Kimi CLI
pip install kimi-cli

# Configure Kimi CLI with Moonshot API Key
# Get your key from: https://platform.moonshot.cn/
kimi config set api_key sk-your-moonshot-api-key-here

# Git
winget install Git.Git
```

**⚠️ IMPORTANT: API Key Configuration**

Ralph uses the Kimi CLI, which requires a Moonshot API key (not Kimi login):

1. Go to https://platform.moonshot.cn/ (Moonshot AI platform)
2. Create an account and generate an API key
3. Set it in Kimi CLI: `kimi config set api_key sk-...`

**Verify it works:**
```powershell
kimi --version
kimi config get api_key  # Should show your key
```

**Common Issues:**
- ❌ Don't use `kimi login` (opens browser, not needed)
- ❌ Don't use Kimi web app credentials
- ✅ Use Moonshot API key from https://platform.moonshot.cn/
- ✅ Key format: `sk-xxxxxxxxxxxxxxxx`

### 2. Initialize & Start

```powershell
# Clone and setup
git clone https://github.com/nicklynch10/ralph-simple.git
copy ralph-simple\*.ps1 C:\path\to\your\project\
cd C:\path\to\your\project

# Initialize workspace
.\ralph.ps1 init

# Convert PRD to beads (one-time setup)
$ beads = Convert-PrdToBeads

# Start 24/7 daemon (this is the main way to run Ralph)
.\ralph.ps1 daemon start
```

That's it. Ralph now runs continuously, processing beads until all work is complete.

---

## How It Works

```
┌─────────────────────────────────────────────────────────────────┐
│                     Ralph Daemon (24/7)                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐         │
│  │  Poll for   │───▶│ Pick highest │───▶│  Process    │         │
│  │  beads      │    │ priority     │    │  bead       │         │
│  └─────────────┘    └─────────────┘    └─────────────┘         │
│       ▲                                        │                 │
│       │                                        ▼                 │
│       │                               ┌─────────────┐           │
│       │                               │ Update PRD  │           │
│       │                               │ on complete │           │
│       │                               └─────────────┘           │
│       │                                        │                 │
│       └────────────────────────────────────────┘                 │
│                                                                  │
│  Features:                                                       │
│  • Self-healing: Auto-restart on failure (exponential backoff)  │
│  • Process isolation: Each bead in separate process             │
│  • Stuck detection: Auto-reset beads stuck >2 hours             │
│  • Atomic writes: No corruption on crashes                      │
│  • No cron needed: Built-in polling loop                        │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Architecture Philosophy

### ❌ DON'T: Cron/Scheduled Tasks

```bash
# WRONG - Don't do this
crontab -e
# */5 * * * * /path/to/ralph.sh  # This defeats the purpose!
```

Problems with cron approach:
- Multiple instances can conflict
- No state awareness between runs
- No stuck bead detection
- No exponential backoff on failures
- Wastes resources starting/stopping

### ✅ DO: Start Once, Run Forever

```powershell
# RIGHT - Start the daemon once
.\ralph.ps1 daemon start

# It will:
# - Poll for beads every 30 seconds
# - Process each bead to completion
# - Auto-restart on failure
# - Run until all work is done
```

---

## Commands

### Essential Commands

| Command | Purpose | When to Use |
|---------|---------|-------------|
| `ralph init` | Initialize workspace | First time setup |
| `ralph daemon start` | **Start 24/7 daemon** | **Primary way to run** |
| `ralph daemon status` | Check if running | Monitoring |
| `ralph daemon logs` | View recent activity | Debugging |
| `ralph daemon stop` | Stop the daemon | Maintenance |

### Development Commands

| Command | Purpose | When to Use |
|---------|---------|-------------|
| `ralph run` | Run one iteration | Testing/debugging |
| `ralph doctor` | Check health | Troubleshooting |
| `ralph status` | View progress | Quick check |

---

## Running Modes Explained

### Production Mode: Daemon (Recommended)

```powershell
# Start once, runs forever
.\ralph.ps1 daemon start

# Check status anytime
.\ralph.ps1 daemon status

# View logs
.\ralph.ps1 daemon logs
```

**Characteristics:**
- ✅ Continuous 24/7 operation
- ✅ Self-healing with exponential backoff
- ✅ Process isolation per bead
- ✅ Automatic stuck bead recovery
- ✅ Log rotation
- ✅ Survives terminal closure

### Development Mode: Interactive

```powershell
# Run single iteration for testing
.\ralph.ps1 run 1
```

**Use only for:**
- Initial setup testing
- Debugging issues
- Verifying configuration

**Not for production** - stops when terminal closes.

### Windows Service Mode (Enterprise)

```powershell
# Run as SYSTEM service (most robust)
.\install-service.ps1 -Install
```

**Use when:**
- Machine reboots automatically
- Must run before user login
- Enterprise environment

---

## File Structure

```
.
├── ralph.ps1              # Command interface
├── ralph-core.ps1         # Core functions
├── ralph-daemon.ps1       # 24/7 daemon (heart of Ralph)
├── install-service.ps1    # Windows Service installer
├── KIMI.md                # Agent instructions
├── prd.json               # Your requirements
└── .ralph/
    ├── logs/              # Daemon logs
    └── beads/             # Work items (auto-generated)
```

---

## Workflow

### 1. Define Work (One-time)

Create `prd.json` with your user stories:

```json
{
  "project": "MyApp",
  "branchName": "ralph/feature",
  "userStories": [
    {
      "id": "US-001",
      "title": "Add login",
      "description": "User can log in",
      "priority": 1,
      "passes": false
    }
  ]
}
```

### 2. Convert to Beads (One-time)

```powershell
# Import core module
. .\ralph-core.ps1

# Convert PRD stories to beads
Convert-PrdToBeads
```

### 3. Start Daemon (Run once, runs forever)

```powershell
.\ralph.ps1 daemon start
```

Ralph will:
1. Pick the highest priority pending bead
2. Process it (invoke Kimi, run verifiers)
3. Mark complete in PRD
4. Pick the next bead
5. Repeat until all done

### 4. Monitor (Optional)

```powershell
# Check progress
.\ralph.ps1 status

# Watch logs
.\ralph.ps1 daemon logs
```

---

## Reliability Features

| Feature | Purpose |
|---------|---------|
| **Process Isolation** | Each bead runs in separate process - prevents memory leaks |
| **Auto-Restart** | Exponential backoff (30s → 10min) on failures |
| **Stuck Detection** | Auto-reset beads stuck >2 hours |
| **Atomic Writes** | Temp + backup + move pattern - no corruption |
| **Schema Validation** | Auto-fixes malformed beads |
| **Log Rotation** | Prevents disk space issues |
| **Graceful Shutdown** | Clean exit on Ctrl+C |

---

## Common Mistakes

### ❌ Mistake 1: Cron Job

```bash
# DON'T DO THIS
crontab -e
*/5 * * * * /path/to/ralph.sh
```

**Why**: Ralph has its own scheduling. Cron creates conflicts.

### ❌ Mistake 2: Multiple Instances

```powershell
# DON'T DO THIS
# Terminal 1:
.\ralph.ps1 daemon start

# Terminal 2:
.\ralph.ps1 daemon start  # Conflict!
```

**Why**: Check `ralph daemon status` first.

### ❌ Mistake 3: Scheduled Task with Intervals

```powershell
# DON'T DO THIS
# Task Scheduler: Run every 5 minutes
```

**Why**: Ralph runs continuously. Use `install-service.ps1` for boot-time start.

### ✅ Correct Approach

```powershell
# Start once
.\ralph.ps1 daemon start

# That's it. It manages itself.
```

---

## Troubleshooting

### API Key Issues (401 Invalid Authentication)

**Problem**: `401 Invalid Authentication` when Ralph tries to invoke Kimi

**Solution**:
```powershell
# 1. Get API key from Moonshot (not Kimi login)
# Visit: https://platform.moonshot.cn/
# Create API key (format: sk-xxxxxxxxxxxxxxxx)

# 2. Configure Kimi CLI
kimi config set api_key sk-your-key-here

# 3. Verify
kimi config get api_key
kimi --version
```

**Common Mistakes**:
- ❌ Using `kimi login` (opens browser, not needed)
- ❌ Using Kimi web app password
- ❌ Using wrong API endpoint
- ✅ Using Moonshot API key from https://platform.moonshot.cn/

### Check if Running

```powershell
.\ralph.ps1 daemon status
```

### View Logs

```powershell
# Recent activity
.\ralph.ps1 daemon logs

# Full log
Get-Content .ralph\logs\ralph-daemon.log -Wait
```

### Health Check

```powershell
.\ralph.ps1 doctor
```

### Reset Stuck Beads

```powershell
.\ralph-health.ps1 -ResetStuck
```

---

## Configuration

### PRD Format

```json
{
  "project": "MyApp",
  "branchName": "ralph/feature-branch",
  "userStories": [
    {
      "id": "US-001",
      "title": "Add feature",
      "description": "As a user...",
      "acceptanceCriteria": ["Test passes"],
      "priority": 1,
      "passes": false
    }
  ]
}
```

### Daemon Configuration

Edit `ralph-daemon.ps1`:

```powershell
$script:Config = @{
    PollIntervalSeconds = 30      # How often to check for work
    BeadTimeoutMinutes = 120      # Max time per bead
    MaxRetries = 3                # Retry failed beads
    RestartOnFailure = $true      # Auto-restart on error
    MaxLogSizeMB = 10             # Log rotation size
}
```

---

## Credits

- Original Ralph pattern by [Geoffrey Huntley](https://ghuntley.com/ralph)
- Production-grade implementation by [nicklynch10](https://github.com/nicklynch10)

## License

MIT License - see LICENSE file.
