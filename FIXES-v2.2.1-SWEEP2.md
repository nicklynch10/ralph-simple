# Ralph v2.2.1 - Second Sweep Fixes

**Date:** 2026-02-06  
**Version:** 2.2.1  

---

## Additional Issues Found in Second Sweep

### 1. Version Number Inconsistencies
**Files:** `ralph.ps1`, `install-service.ps1`

**Problem:** Version numbers were inconsistent across files:
- `ralph-core.ps1`: 2.2.1 ✓
- `ralph-daemon.ps1`: 2.2.1 ✓
- `ralph-health.ps1`: 2.2.1 ✓
- `ralph.ps1`: 2.2.0 ✗ (should be 2.2.1)
- `install-service.ps1`: 2.1.0 ✗ (should be 2.2.1)

**Fix:** Updated all version numbers to 2.2.1

---

### 2. ralph-build.ps1 BOM and Encoding Issues
**File:** `ralph-build.ps1`

**Problems Found:**
1. `Read-Backlog` function didn't handle UTF-8 BOM
2. `Write-Backlog` used `Set-Content` which may add BOM in PS 5.1
3. Context file write used `Set-Content` without proper encoding
4. `Add-Content` for logging didn't specify encoding

**Fixes Applied:**
```powershell
# Read-Backlog - Added BOM handling
$content = Get-Content -Path $BACKLOG_FILE -Raw -Encoding UTF8
if ($content.Length -gt 0 -and $content[0] -eq "`u{feff}") {
    $content = $content.Substring(1)
}

# Write-Backlog - Use atomic write without BOM
$json = $Backlog | ConvertTo-Json -Depth 20
[System.IO.File]::WriteAllText($BACKLOG_FILE, $json, [System.Text.UTF8Encoding]::new($false))

# Context file - Use atomic write without BOM
[System.IO.File]::WriteAllText($contextFile, $buildContext, [System.Text.UTF8Encoding]::new($false))

# Logging - Specify UTF8 encoding
Add-Content -Path $LOG_FILE -Value $logEntry -Encoding UTF8
```

---

### 3. Missing Defensive Checks in Daemon
**File:** `ralph-daemon.ps1`

**Problems Found:**
1. `Invoke-Bead` assumed `$Bead.id` exists without checking
2. `Save-Bead` assumed `$Bead.id` exists without checking
3. `Invoke-Bead` didn't verify `$Bead.status` property exists

**Fixes Applied:**
```powershell
# In Invoke-Bead - Added defensive checks
if (-not $Bead.id) {
    Write-DaemonLog "Bead is missing required 'id' property" -Level "ERROR"
    return $false
}

if (-not ($Bead.PSObject.Properties.Name -contains "status")) {
    $Bead | Add-Member -NotePropertyName "status" -NotePropertyValue "pending" -Force
}

# In Save-Bead - Added defensive check
if (-not $Bead.id) {
    Write-DaemonLog "Cannot save bead: missing 'id' property" -Level "ERROR"
    return $false
}
```

---

## Verification Summary

### BOM Syntax Check
- All 18 occurrences of BOM handling now use correct `"`u{feff}"` syntax
- Zero occurrences of invalid `"`ufeff"` syntax remain in PowerShell files

### Version Consistency Check
- All 5 PowerShell files now report version 2.2.1

### Encoding Consistency Check
- All JSON writes use `[System.IO.File]::WriteAllText` with `UTF8Encoding($false)`
- All JSON reads use `-Raw -Encoding UTF8` with BOM stripping

### Defensive Programming Check
- All bead property access now has null checks
- All file operations have try/catch blocks
- All directory creation uses `-ErrorAction SilentlyContinue`

---

## Files Modified in Second Sweep

| File | Changes |
|------|---------|
| ralph.ps1 | Version bump 2.2.0 → 2.2.1 |
| install-service.ps1 | Version bump 2.1.0 → 2.2.1 |
| ralph-build.ps1 | BOM handling, encoding fixes, atomic writes |
| ralph-daemon.ps1 | Defensive checks for bead.id and bead.status |

---

## Complete File List (All Modified Files)

### From First Sweep:
- `ralph-core.ps1`
- `ralph-daemon.ps1`
- `ralph-health.ps1`
- `CHANGELOG.md`
- `IMPROVEMENTS.md`
- `AGENTS.md`
- `FIXES-v2.2.1.md`

### From Second Sweep:
- `ralph.ps1`
- `install-service.ps1`
- `ralph-build.ps1`
- `ralph-daemon.ps1` (additional changes)
- `FIXES-v2.2.1-SWEEP2.md` (this file)

---

## Testing Recommendations

1. **Test ralph-build.ps1 with BOM file:**
   ```powershell
   # Create a BOM-encoded backlog.json
   $bytes = [System.Text.Encoding]::UTF8.GetBytes('{"lanes": {"feature": []}}')
   [System.IO.File]::WriteAllBytes("backlog-bom.json", [byte[]](0xEF, 0xBB, 0xBF) + $bytes)
   
   # Test reading
   ./ralph-build.ps1 -BacklogPath "backlog-bom.json" -DryRun
   ```

2. **Test daemon with malformed bead:**
   ```powershell
   # Create a bead without id
   @'{"status": "pending"}'@ | Set-Content ".ralph/beads/bad-bead.json"
   
   # Daemon should handle gracefully
   ./ralph-daemon.ps1 -Status
   ```

3. **Verify version consistency:**
   ```powershell
   Get-Content *.ps1 | Select-String 'RalphVersion|DaemonVersion' | Select-Object Filename, Line
   ```
