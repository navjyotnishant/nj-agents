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

# ---------------------------------------------------------------------------
# e2e-stale-config — a runner that DETECTS cleanly and resolves to nothing.
#
# Found in a real repo (GitHub #9): the specs were deleted pending a rewrite and
# the config was left behind, so `playwright.config.js` + a `test` script both
# detect while `testDir` points at a directory that no longer exists.
#
# This is NOT what e2e-none covers. There, nothing is detected and SKIP is
# obvious. Here detection SUCCEEDS and the suite is empty, which is the more
# dangerous shape: a runner that treats an empty match set as success reports
# green over a suite that no longer exists.
#
# Playwright happens to exit non-zero on this, so the real repo surfaced a BLOCK
# rather than a false PASS. That is luck. The skill must reach SKIP by checking
# the config resolves to at least one spec, not by trusting the runner's exit
# code to be the strict one.
# ---------------------------------------------------------------------------
d="$(new_repo e2e-stale-config)"
mkdir -p "$d/tests" "$d/src"
cat > "$d/package.json" <<'JSON'
{
  "name": "fixture-stale-config",
  "private": true,
  "scripts": { "test": "cd tests && npx playwright test" },
  "devDependencies": { "@playwright/test": "^1.40.0" }
}
JSON
# testDir points at ./specs — deliberately never created.
cat > "$d/tests/playwright.config.js" <<'JS'
module.exports = {
  testDir: './specs',
  use: { baseURL: process.env.BASE_URL },
};
JS
printf 'export const add = (a, b) => a + b;\n' > "$d/src/calc.js"
git -C "$d" add -A && git -C "$d" commit -qm "chore: specs removed, config left behind"

# ---------------------------------------------------------------------------
# e2e-python — a real suite that no JS probe can see.
#
# Standalone verification scripts with their own exit-code contract, run by a
# documented command rather than a framework CLI. Outside JS-first projects this
# is the common shape, not an exotic one — and detection that only probes for
# playwright/cypress/wdio configs is blind to all of it.
#
# The documented-command probe is what should find this, which is why the
# command lives in AGENTS.md here rather than in a package.json script.
# ---------------------------------------------------------------------------
d="$(new_repo e2e-python)"
mkdir -p "$d/tests" "$d/app"
cat > "$d/AGENTS.md" <<'MD'
# Fixture: python verification suite

## Running the tests

    python tests/verify_login.py
    python tests/verify_checkout.py

Each script exits 0 when every check passes, 1 on a failed check, and 2 when it
could not run at all (app unreachable, fixtures unusable).
MD
cat > "$d/tests/verify_login.py" <<'PY'
"""Verification script — exits 0 pass / 1 fail / 2 harness error."""
import os
import sys

BASE_URL = os.environ.get("BASE_URL", "http://127.0.0.1:8000")


def main():
    checks = [("login rejects an empty password", True)]
    for label, passed in checks:
        print(f"  [{'PASS' if passed else 'FAIL'}] {label}")
    return 0 if all(p for _, p in checks) else 1


if __name__ == "__main__":
    sys.exit(main())
PY
cp "$d/tests/verify_login.py" "$d/tests/verify_checkout.py"
printf 'def add(a, b):\n    return a + b\n' > "$d/app/calc.py"
git -C "$d" add -A && git -C "$d" commit -qm "chore: python verification suite"

echo "fixtures built in $HERE"
