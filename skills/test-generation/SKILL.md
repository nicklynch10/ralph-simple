---
name: test-generation
description: "Generate automated tests from PRD acceptance criteria. Creates Playwright tests, unit tests, and test plans from user stories. Use when creating tests for stories or converting PRD to test suite."
user-invocable: true
---

# Test Generation from PRD

Generate comprehensive test suites from PRD acceptance criteria. Creates automated tests (Playwright, Jest, etc.) and test plans.

---

## The Job

1. Read the PRD from prd.json
2. Analyze each user story's acceptance criteria
3. Generate appropriate tests for each story
4. Create test files in the project's test directory
5. Create test-plan.json tracking test coverage

---

## Test Types Generated

### 1. Unit Tests

For backend logic, utilities, data transformations:

```typescript
// Example: Testing a priority filter function
describe('filterByPriority', () => {
  it('should return only high priority tasks', () => {
    const tasks = [
      { id: 1, priority: 'high' },
      { id: 2, priority: 'low' },
    ];
    expect(filterByPriority(tasks, 'high')).toHaveLength(1);
  });
});
```

### 2. Component Tests

For React/Vue/Angular components:

```typescript
// Example: Testing a priority badge component
describe('PriorityBadge', () => {
  it('should render red for high priority', () => {
    render(<PriorityBadge priority="high" />);
    expect(screen.getByTestId('badge')).toHaveClass('bg-red-500');
  });
});
```

### 3. Playwright E2E Tests

For user flows and integration:

```typescript
// Example: Testing the priority filter flow
test('user can filter tasks by priority', async ({ page }) => {
  await page.goto('/tasks');
  await page.selectOption('[data-testid="priority-filter"]', 'high');
  await expect(page.locator('.task-card')).toHaveCount(2);
});
```

### 4. API Tests

For backend endpoints:

```typescript
// Example: Testing task creation API
test('POST /api/tasks creates task with priority', async () => {
  const response = await request.post('/api/tasks', {
    data: { title: 'Test', priority: 'high' }
  });
  expect(response.ok()).toBeTruthy();
  expect(await response.json()).toMatchObject({ priority: 'high' });
});
```

---

## Test Generation Rules

### From Acceptance Criteria

| Criterion Type | Test Generated |
|----------------|----------------|
| "Add X to database" | Migration test + API test |
| "Display X on page" | Component test + Screenshot test |
| "User can click X" | Interaction test (Playwright) |
| "Filter/sort X" | Integration test + E2E test |
| "Typecheck passes" | Type check command (not a test file) |
| "Tests pass" | Meta - ensures generated tests pass |

### Test File Naming

```
e2e/
  us-001-add-priority-field.spec.ts
  us-002-display-priority-badge.spec.ts

unit/
  priority-filter.test.ts
  priority-utils.test.ts

components/
  PriorityBadge.test.tsx
```

---

## test-plan.json Structure

Generated alongside prd.json to track test coverage:

```json
{
  "project": "MyApp",
  "generatedAt": "2025-02-02T12:00:00Z",
  "tests": [
    {
      "storyId": "US-001",
      "testFiles": [
        "e2e/us-001-add-priority-field.spec.ts",
        "unit/database/priority-column.test.ts"
      ],
      "testTypes": ["migration", "api"],
      "coverage": {
        "unit": true,
        "integration": false,
        "e2e": true
      },
      "generated": true,
      "status": "pending"
    },
    {
      "storyId": "US-002",
      "testFiles": [
        "e2e/us-002-display-priority-badge.spec.ts",
        "components/PriorityBadge.test.tsx"
      ],
      "testTypes": ["component", "visual"],
      "coverage": {
        "unit": true,
        "integration": false,
        "e2e": true
      },
      "generated": true,
      "status": "pending"
    }
  ],
  "commands": {
    "unit": "npm test",
    "e2e": "npx playwright test",
    "all": "npm run test:all"
  }
}
```

---

## Generation Process

### Step 1: Analyze PRD

For each user story:
1. Extract acceptance criteria
2. Determine test types needed
3. Identify test boundaries

### Step 2: Generate Test Files

Create test files with:
- Descriptive test names matching criteria
- Proper setup/teardown
- Data test IDs for E2E tests
- Mock data where appropriate

### Step 3: Add Test IDs

Update component code to add data-testid attributes:

```tsx
// Before
<button onClick={handleSave}>Save</button>

// After
<button data-testid="save-button" onClick={handleSave}>Save</button>
```

### Step 4: Update PRD

Add test references to prd.json:

```json
{
  "id": "US-001",
  "title": "Add priority field",
  ...,
  "tests": [
    "e2e/us-001-add-priority-field.spec.ts"
  ]
}
```

---

## Example: Complete Test Generation

**Input Story:**
```json
{
  "id": "US-002",
  "title": "Display priority indicator on task cards",
  "acceptanceCriteria": [
    "Each task card shows colored priority badge (red=high, yellow=medium, gray=low)",
    "Priority visible without hovering or clicking",
    "Typecheck passes",
    "Verify in browser using dev-browser skill"
  ]
}
```

**Generated Tests:**

1. **Component Test** (`components/PriorityBadge.test.tsx`):
```typescript
describe('PriorityBadge', () => {
  it.each([
    ['high', 'bg-red-500'],
    ['medium', 'bg-yellow-500'],
    ['low', 'bg-gray-500'],
  ])('renders %s priority with correct color', (priority, expectedClass) => {
    render(<PriorityBadge priority={priority} />);
    expect(screen.getByTestId('priority-badge')).toHaveClass(expectedClass);
  });
});
```

2. **E2E Test** (`e2e/us-002-display-priority-badge.spec.ts`):
```typescript
test('priority badge visible on task cards', async ({ page }) => {
  await page.goto('/tasks');
  const taskCard = page.locator('[data-testid="task-card"]').first();
  const badge = taskCard.locator('[data-testid="priority-badge"]');
  await expect(badge).toBeVisible();
  
  // Screenshot for verification
  await page.screenshot({ path: 'tests/screenshots/us-002-badge-visible.png' });
});
```

3. **Visual Regression Test** (if configured):
```typescript
test('priority badge visual appearance', async ({ page }) => {
  await page.goto('/tasks');
  await expect(page.locator('[data-testid="task-card"]')).toHaveScreenshot();
});
```

---

## Integration with Ralph Flow

### New Workflow with Test Generation

```
1. User creates PRD using /skill:prd
2. User converts PRD using /skill:ralph
3. USER GENERATES TESTS using /skill:test-generation
4. Ralph loop begins:
   a. Pick story with passes: false
   b. Run existing tests → ensure they fail (TDD)
   c. IMPLEMENT story
   d. Run tests again → ensure they pass
   e. IF UI story → Browser test with MCP
   f. Update prd.json
   g. Update test-plan.json (mark tests passed)
   h. Commit
```

### Test-First Approach (TDD)

For strict TDD:
1. Generate tests BEFORE implementation
2. Run tests - they should fail
3. Implement story
4. Run tests - they should pass
5. Browser test for UI
6. Commit

---

## Best Practices

1. **Test at the right level** - Unit for logic, E2E for flows
2. **One test file per story** - Easy to map coverage
3. **Descriptive test names** - Should read like acceptance criteria
4. **Use test IDs** - data-testid for reliable selectors
5. **Independent tests** - Each test can run alone
6. **Fast feedback** - Unit tests < 1s, E2E < 10s each

---

## Output

After running this skill:
- Test files created in appropriate directories
- test-plan.json with coverage tracking
- PRD updated with test references
- Components updated with test IDs (if applicable)

---

## Commands

The skill will detect and use your project's test commands:

```json
{
  "scripts": {
    "test": "jest",
    "test:unit": "jest --testPathPattern=unit",
    "test:e2e": "playwright test",
    "test:all": "npm run test:unit && npm run test:e2e"
  }
}
```
