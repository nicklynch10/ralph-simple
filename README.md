# Ralph for Kimi Code CLI - Test-Driven Edition

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Ralph is an autonomous AI agent loop that runs [Kimi Code CLI](https://github.com/moonshotai/kimi-cli) repeatedly until all PRD (Product Requirements Document) items are complete. **Now with built-in test-driven development and browser automation support.**

This is a port of the original [Ralph](https://github.com/snarktank/ralph) project (built for Amp and Claude Code) to work with Kimi Code CLI.

Based on the [Ralph pattern](https://ghuntley.com/ralph) by Geoffrey Huntley.

---

## What's New: Test-Driven Ralph

This enhanced version includes:

- **🧪 Test-First Development** - Generate tests from PRDs before implementation
- **🎭 Playwright MCP Integration** - Automated browser testing for UI stories
- **📊 Test Plan Management** - Track test coverage with `test-plan.json`
- **🖼️ Screenshot Verification** - Visual proof of UI changes
- **⚡ Context-Aware Testing** - Smart batching to manage context usage
- **📈 Coverage Tracking** - Know what's tested and what's not

---

## Table of Contents

- [How It Works](#how-it-works)
- [The Test-Driven Flow](#the-test-driven-flow)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Testing Strategy](#testing-strategy)
- [Context Management](#context-management)
- [Troubleshooting](#troubleshooting)

---

## How It Works

```
┌─────────────────────────────────────────────────────────────────────┐
│                      Ralph Test-Driven Loop                          │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌─────────┐    ┌─────────────┐    ┌──────────┐    ┌─────────────┐ │
│  │  PRD    │───→│ Test Plan   │───→│  Tests   │───→│ Implementation│
│  │ (JSON)  │    │  (JSON)     │    │(Generate)│    │             │
│  └─────────┘    └─────────────┘    └──────────┘    └─────────────┘ │
│       │                                                    │        │
│       │    ┌──────────┐    ┌──────────┐    ┌──────────┐   │        │
│       └───→│  Git     │←───│ Browser  │←───│  Verify  │←──┘        │
│            │(Memory)  │    │  (MCP)   │    │  Tests   │            │
│            └──────────┘    └──────────┘    └──────────┘            │
│                                                                      │
│  Memory: git history + prd.json + test-plan.json + progress.txt     │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Key Differences from Original Ralph

| Feature | Original Ralph | Test-Driven Ralph |
|---------|---------------|-------------------|
| Testing | Manual verification | Automated + Browser |
| Test Generation | None | Generate from PRD |
| Browser Testing | Optional skill | Integrated workflow |
| Test Tracking | None | test-plan.json |
| Context Management | N/A | Smart batching |

---

## The Test-Driven Flow

### 1. PRD Creation (with Test Planning)

```bash
kimi
/skill:prd
```

Creates PRD with testable acceptance criteria.

### 2. Convert to Ralph Format

```bash
/skill:ralph
```

Creates `prd.json` with test metadata.

### 3. Generate Test Suite

```bash
/skill:test-generation
```

Creates:
- `test-plan.json` - Test coverage tracking
- Unit/Integration/E2E test files
- Browser test specifications
- Data-testid attributes in components

### 4. Run Ralph Loop

```powershell
.\scripts\ralph\ralph.ps1
```

Each iteration:
1. **Pre-flight**: Run tests (they should fail - TDD)
2. **Implement**: Code the story
3. **Verify**: Run tests (they should pass)
4. **Browser Test**: If UI story, verify with Playwright MCP
5. **Commit**: Only if all tests pass
6. **Document**: Update progress with test results

---

## Prerequisites

- [Kimi Code CLI](https://github.com/moonshotai/kimi-cli) installed and authenticated
- Git repository for your project
- PowerShell (Windows) or Bash (Linux/macOS)
- **Playwright MCP** (optional but recommended for browser testing)

### Installing Playwright MCP

```bash
# Add Playwright MCP to Kimi
kimi mcp add --transport http playwright http://localhost:3000/mcp

# Or use the chrome-devtools MCP
kimi mcp add --transport stdio chrome-devtools -- npx chrome-devtools-mcp@latest
```

---

## Quick Start

### 1. Install Ralph in Your Project

```powershell
# Create the ralph directory
mkdir -p scripts/ralph

# Download the files
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/nicklynch10/ralph-kimi/main/ralph.ps1" -OutFile "scripts/ralph/ralph.ps1"
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/nicklynch10/ralph-kimi/main/KIMI.md" -OutFile "scripts/ralph/KIMI.md"
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/nicklynch10/ralph-kimi/main/test-plan.json.example" -OutFile "scripts/ralph/test-plan.json.example"
```

### 2. Install Skills

```powershell
# Create skills directory
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.kimi\skills"

# Download skills
# (Copy skills/prd, skills/ralph, skills/browser-testing, skills/test-generation)
```

### 3. Create PRD with Test Planning

```bash
kimi
/skill:prd
```

The PRD skill now includes test planning in the acceptance criteria.

### 4. Generate Tests

```bash
/skill:test-generation
```

This creates your test suite and `test-plan.json`.

### 5. Run Ralph

```powershell
.\scripts\ralph\ralph.ps1
```

Watch as it:
- Runs tests first (TDD)
- Implements stories
- Verifies with browser automation
- Commits only when all tests pass

---

## Testing Strategy

### Three Levels of Testing

```
┌────────────────────────────────────────────────────────────┐
│                    Testing Pyramid                         │
├────────────────────────────────────────────────────────────┤
│                                                            │
│     🎭 E2E / Browser Tests (Few, Expensive)               │
│         - Full user flows                                 │
│         - Playwright MCP                                  │
│         - ~30-60s per test                                │
│                      ▲                                     │
│     🔗 Integration Tests (Some)                           │
│         - API + Database                                  │
│         - Component + Backend                             │
│         - ~5-10s per test                                 │
│                      ▲                                     │
│     ⚡ Unit Tests (Many, Fast)                            │
│         - Pure functions                                  │
│         - Business logic                                  │
│         - ~10-100ms per test                              │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

### Test Types by Story

| Story Type | Unit | Integration | E2E | Browser | Context Cost |
|------------|------|-------------|-----|---------|--------------|
| Database/Schema | ✅ | ✅ | ❌ | ❌ | Low |
| API Endpoint | ✅ | ✅ | ❌ | ❌ | Low |
| UI Component | ✅ | ❌ | ✅ | Screenshot | Medium |
| Form/Input | ✅ | ✅ | ✅ | Interaction | High |
| Full Feature | ✅ | ✅ | ✅ | Full E2E | Very High |

### Browser Testing Intensity

Choose the right level to manage context:

#### 🖼️ Screenshot Only (Fast, ~10% context)
```yaml
Use for: Visual verification, simple UI additions
Steps:
  - Navigate to page
  - Take screenshot
  - Verify element visible
Time: ~10-15 seconds
```

#### 🖱️ Interaction Test (Medium, ~25% context)
```yaml
Use for: Forms, buttons, user interactions
Steps:
  - Navigate to page
  - Take "before" screenshot
  - Click/type/interact
  - Take "after" screenshot
  - Verify change
Time: ~20-30 seconds
```

#### 🎬 Full E2E Flow (Comprehensive, ~50% context)
```yaml
Use for: Complete user journeys
Steps:
  - Navigate to entry
  - Progress through flow
  - Multiple interactions
  - Screenshots at key points
  - Verify final state
Time: ~40-60 seconds
```

---

## Context Management

**Browser testing is powerful but context-expensive.** Here's how to use it effectively:

### Strategy 1: Test Batching

Instead of testing each story separately, batch related UI stories:

```
❌ Expensive (separate browser tests):
   Story 1: Add button → Browser test → Commit
   Story 2: Add form → Browser test → Commit
   Story 3: Connect → Browser test → Commit

✅ Efficient (batched browser test):
   Story 1: Add button → Implement
   Story 2: Add form → Implement
   Story 3: Connect → Implement
   → Batch browser test all three → Commit
```

Configure in `test-plan.json`:
```json
{
  "batchTests": [{
    "stories": ["US-002", "US-003", "US-004"],
    "reason": "Related UI features"
  }]
}
```

### Strategy 2: Context Threshold

When context runs high, adjust testing:

```
Context < 50%: Full browser testing
Context 50-70%: Screenshot only
Context > 70%: Skip browser, rely on automated tests
```

Ralph monitors context and adjusts automatically.

### Strategy 3: Selective Browser Testing

Not every UI change needs a browser test:

| Change Type | Browser Test | Why |
|-------------|--------------|-----|
| Color change | ❌ Skip | CSS only, trust the code |
| Font size | ❌ Skip | Visual but low risk |
| New button | 🖼️ Screenshot | Verify visibility |
| New form | 🖱️ Interaction | Verify functionality |
| New workflow | 🎬 Full E2E | Verify complete flow |

### Strategy 4: Screenshot as Proof

When you do browser test, always screenshot:

```
1. Navigate to page
2. Take screenshot: tests/screenshots/US-XXX-start.png
3. [Interact if needed]
4. Take screenshot: tests/screenshots/US-XXX-end.png
5. Document in progress.txt
```

Screenshots serve as:
- Proof of verification
- Documentation for future developers
- Regression test baseline (if using visual regression)

---

## File Structure

```
scripts/ralph/
├── ralph.ps1              # Main orchestration script
├── ralph.sh               # Linux/Mac version
├── KIMI.md                # Agent instructions (test-driven)
├── prd.json               # Your stories (generated)
├── test-plan.json         # Test coverage tracking (generated)
├── progress.txt           # Learnings log
└── archive/               # Old runs

Your Project/
├── tests/
│   ├── unit/              # Unit tests (generated)
│   ├── integration/       # Integration tests (generated)
│   ├── components/        # Component tests (generated)
│   └── screenshots/       # Browser test evidence
├── e2e/
│   └── *.spec.ts          # Playwright tests (generated)
├── tasks/
│   └── prd-*.md           # PRD documents
└── src/
    └── components/        # Components with data-testid
```

---

## Test Plan Format

The `test-plan.json` tracks test coverage:

```json
{
  "project": "MyApp",
  "stories": [
    {
      "storyId": "US-002",
      "title": "Display priority badge",
      "testTypes": ["component", "e2e"],
      "testFiles": [
        "tests/components/PriorityBadge.test.tsx",
        "e2e/us-002-priority-badge.spec.ts"
      ],
      "browserTest": {
        "required": true,
        "type": "screenshot",
        "selectors": {
          "badge": "[data-testid='priority-badge']"
        }
      },
      "status": "pending",
      "coverage": {
        "unit": false,
        "integration": false,
        "e2e": false
      }
    }
  ]
}
```

---

## Example Workflow

### Story: Add Priority Badge to Tasks

**1. PRD Created:**
```json
{
  "id": "US-002",
  "acceptanceCriteria": [
    "Badge shows colored priority (red/yellow/gray)",
    "Typecheck passes",
    "Component tests pass",
    "Screenshot verification in browser"
  ]
}
```

**2. Tests Generated:**
```typescript
// tests/components/PriorityBadge.test.tsx
describe('PriorityBadge', () => {
  it.each([
    ['high', 'bg-red-500'],
    ['medium', 'bg-yellow-500'],
    ['low', 'bg-gray-500'],
  ])('renders %s priority correctly', (priority, expectedClass) => {
    render(<PriorityBadge priority={priority} />);
    expect(screen.getByTestId('priority-badge')).toHaveClass(expectedClass);
  });
});
```

**3. Ralph Iteration:**
```
[Iteration 1]
- Run tests: FAIL (TDD - expected)
- Implement PriorityBadge component
- Add data-testid="priority-badge"
- Run tests: PASS
- Browser test (screenshot):
  - Navigate to /tasks
  - Screenshot: tests/screenshots/US-002.png
  - Verify badge visible
- Commit: "feat: US-002 - Display priority badge"
- Update prd.json: passes: true
```

**4. Progress Logged:**
```markdown
## 2025-02-02 14:30 - US-002
- Implemented PriorityBadge component with color variants
- Files: components/PriorityBadge.tsx, components/PriorityBadge.test.tsx

### Testing
**Automated:**
- Component tests: PASS (3 variants tested)
- Pre-implementation: FAIL (TDD)
- Post-implementation: PASS

**Browser:**
- Type: Screenshot
- Result: PASS
- Screenshot: tests/screenshots/US-002.png
- Badge visible on all task cards

### Learnings
- Use data-testid for reliable selectors
- Color classes: bg-red-500, bg-yellow-500, bg-gray-500
---
```

---

## Troubleshooting

### Browser Tests Too Slow

**Problem:** Each iteration takes too long with browser testing.

**Solutions:**
1. Batch related UI stories
2. Use screenshot instead of interaction for simple changes
3. Skip browser tests for pure backend stories
4. Increase `contextThreshold` in test-plan.json

### Context Running Out

**Problem:** Kimi runs out of context during browser testing.

**Solutions:**
1. Ralph will auto-adjust to screenshot-only mode
2. Use `/compact` to summarize context mid-run
3. Reduce batch size
4. Run fewer iterations

### Tests Failing After Implementation

**Problem:** Tests fail even after implementing the story.

**Check:**
1. Are selectors correct? (use data-testid)
2. Is dev server running?
3. Are there async timing issues? (add waits)
4. Did implementation match test expectations?

### Playwright MCP Not Available

**Problem:** Browser MCP tools not found.

**Solutions:**
1. Skip browser tests for this run
2. Add MCP server: `kimi mcp add ...`
3. Use manual testing (document in progress.txt)

---

## Advanced Configuration

### Custom Test Commands

Update `test-plan.json`:
```json
{
  "commands": {
    "test:unit": "vitest run",
    "test:e2e": "playwright test --project=chromium",
    "test:visual": "playwright test --grep visual"
  }
}
```

### Visual Regression Testing

Enable in Playwright:
```typescript
// playwright.config.ts
export default {
  expect: {
    toHaveScreenshot: {
      maxDiffPixels: 100,
    },
  },
};
```

Then in tests:
```typescript
test('visual regression', async ({ page }) => {
  await page.goto('/tasks');
  await expect(page).toHaveScreenshot('tasks-page.png');
});
```

---

## Contributing

Contributions welcome! Areas for improvement:

- Additional testing strategies
- MCP server integrations
- CI/CD workflow templates
- Language/framework support

---

## Credits

- Original Ralph pattern by [Geoffrey Huntley](https://ghuntley.com/ralph)
- Original Ralph implementation by [Snarktank](https://github.com/snarktank/ralph)
- Test-driven enhancements by [nicklynch10](https://github.com/nicklynch10)

---

## License

MIT License - see LICENSE file.
