# Ralph v2.2.1 - Critical Bug Fixes Summary

**Date:** 2026-02-06  
**Version:** 2.2.1  
**Status:** Production-Ready

---

## Overview

This release addresses all critical issues identified during extensive independent agent testing. All P0 and P1 issues have been resolved with minimal, clean changes that maintain backward compatibility.

---

## Issues Fixed

### P0 - Critical Issues

#### 1. PowerShell Unicode Escape Syntax Error
**Files:** `ralph-core.ps1`, `ralph-daemon.ps1`, `ralph-health.ps1`, `ralph.ps1`

**Problem:** Used invalid `\ufeff` syntax instead of proper `\u{feff}` (PowerShell 7+ requires curly braces for Unicode escapes).

**Impact:** ParserError when reading UTF-8 BOM files, causing complete script failure.

**Fix:** Replaced all 13 occurrences of `"`ufeff"` with `"`u{feff}"`.

```powershell
# Before (invalid)
if ($content[0] -eq "`ufeff") { $content = $content.Substring(1) }

# After (correct)
if ($content[0] -eq "`u{feff}") { $content = $content.Substring(1) }
```

---

#### 2. Export-ModuleMember Runtime Error
**File:** `ralph-core.ps1`

**Problem:** `Export-ModuleMember` was called when the script was dot-sourced (not imported as a module), causing:
```
The Export-ModuleMember cmdlet can only be called from inside a module
```

**Fix:** Wrapped in module check:
```powershell
if ($MyInvocation.MyCommand.ScriptBlock.Module) {
    Export-ModuleMember -Function @(...)
}
```

---

#### 3. Daemon Retry Logic Bug (Critical)
**File:** `ralph-daemon.ps1`

**Problem:** Beads with exit code 0 were incorrectly marked for retry instead of completed.

**Root Cause:** The daemon checked `$updatedBead.status` but the bead status wasn't updated before the check. Ralph updates `prd.json` when stories complete, but the daemon wasn't verifying against this source of truth.

**Fix:** Added dual verification in `Invoke-Bead`:
1. Check bead status first
2. If exit code is 0, verify against PRD's `passes` field
3. Added `Get-PrdForBead` function for PRD verification

```powershell
# CRITICAL FIX: Check both bead status AND PRD for actual completion
$isActuallyComplete = $false

# First check: bead status already marked as completed
if ($updatedBead.status -eq "completed") {
    $isActuallyComplete = $true
}
# Second check: exit code 0 AND verify against PRD that work is done
elseif ($exitCode -eq 0) {
    $prd = Get-PrdForBead -BeadId $beadId
    if ($prd) {
        $story = $prd.userStories | Where-Object { $_.id -eq $beadId } | Select-Object -First 1
        if ($story -and $story.passes -eq $true) {
            $isActuallyComplete = $true
            $updatedBead.status = "completed"
            Save-Bead -Bead $updatedBead
        }
    }
}
```

---

### P1 - High Priority Issues

#### 4. Missing Bead Schema Properties
**File:** `ralph-daemon.ps1`

**Problem:** Daemon expected `ralph_meta.last_attempt` and `ralph_meta.status_detail` properties that don't exist in manually created beads.

**Impact:** Error: "The property 'last_attempt' cannot be found on this object"

**Fix:** Added defensive property initialization in `Get-Bead`:
```powershell
# Defensive: Ensure ralph_meta exists with all required properties
if (-not $bead.ralph_meta) {
    $bead | Add-Member -NotePropertyName "ralph_meta" -NotePropertyValue @{} -Force
}

# Ensure required properties exist within ralph_meta
$requiredMetaProps = @('last_attempt', 'status_detail', 'attempt_count', 'timeout_count', 'stuck_count')
foreach ($prop in $requiredMetaProps) {
    if (-not $bead.ralph_meta.PSObject.Properties.Name -contains $prop) {
        $bead.ralph_meta | Add-Member -NotePropertyName $prop -NotePropertyValue $null -Force
    }
}
```

---

#### 5. PRD-to-Bead Synchronization Gap
**File:** `ralph-daemon.ps1`

**Problem:** Ralph (interactive mode) updates `prd.json` `passes` field, but daemon didn't read PRD to verify completion. It relied solely on exit code.

**Fix:** Integrated PRD verification into completion check (see P0 #3 above). Added `Get-PrdForBead` helper function.

---

### P2 - Medium Priority Issues

#### 6. Process Isolation Timeout Handling
**File:** `ralph-daemon.ps1`

**Problem:** `$process.WaitForExit($timeoutMs)` returns `$false` on timeout, but the process object is still referenced in the finally block. Potential race condition where process exits between timeout check and `Stop-Process`.

**Fix:** Added `HasExited` check before attempting to kill:
```powershell
if (-not $completed) {
    # CRITICAL FIX: Check HasExited before attempting to kill
    if ($process -and -not $process.HasExited) {
        try {
            Stop-Process -Id $process.Id -Force -ErrorAction Stop
        }
        catch {
            Write-DaemonLog "Failed to kill process: $_" -Level "WARN"
        }
    }
    # ...
}
```

---

#### 7. Log Directory Creation Race Condition
**File:** `ralph-daemon.ps1`

**Problem:** Multiple simultaneous bead executions could trigger `New-Item` on the same path, causing errors.

**Fix:** Added `-ErrorAction SilentlyContinue`:
```powershell
if (-not (Test-Path $script:LogDir)) {
    New-Item -ItemType Directory -Force -Path $script:LogDir -ErrorAction SilentlyContinue | Out-Null
}
```

---

#### 8. Bead File Corruption on Concurrent Writes
**File:** `ralph-daemon.ps1`

**Problem:** No file locking; simultaneous `Save-Bead` calls could corrupt JSON.

**Fix:** Implemented atomic write pattern (temp file + move):
```powershell
$tempFile = "$beadFile.tmp"
$json = $Bead | ConvertTo-Json -Depth 10
[System.IO.File]::WriteAllText($tempFile, $json, [System.Text.UTF8Encoding]::new($false))
Move-Item $tempFile $beadFile -Force
```

---

### P3 - Lower Priority Issues

#### 9. UTF-8 BOM Inconsistency
**Files:** All scripts

**Problem:** Mix of BOM-aware and BOM-unaware file operations.

**Fix:** Standardized on `"`u{feff}"` syntax everywhere. All JSON read operations now properly handle BOM.

---

#### 10. PowerShell Cross-Platform Compatibility
**File:** `ralph-daemon.ps1`

**Problem:** Hardcoded `pwsh.exe` won't work on Linux/Mac.

**Fix:** Added dynamic PowerShell detection:
```powershell
$script:PwshPath = if ($IsWindows -or ($env:OS -eq "Windows_NT")) {
    # Windows: prefer pwsh.exe (PS 7), fallback to powershell.exe
    $pwsh = Get-Command "pwsh.exe" -ErrorAction SilentlyContinue
    if ($pwsh) { $pwsh.Source } else { "powershell.exe" }
} else {
    # Linux/Mac: use pwsh (PS 7) or fallback to powershell
    $pwsh = Get-Command "pwsh" -ErrorAction SilentlyContinue
    if ($pwsh) { $pwsh.Source } else { "powershell" }
}
```

---

## New Features

### Convert-PrdToBeads Function
**File:** `ralph-core.ps1`

Converts PRD user stories to bead files for daemon processing.

**Usage:**
```powershell
# Import core module
. ./ralph-core.ps1

# Convert all stories to beads
Convert-PrdToBeads

# Force overwrite existing beads
Convert-PrdToBeads -Force
```

**Features:**
- Preserves existing beads (use `-Force` to overwrite)
- Auto-generates verifiers from acceptance criteria
- Sets appropriate defaults for all bead properties
- Uses atomic file writes for safety

---

## Version Updates

All scripts updated to version **2.2.1**:
- `ralph-core.ps1`: 2.1.0 → 2.2.1
- `ralph-daemon.ps1`: 2.1.0 → 2.2.1
- `ralph-health.ps1`: 2.1.0 → 2.2.1
- `ralph.ps1`: 2.2.0 → 2.2.1

---

## Documentation Updates

- **CHANGELOG.md**: Added v2.2.1 section with detailed fix descriptions
- **IMPROVEMENTS.md**: Marked all production stability fixes as complete
- **AGENTS.md**: Updated BOM syntax example to use correct `\u{feff}` format
- **FIXES-v2.2.1.md** (this file): Comprehensive summary of all changes

---

## Testing Recommendations

After upgrading to v2.2.1:

1. **Verify BOM handling:**
   ```powershell
   # Create a BOM file and test reading
   $bytes = [System.Text.Encoding]::UTF8.GetBytes('{"test": true}')
   [System.IO.File]::WriteAllBytes("test-bom.json", [byte[]](0xEF, 0xBB, 0xBF) + $bytes)
   . ./ralph-core.ps1
   $result = Read-RalphJson -Path "test-bom.json"
   ```

2. **Test PRD-to-Bead conversion:**
   ```powershell
   . ./ralph-core.ps1
   $beads = Convert-PrdToBeads
   Write-Host "Created $($beads.Count) beads"
   ```

3. **Verify daemon retry logic:**
   - Create a bead that completes successfully
   - Verify it's marked as `completed` (not `retry`)
   - Check PRD `passes` field is synchronized

4. **Test cross-platform detection:**
   ```powershell
   # Should detect appropriate PowerShell path
   $script:PwshPath
   ```

---

## Backward Compatibility

All changes are backward compatible:
- PRD format unchanged
- Bead format unchanged (new properties are auto-initialized)
- All existing commands work the same way
- No breaking changes to APIs or file formats

---

## Migration from v2.1.0 / v2.2.0

Simply copy the new files:
```powershell
copy ralph.ps1 my-project\
copy ralph-core.ps1 my-project\
copy ralph-daemon.ps1 my-project\
copy ralph-health.ps1 my-project\
```

No other changes required.

---

## Files Modified

| File | Changes |
|------|---------|
| ralph-core.ps1 | BOM syntax, Export-ModuleMember fix, Convert-PrdToBeads added, version bump |
| ralph-daemon.ps1 | BOM syntax, bead property initialization, retry logic fix, PRD sync, atomic writes, cross-platform PS detection, version bump |
| ralph-health.ps1 | BOM syntax, version bump |
| ralph.ps1 | BOM syntax, version bump |
| CHANGELOG.md | Added v2.2.1 release notes |
| IMPROVEMENTS.md | Marked fixes as complete |
| AGENTS.md | Updated BOM syntax example |
| FIXES-v2.2.1.md | Created (this file) |

---

## Credits

These fixes were identified through comprehensive independent agent testing. Special thanks to the agents who provided detailed technical analysis and reproduction steps.
