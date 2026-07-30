# hooks/

Shell hooks that make the toolkit's advice mechanical instead of relying on the
model to remember.

Installed as symlinks by `./install.sh` (into `~/.claude/hooks/`), but **not wired
up** unless you ask — registering a hook edits your `settings.json`, which the
installer never does behind your back.

## `suggest-skills.sh`

A `UserPromptSubmit` hook. Matches the prompt against the skills that ship here and
adds a one-line note naming the ones that fit. It only **adds context** — it never
blocks a prompt and never runs a skill.

Why it exists: `global/CLAUDE.md` already says "prefer the matching skill over
improvising the same task by hand," but that relies on the model remembering, and in
a long build/test/PR loop it quietly stops happening.

`check.sh` keeps it honest — the hook hand-lists skills, so `check_hook_sync` flags
any skill it never suggests.

### Wiring it up

```bash
./install.sh --with-hooks      # idempotent; leaves existing hooks alone
```

Or add it to `~/.claude/settings.json` yourself:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/suggest-skills.sh",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

Use the absolute path — `~` is not expanded in that field.

### Requirements

`jq`, for reading the prompt out of the hook payload. It is **detected, not
required**: without `jq` the hook exits 0 silently rather than erroring on every
prompt.
