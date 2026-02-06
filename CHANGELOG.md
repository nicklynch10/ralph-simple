# Changelog

All notable changes to the Ralph for Kimi Code CLI project.

## [2.2.2] - 2026-02-06

### Production Hardening - Independent Agent Testing Results

This release addresses all issues identified during extensive independent agent testing. The daemon is now significantly more robust for 24/7 operation.

#### Fixed (P0 - Critical)

- **Bead Property Initialization (CRITICAL)**
  - Added `Initialize-BeadSchema` function for comprehensive bead validation
  - Ensures ALL required fields exist: core fields, ralph_meta, dod, constraints
  - Prevents "property cannot be found" errors on manually created beads
  - Automatic schema migration for beads from older versions

- **Retry Logic Bug - Enhanced PRD Verification**
  - Dual verification: checks bead status AND PRD `passes` field
  - Daemon now correctly detects completion even if bead file wasn't updated
  - Prevents false "incomplete" statuses causing infinite retry loops

#### Fixed (P1 - High Priority)

- **Save-Bead Atomic Writes with Backup/Restore**
  - Implemented full atomic write pattern: temp -> backup -> move -> cleanup
  - Automatic restore from backup on write failure
  - Prevents bead corruption on concurrent writes or crashes

- **Enhanced Convert-PrdToBeads Function**
  - Full schema initialization with all required fields
  - PRD linkage metadata (story_id, project, branch_name)
  - Test file verifiers auto-generated from PRD testing metadata
  - Backup/restore safety for bead updates

#### Fixed (P2 - Medium Priority)

- **Daemon Auto-Restart with Exponential Backoff**
  - Replaced "stop after 5 errors" with intelligent restart logic
  - Exponential backoff: 30s -> 60s -> 120s -> ... -> max 10 minutes
  - Configurable via `RestartOnFailure`, `RestartDelaySeconds`, `MaxRestartDelaySeconds`
  - Daemon now truly runs 24/7, recovering from transient failures

- **PowerShell Version Detection**
  - New `Get-PowerShellPath` function with proper cross-platform detection
  - Tries PowerShell 7+ first, falls back to PowerShell 5.1 with warning
  - Clear error message if no PowerShell found

#### Added

- **Bead Schema Documentation**
  - Complete bead schema specification in AGENTS.md
  - All fields documented with types and defaults
  - Migration guide for custom bead creation

#### Changed

- **Version bumped to 2.2.2** across all scripts
- **Improved error logging** with consecutive error counters
- **Enhanced daemon logging** with restart/backoff information

---

## [2.2.1] - 2026-02-06

### Critical Bug Fixes - Production Stability

This release addresses all critical issues identified during extensive independent agent testing. All P0 and P1 issues have been resolved.

#### Fixed (P0 - Critical)

- **PowerShell Unicode Escape Syntax Error**
  - Fixed invalid `\ufeff` syntax to proper `\u{feff}` (PowerShell 7+ requires curly braces)
  - Affected: ralph-core.ps1, ralph-daemon.ps1, ralph-health.ps1, ralph.ps1
  - Was causing ParserError when reading UTF-8 BOM files

- **Export-ModuleMember Runtime Error**
  - Wrapped `Export-ModuleMember` in module check: `if ($MyInvocation.MyCommand.ScriptBlock.Module)`
  - Prevents "can only be called from inside a module" error when dot-sourcing

- **Daemon Retry Logic Bug (Critical)**
  - Fixed issue where beads with exit code 0 were incorrectly marked for retry
  - Root cause: Status check happened before PRD synchronization
  - Fix: Added dual verification - checks both bead status AND PRD `passes` field
  - New `Get-PrdForBead` function provides source-of-truth verification

#### Fixed (P1 - High Priority)

- **Missing Bead Schema Properties**
  - Added defensive property initialization in `Get-Bead`
  - Ensures `last_attempt`, `status_detail`, `attempt_count`, `timeout_count`, `stuck_count` exist
  - Prevents "property cannot be found" errors on manually created beads

- **PRD-to-Bead Synchronization Gap**
  - Daemon now verifies completion against PRD, not just exit code
  - Ralph updates PRD when stories complete; daemon reads PRD to confirm
  - Eliminates false "incomplete" statuses

#### Fixed (P2 - Medium Priority)

- **Process Isolation Timeout Handling**
  - Added `HasExited` check before `Stop-Process` to prevent race conditions
  - Process may exit between timeout detection and kill attempt

- **Log Directory Creation Race Condition**
  - Added `-ErrorAction SilentlyContinue` to `New-Item` calls
  - Multiple simultaneous executions no longer cause errors

- **Bead File Corruption on Concurrent Writes**
  - Implemented atomic write pattern: write to temp file, then `Move-Item`
  - Prevents JSON corruption when multiple processes write same bead

- **Cross-Platform PowerShell Compatibility**
  - Replaced hardcoded `pwsh.exe` with dynamic detection
  - Uses `Get-Command` to find appropriate PowerShell executable
  - Works on Windows (pwsh.exe/powershell.exe), Linux/Mac (pwsh/powershell)

#### Added

- **`Convert-PrdToBeads` Function** (ralph-core.ps1)
  - Converts PRD user stories to bead files for daemon processing
  - Usage: `Convert-PrdToBeads -PrdPath "prd.json" -BeadsDir ".ralph/beads"`
  - Preserves existing beads (use `-Force` to overwrite)
  - Auto-generates verifiers from acceptance criteria

#### Changed

- **Version bumped to 2.2.1** across all scripts
- **Standardized UTF-8 BOM handling** - all files now use `\u{feff}` syntax
- **Documentation updated** in AGENTS.md with correct syntax examples

---

## [2.1.0] - 2026-02-06

### Major Changes - PowerShell 7 & Windows Service Support

This release upgrades Ralph to require PowerShell 7.0+ and adds true Windows Service support for enterprise-grade 24/7 operation.

#### Added

- **install-service.ps1** - Windows Service installer using NSSM
  - True Windows Service (runs as SYSTEM, before login)
  - Automatic restart on failure
  - Windows Event Log integration
  - Service management (start/stop/restart/status)
  - Auto-downloads NSSM if not present

- **Test-RalphVerifier** function in ralph-core.ps1
  - Pipeline deadlock prevention using file-based output
  - 20-minute default timeout for Kimi sessions
  - Isolated process execution for verifiers

#### Changed

- **PowerShell 7.0+ Required**
  - All scripts now require `#requires -Version 7.0`
  - Uses `pwsh.exe` instead of `powershell.exe`
  - Better cross-platform compatibility
  - Improved performance and modern language features
  - Install: `winget install Microsoft.PowerShell`

- **ralph-daemon.ps1** - Updated for PowerShell 7
  - Uses `pwsh.exe` for process isolation
  - Improved error handling

- **ralph-health.ps1** - Updated prerequisites check
  - Now checks for PowerShell 7.0+
  - Clear error message if wrong version detected

- **Documentation Updates**
  - README.md: PowerShell 7 requirement prominently displayed
  - AGENTS.md: Technical details for PowerShell 7
  - KIMI.md: System requirements section

#### Fixed

- **Substring Error on Array Output**
  - Fixed error when Kimi output is an array instead of string
  - Now uses `$output -join "`n"` to convert arrays to strings

- **Missing Bead Properties**
  - Defensive handling for `created_at` and `updated_at` fields
  - Uses `Add-Member` with `-Force` for optional properties

- **Verifier Timeout Too Short**
  - Increased default from 5 minutes to 20 minutes
  - Accommodates long Kimi sessions and complex implementations

---

## [2.0.0] - 2026-02-06

### Major Changes - Production-Grade Reliability

This release addresses all critical issues identified during extensive production testing. The codebase has been completely restructured for reliability, maintainability, and proper error handling.

#### Added

- **ralph-core.ps1** - New core module with reusable functions
  - UTF-8 BOM safe JSON reading/writing (`Read-RalphJson`, `Write-RalphJson`)
  - Centralized logging system (`Write-RalphLog`)
  - PRD operations (`Get-RalphPrd`, `Update-StoryStatus`, `Test-AllStoriesComplete`)
  - Git integration (`Invoke-RalphGitCommit`, `Invoke-RalphArchive`)
  - Kimi CLI invocation with timeout (`Invoke-RalphKimi`)
  - Proper Ctrl+C handling using `Console.CancelKeyPress`

- **ralph-daemon.ps1** - Production daemon for 24/7 operation
  - Process isolation (each bead runs in separate process)
  - 2-hour hard timeout per bead with forced termination
  - Automatic stuck bead detection and recovery (>2 hours)
  - Log rotation (10MB max, 5 files)
  - Windows Task Scheduler integration (`-InstallTask`, `-UninstallTask`)
  - Retry logic (max 3 attempts per bead)
  - Individual log files per bead execution

- **ralph-health.ps1** - Health monitoring and diagnostics
  - Prerequisite checks (Kimi CLI, Git, PowerShell version)
  - PRD validation
  - Daemon process status
  - Bead status with stuck detection
  - Auto-fix mode (`-Fix`)
  - Log viewing (`-Logs`)

#### Fixed

- **PowerShell 5.1 Compatibility**
  - Changed all `pwsh` references to `powershell`
  - Removed PowerShell 7+ syntax (null coalescing, null conditional)
  - Verified on Windows PowerShell 5.1

- **UTF-8 BOM Handling**
  - Fixed `ConvertFrom-Json` failures on BOM files
  - All JSON reads now use `-Raw -Encoding UTF8` with BOM stripping
  - All JSON writes use `UTF8Encoding($false)` for no BOM

- **False Ctrl+C Detection**
  - Replaced `trap` statement with `Console.CancelKeyPress` event
  - Kimi CLI exit codes no longer trigger false interrupts
  - Graceful shutdown on actual Ctrl+C

- **Pipeline Deadlocks**
  - Replaced pipeline capture with file-based output
  - Uses `Start-Process` with proper redirection
  - Prevents buffer exhaustion on long-running processes

- **Missing Property Errors**
  - Added defensive checks for `updated_at` and other optional fields
  - Uses `Add-Member` with `-Force` for dynamic properties

#### Changed

- **ralph.ps1** - Complete rewrite as dispatcher
  - Now routes to specialized scripts based on parameters
  - Simple mode: `.\ralph.ps1 [iterations]`
  - Daemon mode: `.\ralph.ps1 -Daemon`
  - Health mode: `.\ralph.ps1 -Health`
  - Status mode: `.\ralph.ps1 -Status`

- **ralph.sh** - Updated with same fixes
  - UTF-8 BOM handling with `sed`
  - Proper error handling without `trap` issues
  - Daemon mode support
  - Health check mode

- **KIMI.md** - Enhanced with troubleshooting
  - Added encoding notes section
  - Better error handling guidance
  - Context conservation strategies

- **README.md** - Comprehensive rewrite
  - Production deployment guide
  - Architecture diagrams
  - Windows/Linux/Mac instructions
  - Troubleshooting section

- **AGENTS.md** - Complete rewrite
  - Architecture documentation
  - Critical implementation details
  - Testing procedures
  - Code style guidelines

---

## [1.1.0] - 2026-02-02

### Added

- Test-driven development support
- Browser testing with Playwright MCP
- `test-plan.json` format
- Example PRD with testing metadata

### Changed

- Enhanced KIMI.md with testing instructions
- Updated README with test-driven flow

---

## [1.0.0] - 2026-02-01

### Added

- Initial release
- Basic Ralph loop (`ralph.ps1`)
- Linux/Mac support (`ralph.sh`)
- PRD format (`prd.json`)
- Progress tracking (`progress.txt`)
- Git integration
- Archive functionality

---

## Version Numbering

Ralph follows [Semantic Versioning](https://semver.org/):

- **MAJOR** - Breaking changes to file formats or APIs
- **MINOR** - New features, backward compatible
- **PATCH** - Bug fixes, backward compatible

### Version Compatibility

| Ralph Version | prd.json | progress.txt | PowerShell |
|---------------|----------|--------------|------------|
| 2.2.x | Compatible | Compatible | 7.0+ |
| 2.1.x | Compatible | Compatible | 7.0+ |
| 2.0.x | Compatible | Compatible | 5.1+ |
| 1.1.x | Compatible | Compatible | 5.1+ |
| 1.0.x | Compatible | Compatible | 5.1+ |

All versions use the same `prd.json` format and are fully backward compatible.

### Migration Guide

#### From v2.1 to v2.2

1. **Update your scripts**
   ```powershell
   # Copy new files (all P0 bugs fixed)
   copy ralph.ps1 my-project\
   copy ralph-core.ps1 my-project\
   copy ralph-daemon.ps1 my-project\
   copy ralph-health.ps1 my-project\
   ```

2. **Optional: Convert existing PRD to beads**
   ```powershell
   # Import core module
   . ./ralph-core.ps1
   
   # Convert PRD stories to beads
   Convert-PrdToBeads
   ```

3. **No breaking changes** - all file formats remain compatible

#### From v2.0 to v2.1

1. **Install PowerShell 7** (if not already installed)
   ```powershell
   winget install Microsoft.PowerShell
   ```

2. **Update your scripts**
   ```powershell
   # Copy new files
   copy ralph.ps1 my-project\
   copy ralph-core.ps1 my-project\
   copy ralph-daemon.ps1 my-project\
   copy ralph-health.ps1 my-project\
   copy install-service.ps1 my-project\
   copy KIMI.md my-project\
   ```

3. **Optional: Install as Windows Service** (for true 24/7 operation)
   ```powershell
   # Run as Administrator
   .\install-service.ps1 -Install
   ```

#### From v1.x to v2.0

1. **Backup your existing Ralph files**
   ```powershell
   copy ralph.ps1 ralph.ps1.backup
   copy KIMI.md KIMI.md.backup
   ```

2. **Copy new files**
   ```powershell
   copy ralph.ps1 my-project\
   copy ralph-core.ps1 my-project\
   copy ralph-daemon.ps1 my-project\
   copy ralph-health.ps1 my-project\
   copy KIMI.md my-project\
   ```

3. **Update your workflow**
   - Interactive mode: Same as before (`.\ralph.ps1`)
   - For 24/7 operation: Use `.\ralph.ps1 -Daemon`
   - For monitoring: Use `.\ralph.ps1 -Health`

4. **No changes needed to:**
   - `prd.json` format (fully backward compatible)
   - `progress.txt` (automatically handled)
   - Git repository structure
