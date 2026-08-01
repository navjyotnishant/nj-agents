#!/usr/bin/env bash
# Build the fixture repos from scratch. They are generated, not committed — a git
# repo inside a git repo is a submodule trap, and these must be disposable.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

new_repo() {
  local d="$HERE/$1"; rm -rf "$d"; mkdir -p "$d"
  git -C "$d" init -q
  git -C "$d" config user.email fixture@example.test
  git -C "$d" config user.name "Fixture"
  git -C "$d" config commit.gpgsign false
  echo "$d"
}

# dirty — a small uncommitted change for the review class to look at.
d="$(new_repo dirty)"
printf 'def add(a, b):\n    return a + b\n' > "$d/calc.py"
git -C "$d" add -A && git -C "$d" commit -qm "init"
printf 'def add(a, b):\n    return a + b\n\ndef div(a, b):\n    return a / b\n' > "$d/calc.py"

# with-changelog / without-changelog — the two §A4 placement rungs.
d="$(new_repo with-changelog)"
printf '# Changelog\n\n## [Unreleased]\n\n### Added\n- an existing entry\n' > "$d/CHANGELOG.md"
printf 'x = 1\n' > "$d/app.py"
git -C "$d" add -A && git -C "$d" commit -qm "feat: add app"

# A tag + commits after it, so /changelog has a real "since the last release" range
# to summarise. Without one it has nothing to write, and an empty result would look
# like a contract violation when it is just an empty input.
d="$(new_repo without-changelog)"
printf 'x = 1\n' > "$d/app.py"
git -C "$d" add -A && git -C "$d" commit -qm "chore: init"
git -C "$d" tag -a v0.1.0 -m "v0.1.0"
printf 'x = 1\ny = 2\n' > "$d/app.py"
git -C "$d" add -A && git -C "$d" commit -qm "feat: add y"
printf 'def z():\n    return 3\n' > "$d/z.py"
git -C "$d" add -A && git -C "$d" commit -qm "fix: handle z"

# ---------------------------------------------------------------------------
# Testing-class fixtures (NAV-207).
#
# The testing skills detect a runner rather than assuming one, so a single
# fixture cannot show that: it would pass just as well against a hardcoded
# Playwright path. Two different stacks is the minimum that proves detection,
# and a third with no runner at all proves the SKIP path.
#
# These are DELIBERATELY NOT RUNNABLE. Installing browser binaries into a
# fixture would make `make.sh` slow, network-dependent, and CI-hostile — and
# what needs testing here is what the skills DECIDE (which runner, which URL
# rule, which class of failure), not whether Playwright can drive Chromium.
# The specs are present and syntactically real so detection has something
# honest to find.
# ---------------------------------------------------------------------------

# e2e-playwright — the common case: a config, a script, a spec, a testid.
d="$(new_repo e2e-playwright)"
mkdir -p "$d/e2e" "$d/src"
cat > "$d/package.json" <<'JSON'
{
  "name": "fixture-playwright",
  "private": true,
  "scripts": { "test:e2e": "playwright test" },
  "devDependencies": { "@playwright/test": "^1.40.0" }
}
JSON
cat > "$d/playwright.config.ts" <<'TS'
import { defineConfig } from '@playwright/test';
export default defineConfig({
  testDir: './e2e',
  use: { baseURL: process.env.BASE_URL, trace: 'on-first-retry' },
});
TS
# A spec with a proper testid locator — what /test-author should emit.
cat > "$d/e2e/login.spec.ts" <<'TS'
import { test, expect } from '@playwright/test';

test('rejects an empty password', async ({ page }) => {
  await page.goto('/login');
  await page.getByTestId('username').fill('user@example.test');
  await page.getByTestId('submit').click();
  await expect(page.getByTestId('error')).toHaveText('Password is required');
});
TS
# A spec with a brittle locator — what /test-author must FLAG and /test-repair
# is allowed to fix. Positional CSS breaks on any reorder.
cat > "$d/e2e/checkout.spec.ts" <<'TS'
import { test, expect } from '@playwright/test';

test('shows the order total', async ({ page }) => {
  await page.goto('/checkout');
  await page.click('.actions > button:nth-child(2)');
  await expect(page.locator('.summary .row:nth-child(3)')).toContainText('Total');
});
TS
printf '<button data-testid="submit">Go</button>\n' > "$d/src/login.html"
git -C "$d" add -A && git -C "$d" commit -qm "chore: playwright e2e suite"

# e2e-cypress — a DIFFERENT stack. If a skill only works here by accident of
# hardcoding, this is the fixture that catches it.
d="$(new_repo e2e-cypress)"
mkdir -p "$d/cypress/e2e"
cat > "$d/package.json" <<'JSON'
{
  "name": "fixture-cypress",
  "private": true,
  "scripts": { "e2e": "cypress run" },
  "devDependencies": { "cypress": "^13.0.0" }
}
JSON
cat > "$d/cypress.config.js" <<'JS'
module.exports = {
  e2e: { baseUrl: process.env.BASE_URL, specPattern: 'cypress/e2e/**/*.cy.js' },
};
JS
cat > "$d/cypress/e2e/search.cy.js" <<'JS'
describe('search', () => {
  it('returns a result', () => {
    cy.visit('/search');
    cy.get('[data-testid="query"]').type('widget');
    cy.get('[data-testid="results"]').should('contain', 'widget');
  });
});
JS
git -C "$d" add -A && git -C "$d" commit -qm "chore: cypress e2e suite"

# e2e-none — source, tests, but no E2E runner anywhere. /e2e-run must SKIP
# with a labeled reason (§T5) rather than installing one or inventing a
# command. A silent pass here would be the worst outcome of the three.
d="$(new_repo e2e-none)"
mkdir -p "$d/src" "$d/tests"
cat > "$d/package.json" <<'JSON'
{
  "name": "fixture-no-e2e",
  "private": true,
  "scripts": { "test": "node --test" }
}
JSON
printf 'export const add = (a, b) => a + b;\n' > "$d/src/calc.js"
printf "import {add} from '../src/calc.js';\n" > "$d/tests/calc.test.js"
git -C "$d" add -A && git -C "$d" commit -qm "chore: unit tests only, no e2e"

echo "fixtures built in $HERE"
