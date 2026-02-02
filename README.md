# Ralph for Kimi Code CLI

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Ralph is an autonomous AI agent loop that runs [Kimi Code CLI](https://github.com/moonshotai/kimi-cli) repeatedly until all PRD (Product Requirements Document) items are complete. Each iteration is a fresh instance with clean context. Memory persists via git history, `progress.txt`, and `prd.json`.

This is a port of the original [Ralph](https://github.com/snarktank/ralph) project (built for Amp and Claude Code) to work with Kimi Code CLI.

Based on the [Ralph pattern](https://ghuntley.com/ralph) by Geoffrey Huntley.

---

## Table of Contents

- [How It Works](#how-it-works)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Detailed Setup](#detailed-setup)
- [Usage](#usage)
- [Creating PRDs](#creating-prds)
- [Progress Tracking](#progress-tracking)
- [Troubleshooting](#troubleshooting)
- [Architecture](#architecture)

---

## How It Works

```
┌─────────────────────────────────────────────────────────────┐
│                        Ralph Loop                            │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐              │
│  │ Kimi CLI │───→│  Git     │───→│ prd.json │              │
│  │  (New)   │    │ (Memory) │    │ (Status) │              │
│  └──────────┘    └──────────┘    └──────────┘              │
│       ↑                                          │          │
│       └──────────┐    ┌──────────┐              │          │
│                  │    │ progress │              ↓          │
│                  └───→│  .txt    │←─────────────┘          │
│                       │(Learnings)│                         │
│                       └──────────┘                          │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

**Each iteration spawns a new Kimi instance with clean context.** The only memory between iterations is:
- **Git history** (commits from previous iterations)
- **`progress.txt`** (learnings and context)
- **`prd.json`** (which stories are done)

---

## Prerequisites

- [Kimi Code CLI](https://github.com/moonshotai/kimi-cli) installed and authenticated
- Git repository for your project
- PowerShell (Windows) or Bash (Linux/macOS)

### Installing Kimi Code CLI

```bash
# Using pip
pip install kimi-cli

# Or using uv
uv tool install kimi-cli

# Authenticate
kimi login
```

---

## Quick Start

### 1. Install Ralph in Your Project

```powershell
# Create the ralph directory
mkdir -p scripts/ralph

# Download the files (PowerShell)
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/nicklynch10/ralph-kimi/main/ralph.ps1" -OutFile "scripts/ralph/ralph.ps1"
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/nicklynch10/ralph-kimi/main/KIMI.md" -OutFile "scripts/ralph/KIMI.md"
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/nicklynch10/ralph-kimi/main/prd.json.example" -OutFile "scripts/ralph/prd.json.example"

# Or clone and copy
git clone https://github.com/nicklynch10/ralph-kimi.git /tmp/ralph-kimi
copy /tmp/ralph-kimi/ralph.ps1 scripts/ralph/
copy /tmp/ralph-kimi/KIMI.md scripts/ralph/
copy /tmp/ralph-kimi/prd.json.example scripts/ralph/
```

### 2. Install Skills (Optional but Recommended)

Copy the skills to your Kimi config for use across all projects:

```powershell
# Windows - create skills directory if it doesn't exist
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.kimi\skills"

# Copy skills
Copy-Item -Recurse "scripts/ralph/skills/prd" "$env:USERPROFILE\.kimi\skills\"
Copy-Item -Recurse "scripts/ralph/skills/ralph" "$env:USERPROFILE\.kimi\skills\"
```

```bash
# Linux/Mac
mkdir -p ~/.kimi/skills
cp -r scripts/ralph/skills/prd ~/.kimi/skills/
cp -r scripts/ralph/skills/ralph ~/.kimi/skills/
```

### 3. Create Your First PRD

Start Kimi and use the PRD skill:

```bash
kimi
```

Then type:
```
/skill:prd
```

Answer the questions to generate a PRD. It will be saved to `tasks/prd-[feature-name].md`.

### 4. Convert to Ralph Format

```
/skill:ralph
```

This converts your markdown PRD to `scripts/ralph/prd.json`.

### 5. Run Ralph

```powershell
# Windows PowerShell
.\scripts\ralph\ralph.ps1

# Or specify iterations
.\scripts\ralph\ralph.ps1 20
```

```bash
# Linux/Mac
./scripts/ralph/ralph.sh

# Or specify iterations
./scripts/ralph/ralph.sh 20
```

---

## Detailed Setup

### Project Structure After Setup

```
your-project/
├── scripts/
│   └── ralph/
│       ├── ralph.ps1          # Main script (Windows)
│       ├── ralph.sh           # Main script (Linux/Mac)
│       ├── KIMI.md            # Prompt template
│       ├── prd.json           # Your tasks (generated)
│       ├── prd.json.example   # Example format
│       ├── progress.txt       # Learnings log (generated)
│       └── archive/           # Old runs (auto-created)
├── tasks/
│   └── prd-your-feature.md    # Your PRD
├── src/                       # Your code
└── ...
```

### Customizing KIMI.md

Edit `scripts/ralph/KIMI.md` to add:

- **Project-specific quality checks** (e.g., `npm run typecheck`, `pytest`)
- **Code conventions** specific to your stack
- **Common gotchas** in your codebase

Example additions:
```markdown
## Project-Specific Commands

Run these quality checks before committing:
- `npm run typecheck` - TypeScript type checking
- `npm run lint` - ESLint
- `npm run test:unit` - Unit tests

## Code Conventions

- Use TypeScript strict mode
- Prefer functional components
- Use `async/await` over callbacks
```

---

## Usage

### Running Ralph

```powershell
# Default: 10 iterations
.\scripts\ralph\ralph.ps1

# Custom iterations
.\scripts\ralph\ralph.ps1 5

# Unlimited (be careful!)
.\scripts\ralph\ralph.ps1 100
```

### What Ralph Does Each Iteration

1. **Reads** `prd.json` and `progress.txt`
2. **Picks** the highest priority incomplete story
3. **Implements** that single story
4. **Runs** quality checks
5. **Commits** changes with message: `feat: [Story ID] - [Story Title]`
6. **Updates** `prd.json` to mark story complete
7. **Appends** learnings to `progress.txt`
8. **Repeats** until all stories done or max iterations reached

### Stopping Ralph

- Press `Ctrl+C` to stop gracefully
- Ralph can be restarted and will pick up where it left off

---

## Creating PRDs

### Good Story Size

**✅ Right-sized stories (completable in one iteration):**
- Add a database column and migration
- Add a UI component to an existing page
- Update a server action with new logic
- Add a filter dropdown to a list

**❌ Too big (split these):**
- "Build the entire dashboard"
- "Add authentication"
- "Refactor the API"

### PRD JSON Format

```json
{
  "project": "MyApp",
  "branchName": "ralph/feature-name",
  "description": "Feature description",
  "userStories": [
    {
      "id": "US-001",
      "title": "Story title",
      "description": "As a user, I want...",
      "acceptanceCriteria": [
        "Specific criterion 1",
        "Specific criterion 2",
        "Typecheck passes"
      ],
      "priority": 1,
      "passes": false,
      "notes": ""
    }
  ]
}
```

---

## Progress Tracking

### During a Run

In another terminal, watch progress:

```powershell
# Watch PRD status
while ($true) { clear; Get-Content scripts/ralph/prd.json | ConvertFrom-Json | Select-Object -ExpandProperty userStories | Select-Object id, passes; Start-Sleep -Seconds 10 }

# Watch git log
while ($true) { clear; git log --oneline -5; Start-Sleep -Seconds 10 }

# Watch progress file
while ($true) { clear; Get-Content scripts/ralph/progress.txt; Start-Sleep -Seconds 10 }
```

### After a Run

```powershell
# See which stories are done
cat scripts/ralph/prd.json | ConvertFrom-Json | Select-Object -ExpandProperty userStories | Select-Object id, title, passes

# See learnings
cat scripts/ralph/progress.txt

# See git history
git log --oneline -10
```

---

## Troubleshooting

### Each Iteration Takes a Long Time

**This is normal!** Each iteration takes 30-120+ seconds because Kimi is:
- Reading and analyzing your codebase
- Understanding the task from PRD
- Implementing the solution
- Running quality checks
- Committing changes

Ralph is designed for **autonomy**, not speed. Let it run - go get coffee! ☕

### Kimi Not Found

```powershell
# Check if kimi is installed
kimi --version

# If not found, add to PATH or reinstall
pip install kimi-cli
```

### Git Errors

Make sure you're in a git repository:
```bash
git status

# If not initialized:
git init
git add .
git commit -m "Initial commit"
```

### PRD Not Found

Create one first:
```
/skill:prd
```

Or manually create `scripts/ralph/prd.json` based on the example.

### Stories Not Being Marked Complete

Check that:
1. Kimi is outputting the completion signal `<promise>COMPLETE</promise>`
2. The `prd.json` file is being updated
3. Git commits are being made

Check `scripts/ralph/progress.txt` for errors.

---

## Architecture

### File Purposes

| File | Purpose |
|------|---------|
| `ralph.ps1` / `ralph.sh` | The orchestration loop that spawns fresh Kimi instances |
| `KIMI.md` | The prompt template given to Kimi each iteration |
| `prd.json` | The task list with completion status |
| `progress.txt` | Append-only log of learnings for future iterations |
| `skills/prd/SKILL.md` | Skill for generating PRDs interactively |
| `skills/ralph/SKILL.md` | Skill for converting PRDs to JSON format |

### Memory Model

Ralph has no memory between iterations except:

1. **Git commits** - Code changes persist
2. **`prd.json`** - Task completion status
3. **`progress.txt`** - Learnings and patterns discovered
4. **AGENTS.md files** - Codebase documentation (updated by Kimi)

This is intentional - each Kimi instance starts fresh with clean context.

### Completion Detection

When all stories have `passes: true`, Kimi outputs:
```
<promise>COMPLETE</promise>
```

The script detects this and exits successfully.

---

## Contributing

Contributions welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

---

## License

MIT License - see [LICENSE](LICENSE) file for details.

---

## Credits

- Original Ralph pattern by [Geoffrey Huntley](https://ghuntley.com/ralph)
- Original Ralph implementation for Amp/Claude by [Snarktank](https://github.com/snarktank/ralph)
- Ported to Kimi Code CLI by [nicklynch10](https://github.com/nicklynch10)

---

## Related

- [Kimi Code CLI](https://github.com/moonshotai/kimi-cli) - The AI coding tool
- [Original Ralph](https://github.com/snarktank/ralph) - For Amp and Claude Code
- [Ralph Pattern](https://ghuntley.com/ralph) - The philosophy behind Ralph
