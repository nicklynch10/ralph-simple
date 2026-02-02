---
name: browser-testing
description: "Browser testing using Playwright MCP. Use for verifying UI stories, taking screenshots, and running user acceptance tests."
user-invocable: true
---

# Browser Testing with Playwright MCP

This skill guides you through testing UI changes using browser automation tools.

---

## When to Use Browser Testing

**Use for:**
- UI stories that change visual elements
- Form submissions and user interactions
- Navigation flows
- Responsive design verification

**Skip for:**
- Pure backend/database changes
- API-only stories
- Configuration changes

---

## Context Management Strategy

**⚠️ Browser testing is context-expensive. Use strategically:**

### Efficient Testing Patterns

1. **Screenshot Verification (Quick)**
   - Navigate to page
   - Take screenshot
   - Verify elements visible
   - Context cost: ~10-15% per page

2. **Interaction Testing (Moderate)**
   - Navigate → Interact → Screenshot
   - Verify state changes
   - Context cost: ~20-30% per flow

3. **Full E2E Flow (Expensive)**
   - Complete user journey
   - Multiple pages/interactions
   - Context cost: ~40-60% per flow

---

## Browser Testing Workflow

### Step 1: Check Prerequisites

Ensure the dev server is running before testing.

### Step 2: Determine Test Type

Based on the story, choose test intensity:

| Story Type | Test Type | What to Verify |
|------------|-----------|----------------|
| Add UI element | Screenshot | Element visible, styled correctly |
| Form/input | Interaction | Input works, validation shows |
| Navigation | Flow | Links work, correct page loads |
| Full feature | E2E | Complete user journey works |

### Step 3: Execute Test

#### Screenshot Verification (Fast)

1. Navigate to the page URL
2. Wait for content to load
3. Take screenshot
4. Verify the element is visible
5. Document result in progress.txt

#### Interaction Testing (Moderate)

1. Navigate to page
2. Take "before" screenshot
3. Perform interaction (click, type, etc.)
4. Wait for change
5. Take "after" screenshot
6. Verify expected change occurred
7. Document result with both screenshots

---

## Context-Saving Tips

### Batch Related Tests

Instead of testing each story separately, batch them when possible.

### Use Selective Verification

Not every CSS change needs a full browser test:

- Color change: Skip browser test
- New button: Quick screenshot
- New form flow: Full interaction test

---

## Integration with Ralph Flow

### Modified Ralph Workflow

1. Read PRD
2. Read progress.txt
3. PICK STORY with passes: false
4. Check if UI story - Note for testing
5. IMPLEMENT story
6. RUN quality checks
7. IF UI story: Run browser test
8. Update AGENTS.md with patterns
9. Commit changes
10. Update prd.json
11. Append to progress.txt WITH test results
12. Check completion

---

## Progress.txt Format with Testing

```
## [Date/Time] - [Story ID]
- What was implemented
- Files changed
- **Testing:**
  - Test type: [Screenshot/Interaction/E2E]
  - Result: [PASS/FAIL]
  - Notes: [any issues]
- **Learnings:**
  - Patterns discovered
  - Testing gotchas
---
```

---

## Decision Matrix

Use this to decide test approach:

- Is it a UI change?
  - No → Skip browser test
  - Yes → Is it a new feature or modification?
    - Modification → Screenshot sufficient?
      - Yes → Quick screenshot
      - No → Interaction test
    - New feature → Is it complex?
      - Simple → Interaction test
      - Complex → Full E2E test

---

## Best Practices

1. **Test at the right level** - Do not over-test simple changes
2. **Document everything** - Screenshots are proof of verification
3. **Save artifacts** - Store screenshots in tests/screenshots/
4. **Be consistent** - Use same browser viewport size
5. **Fast feedback** - If test fails, fix before continuing
