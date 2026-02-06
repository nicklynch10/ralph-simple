#!/bin/bash
# Ralph for Kimi Code CLI - Autonomous AI agent loop
# Usage: ./ralph.sh [max_iterations] [--daemon] [--health] [--status] [--help]
#
# Examples:
#   ./ralph.sh                    # Run 10 iterations (default)
#   ./ralph.sh 20                 # Run 20 iterations
#   ./ralph.sh --daemon           # Start production daemon
#   ./ralph.sh --health           # Run health check
#   ./ralph.sh --status           # Show daemon status
#
# Based on the Ralph pattern by Geoffrey Huntley
# Adapted for Kimi Code CLI with production-grade reliability
#
# Version: 2.1.0
# Linux/Mac Version (PowerShell not required on Linux/Mac)

set -e

# ==============================================================================
# CONFIGURATION
# ==============================================================================

RALPH_VERSION="2.1.0"
DEFAULT_MAX_ITERATIONS=10

# ==============================================================================
# PATHS
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRD_FILE="$SCRIPT_DIR/prd.json"
PROGRESS_FILE="$SCRIPT_DIR/progress.txt"
ARCHIVE_DIR="$SCRIPT_DIR/archive"
LAST_BRANCH_FILE="$SCRIPT_DIR/.last-branch"
PROMPT_FILE="$SCRIPT_DIR/KIMI.md"
LOG_DIR="$SCRIPT_DIR/.ralph/logs"
BEADS_DIR="$SCRIPT_DIR/.ralph/beads"
PID_FILE="$SCRIPT_DIR/.ralph/daemon.pid"

# ==============================================================================
# LOGGING
# ==============================================================================

log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[$timestamp] [$level] $message"
    
    # Also write to log file
    mkdir -p "$LOG_DIR" 2>/dev/null || true
    echo "[$timestamp] [$level] $message" >> "$LOG_DIR/ralph-$(date '+%Y%m%d').log" 2>/dev/null || true
}

log_info() { log "INFO" "$1"; }
log_warn() { log "WARN" "$1"; }
log_error() { log "ERROR" "$1"; }
log_success() { log "SUCCESS" "$1"; }

# ==============================================================================
# JSON HANDLING (UTF-8 BOM Safe)
# ==============================================================================

read_json() {
    local file="$1"
    
    if [[ ! -f "$file" ]]; then
        echo "null"
        return
    fi
    
    # Use sed to remove BOM if present, then parse with jq
    sed 's/^\xEF\xBB\xBF//' "$file" | jq . 2>/dev/null || echo "null"
}

get_json_value() {
    local json="$1"
    local key="$2"
    
    echo "$json" | jq -r "$key // empty" 2>/dev/null
}

# ==============================================================================
# HELP
# ==============================================================================

show_help() {
    cat << 'EOF'
Ralph for Kimi Code CLI - Autonomous AI Agent Loop

USAGE:
    ./ralph.sh [options] [max_iterations]

COMMANDS:
    (no args)           Run Ralph loop with default 10 iterations
    <number>            Run Ralph loop with specified iterations
    --daemon            Start production daemon for 24/7 operation
    --health            Run health check and diagnostics
    --status            Show daemon and bead status
    --install-service   Install daemon as systemd service (Linux)
    --uninstall-service Remove daemon systemd service
    --reset-stuck       Reset beads stuck for >2 hours
    --help              Show this help message

EXAMPLES:
    # Run 10 iterations (default)
    ./ralph.sh

    # Run 20 iterations
    ./ralph.sh 20

    # Start production daemon
    ./ralph.sh --daemon

    # Check system health
    ./ralph.sh --health

FILES:
    prd.json            Product requirements (user stories)
    KIMI.md             Agent instructions
    progress.txt        Execution log
    .ralph/             Ralph configuration directory
    .ralph/logs/        Log files
    .ralph/beads/       Bead files (daemon mode)

For more information, see README.md
EOF
}

# ==============================================================================
# STATUS DISPLAY
# ==============================================================================

show_status() {
    if [[ ! -f "$PRD_FILE" ]]; then
        log_warn "PRD file not found"
        return
    fi
    
    local prd=$(read_json "$PRD_FILE")
    
    if [[ "$prd" == "null" ]]; then
        log_error "Could not parse PRD file"
        return
    fi
    
    echo ""
    echo "Current PRD Status:"
    echo "==================="
    
    # Count stories
    local total=$(echo "$prd" | jq '.userStories | length')
    local completed=$(echo "$prd" | jq '[.userStories[] | select(.passes == true)] | length')
    
    # Display each story
    echo "$prd" | jq -r '.userStories[] | 
        if .passes == true then 
            "[✓ PASS] \(.id): \(.title)" 
        else 
            "[○ PENDING] \(.id): \(.title)" 
        end'
    
    echo ""
    echo "Progress: $completed / $total stories complete"
}

# ==============================================================================
# DAEMON FUNCTIONS
# ==============================================================================

daemon_is_running() {
    if [[ -f "$PID_FILE" ]]; then
        local pid=$(cat "$PID_FILE" 2>/dev/null)
        if kill -0 "$pid" 2>/dev/null; then
            return 0
        fi
    fi
    return 1
}

daemon_start() {
    log_info "Starting Ralph Daemon v$RALPH_VERSION"
    
    if daemon_is_running; then
        log_warn "Daemon is already running (PID: $(cat $PID_FILE))"
        return 1
    fi
    
    # Create necessary directories
    mkdir -p "$LOG_DIR" "$BEADS_DIR"
    
    # Start daemon in background
    (
        echo $$ > "$PID_FILE"
        exec > >(tee -a "$LOG_DIR/ralph-daemon.log")
        exec 2>&1
        
        log_info "Daemon started (PID: $$)"
        log_info "Workspace: $SCRIPT_DIR"
        log_info "Poll interval: 30s"
        log_info "Bead timeout: 120m"
        
        # Main daemon loop
        while true; do
            # Reset stuck beads
            reset_stuck_beads
            
            # Process pending beads
            process_pending_beads
            
            # Sleep before next poll
            sleep 30
        done
    ) &
    
    log_success "Daemon started (PID: $!)"
}

daemon_stop() {
    if [[ -f "$PID_FILE" ]]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            log_info "Stopping daemon (PID: $pid)"
            kill "$pid" 2>/dev/null || true
            rm -f "$PID_FILE"
            log_success "Daemon stopped"
        else
            log_warn "Daemon not running (stale PID file)"
            rm -f "$PID_FILE"
        fi
    else
        log_warn "Daemon not running"
    fi
}

daemon_status() {
    echo ""
    echo "Ralph Daemon Status"
    echo "==================="
    echo ""
    
    if daemon_is_running; then
        echo "Status: RUNNING (PID: $(cat $PID_FILE))"
    else
        echo "Status: STOPPED"
    fi
    
    echo "Workspace: $SCRIPT_DIR"
    echo ""
    
    # Show bead status
    show_bead_status
    
    # Show recent logs
    echo ""
    echo "Recent Log Entries:"
    if [[ -f "$LOG_DIR/ralph-daemon.log" ]]; then
        tail -10 "$LOG_DIR/ralph-daemon.log" 2>/dev/null || echo "  (no log entries)"
    else
        echo "  (no log file)"
    fi
}

# ==============================================================================
# BEAD MANAGEMENT
# ==============================================================================

show_bead_status() {
    if [[ ! -d "$BEADS_DIR" ]]; then
        echo "Pending Beads: 0"
        return
    fi
    
    local total=0
    local pending=0
    local in_progress=0
    local completed=0
    local failed=0
    local stuck=0
    
    for bead_file in "$BEADS_DIR"/*.json; do
        [[ -f "$bead_file" ]] || continue
        
        local bead=$(read_json "$bead_file")
        [[ "$bead" == "null" ]] && continue
        
        total=$((total + 1))
        
        local status=$(echo "$bead" | jq -r '.status // "pending"')
        
        case "$status" in
            pending|retry)
                pending=$((pending + 1))
                ;;
            in_progress)
                in_progress=$((in_progress + 1))
                
                # Check if stuck
                local last_attempt=$(echo "$bead" | jq -r '.ralph_meta.last_attempt // empty')
                if [[ -n "$last_attempt" ]]; then
                    local last_epoch=$(date -d "$last_attempt" +%s 2>/dev/null || echo 0)
                    local now_epoch=$(date +%s)
                    local hours_since=$(( (now_epoch - last_epoch) / 3600 ))
                    
                    if [[ $hours_since -gt 2 ]]; then
                        stuck=$((stuck + 1))
                    fi
                fi
                ;;
            completed)
                completed=$((completed + 1))
                ;;
            failed)
                failed=$((failed + 1))
                ;;
        esac
    done
    
    echo "Bead Status:"
    echo "  Total: $total"
    echo "  Pending: $pending"
    echo "  In Progress: $in_progress"
    echo "  Completed: $completed"
    echo "  Failed: $failed"
    [[ $stuck -gt 0 ]] && echo "  Stuck (>2h): $stuck"
}

reset_stuck_beads() {
    if [[ ! -d "$BEADS_DIR" ]]; then
        return 0
    fi
    
    local reset_count=0
    
    for bead_file in "$BEADS_DIR"/*.json; do
        [[ -f "$bead_file" ]] || continue
        
        local bead=$(read_json "$bead_file")
        [[ "$bead" == "null" ]] && continue
        
        local status=$(echo "$bead" | jq -r '.status // empty')
        local last_attempt=$(echo "$bead" | jq -r '.ralph_meta.last_attempt // empty')
        
        if [[ "$status" == "in_progress" && -n "$last_attempt" ]]; then
            local last_epoch=$(date -d "$last_attempt" +%s 2>/dev/null || echo 0)
            local now_epoch=$(date +%s)
            local hours_since=$(( (now_epoch - last_epoch) / 3600 ))
            
            if [[ $hours_since -gt 2 ]]; then
                local bead_id=$(echo "$bead" | jq -r '.id')
                log_warn "Resetting stuck bead: $bead_id (${hours_since}h old)"
                
                # Update bead status
                local updated=$(echo "$bead" | jq \
                    --arg reason "Stuck for ${hours_since} hours" \
                    --arg reset_at "$(date -Iseconds)" \
                    '.status = "retry" | 
                     .ralph_meta.stuck_count = ((.ralph_meta.stuck_count // 0) + 1) |
                     .ralph_meta.reset_reason = $reason |
                     .ralph_meta.reset_at = $reset_at')
                
                echo "$updated" > "$bead_file"
                reset_count=$((reset_count + 1))
            fi
        fi
    done
    
    return $reset_count
}

process_pending_beads() {
    if [[ ! -d "$BEADS_DIR" ]]; then
        return 0
    fi
    
    for bead_file in "$BEADS_DIR"/*.json; do
        [[ -f "$bead_file" ]] || continue
        
        local bead=$(read_json "$bead_file")
        [[ "$bead" == "null" ]] && continue
        
        local status=$(echo "$bead" | jq -r '.status // empty')
        
        if [[ "$status" == "pending" || "$status" == "retry" ]]; then
            local bead_id=$(echo "$bead" | jq -r '.id')
            log_info "Processing bead: $bead_id"
            
            # Update status to in_progress
            local updated=$(echo "$bead" | jq \
                --arg attempt_at "$(date -Iseconds)" \
                '.status = "in_progress" |
                 .ralph_meta.last_attempt = $attempt_at |
                 .ralph_meta.attempt_count = ((.ralph_meta.attempt_count // 0) + 1)')
            
            echo "$updated" > "$bead_file"
            
            # Execute the bead (run ralph once)
            local output_log="$LOG_DIR/bead-$bead_id-$(date '+%Y%m%d-%H%M%S').log"
            
            timeout 120m bash -c "
                cd '$SCRIPT_DIR'
                '$SCRIPT_DIR/ralph.sh' 1
            " > "$output_log" 2>&1 || true
            
            # Re-read bead to check if completed
            bead=$(read_json "$bead_file")
            local new_status=$(echo "$bead" | jq -r '.status // empty')
            
            if [[ "$new_status" == "completed" ]]; then
                log_success "Bead $bead_id completed"
            else
                log_warn "Bead $bead_id did not complete (status: $new_status)"
            fi
            
            # Small delay between beads
            sleep 2
        fi
    done
}

# ==============================================================================
# HEALTH CHECK
# ==============================================================================

health_check() {
    echo ""
    echo "Ralph Health Check v$RALPH_VERSION"
    echo "======================================"
    echo "Workspace: $SCRIPT_DIR"
    echo ""
    
    local issues=0
    
    # Check prerequisites
    echo "Prerequisites:"
    
    if command -v kimi &> /dev/null; then
        local kimi_version=$(kimi --version 2>&1 | head -1)
        echo "  Kimi CLI: OK ($kimi_version)"
    else
        echo "  Kimi CLI: NOT FOUND - Install from https://github.com/moonshotai/kimi-cli"
        issues=$((issues + 1))
    fi
    
    if command -v git &> /dev/null; then
        local git_version=$(git --version)
        echo "  Git: OK ($git_version)"
    else
        echo "  Git: NOT FOUND"
        issues=$((issues + 1))
    fi
    
    if command -v jq &> /dev/null; then
        echo "  jq: OK"
    else
        echo "  jq: NOT FOUND - Install with: apt-get install jq (or equivalent)"
        issues=$((issues + 1))
    fi
    
    # Check configuration
    echo ""
    echo "Configuration:"
    
    if [[ -f "$PRD_FILE" ]]; then
        local prd=$(read_json "$PRD_FILE")
        if [[ "$prd" != "null" ]]; then
            local story_count=$(echo "$prd" | jq '.userStories | length')
            local completed_count=$(echo "$prd" | jq '[.userStories[] | select(.passes == true)] | length')
            echo "  PRD File: OK ($completed_count/$story_count stories)"
        else
            echo "  PRD File: ERROR - Invalid JSON"
            issues=$((issues + 1))
        fi
    else
        echo "  PRD File: NOT FOUND"
        issues=$((issues + 1))
    fi
    
    if [[ -f "$PROMPT_FILE" ]]; then
        local size=$(stat -f%z "$PROMPT_FILE" 2>/dev/null || stat -c%s "$PROMPT_FILE" 2>/dev/null || echo "0")
        echo "  Prompt File: OK ($size bytes)"
    else
        echo "  Prompt File: NOT FOUND"
        issues=$((issues + 1))
    fi
    
    # Check daemon status
    echo ""
    echo "Daemon Status:"
    
    if daemon_is_running; then
        echo "  Process: RUNNING (PID: $(cat $PID_FILE))"
    else
        echo "  Process: STOPPED"
    fi
    
    # Check beads
    echo ""
    show_bead_status
    
    # Summary
    echo ""
    if [[ $issues -eq 0 ]]; then
        echo "Overall Status: HEALTHY"
    else
        echo "Overall Status: $issues issue(s) found"
    fi
    echo ""
}

# ==============================================================================
# MAIN
# ==============================================================================

# Parse arguments
MAX_ITERATIONS=$DEFAULT_MAX_ITERATIONS
DAEMON_MODE=false
HEALTH_MODE=false
STATUS_MODE=false
RESET_STUCK=false

for arg in "$@"; do
    case "$arg" in
        --daemon)
            DAEMON_MODE=true
            ;;
        --health)
            HEALTH_MODE=true
            ;;
        --status)
            STATUS_MODE=true
            ;;
        --reset-stuck)
            RESET_STUCK=true
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        [0-9]*)
            MAX_ITERATIONS=$arg
            ;;
    esac
done

# Dispatch to appropriate mode
if [[ "$HEALTH_MODE" == true ]]; then
    health_check
    exit 0
fi

if [[ "$STATUS_MODE" == true ]]; then
    daemon_status
    exit 0
fi

if [[ "$RESET_STUCK" == true ]]; then
    reset_stuck_beads
    exit 0
fi

if [[ "$DAEMON_MODE" == true ]]; then
    daemon_start
    exit 0
fi

# ==============================================================================
# MAIN RALPH LOOP
# ==============================================================================

log_info "Ralph for Kimi Code CLI v$RALPH_VERSION"
log_info "Max iterations: $MAX_ITERATIONS"

# Check prerequisites
if ! command -v kimi &> /dev/null; then
    log_error "Kimi CLI not found. Please install Kimi Code CLI first."
    log_error "Visit: https://github.com/moonshotai/kimi-cli"
    exit 1
fi

if ! command -v git &> /dev/null; then
    log_error "Git not found. Please install git."
    exit 1
fi

if [[ ! -f "$PRD_FILE" ]]; then
    log_error "PRD file not found at $PRD_FILE"
    log_error "Please create a prd.json file or use the PRD skill to generate one."
    exit 1
fi

# Archive previous run if branch changed
if [[ -f "$PRD_FILE" && -f "$LAST_BRANCH_FILE" ]]; then
    CURRENT_BRANCH=$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null || echo "")
    LAST_BRANCH=$(cat "$LAST_BRANCH_FILE" 2>/dev/null || echo "")
    
    if [[ -n "$CURRENT_BRANCH" && -n "$LAST_BRANCH" && "$CURRENT_BRANCH" != "$LAST_BRANCH" ]]; then
        DATE=$(date +%Y-%m-%d)
        FOLDER_NAME=$(echo "$LAST_BRANCH" | sed 's|^ralph/||')
        ARCHIVE_FOLDER="$ARCHIVE_DIR/$DATE-$FOLDER_NAME"
        
        log_info "Archiving previous run: $LAST_BRANCH"
        mkdir -p "$ARCHIVE_FOLDER"
        cp "$PRD_FILE" "$ARCHIVE_FOLDER/" 2>/dev/null || true
        cp "$PROGRESS_FILE" "$ARCHIVE_FOLDER/" 2>/dev/null || true
        log_success "Archived to: $ARCHIVE_FOLDER"
        
        # Reset progress file
        echo "# Ralph Progress Log" > "$PROGRESS_FILE"
        echo "Started: $(date)" >> "$PROGRESS_FILE"
        echo "---" >> "$PROGRESS_FILE"
    fi
fi

# Track current branch
if [[ -f "$PRD_FILE" ]]; then
    CURRENT_BRANCH=$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null || echo "")
    if [[ -n "$CURRENT_BRANCH" ]]; then
        echo "$CURRENT_BRANCH" > "$LAST_BRANCH_FILE"
    fi
fi

# Initialize progress file
if [[ ! -f "$PROGRESS_FILE" ]]; then
    echo "# Ralph Progress Log" > "$PROGRESS_FILE"
    echo "Started: $(date)" >> "$PROGRESS_FILE"
    echo "---" >> "$PROGRESS_FILE"
fi

# Show status
show_status

# Set up trap for Ctrl+C
cleanup() {
    log_warn "Interrupted by user (Ctrl+C)"
    exit 130
}
trap cleanup INT TERM

# Main loop
COMPLETED_ITERATIONS=0

for ((i=1; i<=MAX_ITERATIONS; i++)); do
    echo ""
    echo "==============================================================="
    echo "  Ralph Iteration $i of $MAX_ITERATIONS"
    echo "==============================================================="
    echo ""
    
    log_info "Starting iteration $i"
    
    OUTPUT=""
    
    # Run Kimi with the Ralph prompt
    if OUTPUT=$(cat "$PROMPT_FILE" | kimi --print --final-message-only 2>&1); then
        echo "$OUTPUT"
    else
        # Don't let errors stop the loop
        log_warn "Iteration $i encountered an error"
        echo "$OUTPUT"
    fi
    
    COMPLETED_ITERATIONS=$((COMPLETED_ITERATIONS + 1))
    
    # Check for completion signal
    if echo "$OUTPUT" | grep -q "<promise>COMPLETE</promise>"; then
        echo ""
        echo "==============================================================="
        echo "  RALPH COMPLETED ALL TASKS!"
        echo "==============================================================="
        echo ""
        log_success "Completed at iteration $i of $MAX_ITERATIONS"
        show_status
        exit 0
    fi
    
    # Also check if all stories are complete
    prd=$(read_json "$PRD_FILE")
    if [[ "$prd" != "null" ]]; then
        incomplete=$(echo "$prd" | jq '[.userStories[] | select(.passes != true)] | length')
        if [[ "$incomplete" == "0" ]]; then
            echo ""
            echo "==============================================================="
            echo "  ALL STORIES COMPLETE!"
            echo "==============================================================="
            echo ""
            log_success "All stories marked complete at iteration $i"
            exit 0
        fi
    fi
    
    log_info "Iteration $i complete. Checking for more work..."
    show_status
    
    # Delay between iterations
    if [[ $i -lt $MAX_ITERATIONS ]]; then
        sleep 2
    fi
done

echo ""
echo "==============================================================="
echo "  RALPH REACHED MAX ITERATIONS"
echo "==============================================================="
echo ""
log_warn "Max iterations ($MAX_ITERATIONS) reached without completion"
echo "Check $PROGRESS_FILE for status."
echo ""

show_status

exit 1
