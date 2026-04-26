# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A personal workspace folder backed up to GitHub (`PandamanBLP/Claudcodebackup`). Not a project codebase — anything created here gets auto-committed and pushed.

## Working rule: push regularly

The user's standing instruction is: **push to GitHub frequently so we never lose our place.** The 30-minute auto-backup is a safety net, not a substitute. After any meaningful change in a session (new files, edits to scripts, doc updates), run a manual push instead of waiting for the next scheduled tick:

```powershell
Start-ScheduledTask ClaudeCodeBackup    # easiest — uses the existing script
# or:
git add -A && git commit -m "<msg>" && git push
```

If a session involves multiple meaningful checkpoints, push at each one rather than batching.

## Auto-backup mechanism

A Windows Scheduled Task named `ClaudeCodeBackup` runs `backup.ps1` every 30 minutes. The script:

1. Skips if `git status --porcelain` is clean
2. Otherwise runs `git add -A`, commits with message `Auto-backup <timestamp>`, and pushes to `origin main`
3. Logs to `.backup.log` (gitignored)

**Implications when working in this folder:**

- Anything you create here will be on a public-by-default GitHub repo within 30 minutes — do not drop secrets, large binaries, or anything you wouldn't push manually.
- `git status` may show a clean tree even though you just edited files — the scheduler may have already committed and pushed in the background. Always `git pull` before assuming local state is authoritative if any time has passed.
- `backup.ps1` hardcodes the absolute path `C:\Users\jlync\OneDrive\Desktop\ClaudeCode`. Moving or renaming the folder breaks the task without warning — update both the script and the task action if relocating.

## Managing the backup task

| Action | Command |
|---|---|
| Run now | `Start-ScheduledTask ClaudeCodeBackup` |
| Status / next run | `Get-ScheduledTask ClaudeCodeBackup \| Get-ScheduledTaskInfo` |
| Tail log | `Get-Content .backup.log -Tail 20` |
| Pause | `Disable-ScheduledTask ClaudeCodeBackup` |
| Resume | `Enable-ScheduledTask ClaudeCodeBackup` |
| Remove | `Unregister-ScheduledTask ClaudeCodeBackup -Confirm:$false` |

The task runs only when the user is logged in (no stored password). Missed runs fire on next logon (`StartWhenAvailable`).

## Gitignored

`.claude/` (Claude Code session data) and `.backup.log` are gitignored and must stay that way — they contain machine-local state.

## Environment notes

- The folder lives inside OneDrive (`C:\Users\jlync\OneDrive\Desktop\ClaudeCode`), so files are also synced separately by OneDrive. Watch for `desktop.ini` / sync-conflict files (already gitignored).
- Auth to GitHub is via Git Credential Manager (bundled with Git for Windows) — no `gh` CLI installed. If a push fails with auth error, run `git push` manually once to re-trigger the browser flow.
