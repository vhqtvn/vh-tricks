# claude/multi — Multi-account Claude Code launcher (isolated auth, shared sessions)

Run multiple Claude Code accounts on one Linux machine with **separate
authentication/identity per profile** but a **shared, resumable session
history**. Stop a session under account A, resume the exact same session under
account B.

```
account A auth/state  !=  account B auth/state
account A projects    ==  account B projects
```

Isolation is done entirely with **bubblewrap bind mounts over the real
canonical paths** — no symlinks, no sandbox-HOME swap. Claude sees its normal
`~/.claude`; only the account state is swapped underneath. `CLAUDE_CONFIG_DIR`
is set to `~/.claude` purely so the global config file lives at
`~/.claude/.claude.json` (inside the bound directory) — see
[Why `.claude.json` lives inside `~/.claude`](#why-claudejson-lives-inside-claude).
The bind mounts, not `CLAUDE_CONFIG_DIR`, are what isolate the accounts.

**Requires:** `bubblewrap` (`bwrap`).

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/vhqtvn/vh-tricks/main/claude/multi/install.sh | bash
```

Configure at install time with env vars (persisted to
`~/.config/claude-multi/config` and **reused on later updates / reinstalls**).
Put the variables on the `bash` side of the pipe — with `curl ... | bash` the
piped `bash` is a separate process and would not inherit vars set on `curl`:

```bash
curl -fsSL .../claude/multi/install.sh \
  | CLAUDE_MULTI_PROFILES="work personal alt" CLAUDE_MULTI_SHARED="projects" bash
```

Or export them first (an exported var is inherited by the piped `bash`):

```bash
export CLAUDE_MULTI_PROFILES="work personal alt"
curl -fsSL .../claude/multi/install.sh | bash
```

**Uninstall** (keeps state + config so a reinstall reuses them):

```bash
curl -fsSL .../claude/multi/install.sh | bash -s -- --uninstall
```

**Full reset** (also deletes all profile/shared state and config):

```bash
curl -fsSL .../claude/multi/install.sh | bash -s -- --purge
```

## Configuration

| Variable | Default | Meaning |
|---|---|---|
| `CLAUDE_MULTI_PROFILES` | `a b` | Profiles to create wrappers for (`claude-a`, `claude-b`, …) |
| `CLAUDE_MULTI_ROOT` | `~/.local/share/claude-multi` | State root |
| `CLAUDE_MULTI_SHARED` | `projects` | `~/.claude` subdirs shared across profiles |
| `CLAUDE_MULTI_CACHE` | `1` | Give each profile a private disposable `~/.cache` |
| `CLAUDE_MULTI_WRITABLE` | *(empty)* | Extra host paths exposed writable, e.g. `"$HOME/.npm"` |
| `CLAUDE_MULTI_RUNTIME_DIR` | `1` | Expose `$XDG_RUNTIME_DIR` (ssh-agent / keyring sockets) |
| `CLAUDE_MULTI_LINK_MAIN` | *(empty)* | Subdirs to symlink to main `~/.claude` at install (`projects`, a list, or `all`) |

Env vars override the stored config at runtime too, e.g. `CLAUDE_MULTI_SHARED="projects file-history" claude-a`.

To change settings later: re-run the installer with new env vars (it rewrites
the config), edit `~/.config/claude-multi/config` directly, or `--purge` and
reinstall.

## State layout

```
~/.local/share/claude-multi/
├── profiles/
│   ├── a/
│   │   ├── .claude/        # PRIVATE: .claude.json (identity), .credentials.json,
│   │   │                   #          settings.json, history.jsonl, sessions/, ...
│   │   └── cache/          # private disposable ~/.cache
│   └── b/ ...
└── shared/
    ├── projects/           # SHARED: resumable session transcripts (<uuid>.jsonl)
    └── .locks/             # resume concurrency guards
```

## Filesystem view inside bwrap

Bind mounts are applied **in order**:

```
--ro-bind / /                                  # whole host, read-only
--proc /proc  --dev /dev  --tmpfs /tmp         # fresh proc/dev, writable /tmp
--bind  $PWD                    $PWD           # 1) working tree (writable) — may be/overlap $HOME
--bind  $XDG_RUNTIME_DIR        $XDG_RUNTIME_DIR    # ssh-agent / keyring (writable)
--bind  <profile>/.claude       ~/.claude      # 2) private account state, ON TOP of cwd
--bind  <profile>/cache         ~/.cache       # private disposable cache
--bind  shared/projects         ~/.claude/projects  # 3) overlay shared, LAST (on top of .claude)
--die-with-parent
--setenv TMPDIR /tmp
--setenv CLAUDE_CONFIG_DIR ~/.claude           # .claude.json lives INSIDE the bound dir
--unsetenv ANTHROPIC_API_KEY ... (provider/API creds stripped)
```

**Bind order matters.** bwrap applies binds in sequence, and a later bind over
an ancestor path shadows earlier binds beneath it. The working tree (`$PWD`) and
`$XDG_RUNTIME_DIR` can live under — or *be* — `$HOME`, so they are bound **first**;
the per-profile `~/.claude` is bound **on top**; shared subdirs are bound
**last**. If the cwd bind came after the profile bind, running a wrapper from
your home directory (`cd ~; claude-a`, or over `ssh`, whose cwd is `$HOME`) would
re-expose the real `~/.claude` to every profile and collapse all accounts into
one. `claude-multi verify` tests this explicitly (checks 9–10).

### Why `.claude.json` lives inside `~/.claude`

Claude Code's global config `.claude.json` is normally at `~/.claude.json`
(next to `~/.claude`, not inside it), and it is saved with an **atomic
temp-file + `rename()`**. You cannot `rename()` over a single-file bind mount —
it fails with `EBUSY` ("Device or resource busy") — so bind-mounting
`~/.claude.json` as a file makes every save silently fail: the account identity
(`oauthAccount`, shown by `claude auth status`) freezes at whatever it was
seeded with, and all profiles appear to be the same account even though their
`.credentials.json` differ. To avoid this, the launcher sets
`CLAUDE_CONFIG_DIR=~/.claude`, which relocates `.claude.json` to
`~/.claude/.claude.json` — **inside** the bound directory, where atomic renames
work. A directory bind, unlike a single-file bind, isolates and persists
correctly. Existing profiles are migrated automatically (the old
`profiles/<p>/.claude.json` is moved into `profiles/<p>/.claude/`).
`verify` check 9c guards the atomic-write path.

Result inside the sandbox:

- `~/.claude` (incl. `~/.claude/.claude.json`) → this profile's private state (writable).
- `~/.claude/projects` → common shared transcripts (writable) → **resume works
  across profiles**.
- `~/.cache` → profile-local, disposable.
- Working directory → writable. **Everything else on the host is read-only.**
- Real `$HOME` path is preserved, so git/ssh/npm configs resolve normally.
- No PID/IPC/UTS/network namespace, no `--new-session` → normal PTY/process
  behaviour (works under Paseo). Only `--die-with-parent` is kept.

### What is shared vs private (inspected on Claude Code 2.1.291)

- **Shared:** `projects/` only, by default — the `<uuid>.jsonl` transcripts are
  the resumable session history.
- **Private:** `.credentials.json`, `.claude.json`, `history.jsonl`,
  `settings.json`, `plugins/`, `skills/`, …
- **Never shared (runtime coordination):** `sessions/` (PID-keyed), `jobs/`,
  `daemon/`, `ide/`.
- **Optional higher-fidelity sharing:** add `file-history` (for `/rewind` across
  accounts) and/or `session-env` to `CLAUDE_MULTI_SHARED`. Both are UUID-keyed
  and safe to share; left private by default to start conservatively.
- Note: this version has **no `tasks/`, `plans/`, or `todos/`** directory. If a
  future version adds one, just add its name to `CLAUDE_MULTI_SHARED` — no code
  change needed.

### Share sessions with your main (non-sandboxed) Claude

To also share history with the normal `claude` you run outside the sandbox,
point the shared store at your real `~/.claude/<subdir>`. bwrap resolves the
bind source through the symlink, so all profiles **and** main read/write the
same transcripts. Use the built-in subcommand:

```bash
claude-multi link-main              # link the whole shared set (default: projects)
claude-multi link-main projects     # or name specific subdirs
claude-multi unlink-main            # detach again (independent dirs)
claude-multi unlink-main --copy     # detach, keeping a snapshot of main's content
```

Existing shared content is merged into main non-destructively (`cp -an`, never
overwrites) before the shared dir is replaced by a symlink. `link-main` only
**asks for confirmation when something would actually be lost** — i.e. a shared
file collides with a *different* existing file in `~/.claude` (main's copy is
kept). Empty dirs, unique files, identical files, and re-linking are lossless
and run without prompting. It is idempotent. Pass `--yes` (or
`CLAUDE_MULTI_YES=1`) to auto-confirm in scripts; with a real collision, no
terminal and no `--yes`, it refuses rather than guess. `unlink-main` never
prompts (the data stays in main).

Set it up **at install time** with `CLAUDE_MULTI_LINK_MAIN` (`projects`, a space
list, or `all`); the installer runs `link-main` for you (prompting on your
terminal, which works through `curl … | bash`):

```bash
curl -fsSL .../claude/multi/install.sh \
  | CLAUDE_MULTI_PROFILES="work personal" CLAUDE_MULTI_LINK_MAIN="projects" bash
```

Your main account then becomes just another participant in the shared history
(transcripts are account-agnostic, so resume works across all of them).
`--purge`/`rm -rf` removes the symlink, not the real `~/.claude` directory.

## Usage

Select a profile by calling its wrapper (what **Paseo** should invoke):

```bash
claude-a                 # = claude-multi run a  -> claude
claude-b --resume UUID   # = claude-multi run b  -> claude --resume UUID
```

Or the dispatcher directly:

```bash
claude-multi run a [claude args...]     # launch
claude-multi list                       # profiles + login status
claude-multi init <profile>             # create empty profile
claude-multi import <profile> [opts]    # migrate existing ~/.claude in
claude-multi exec <profile> -- <cmd>    # run any command in the sandbox
claude-multi verify                     # sandbox isolation self-test
claude-multi where                      # print state paths
```

### Initialize & log in

```bash
# (optional) seed profile 'a' from your current, already-logged-in ~/.claude.
# Non-destructive: never touches your real ~/.claude. Copies private
# creds/settings into profile a, and seeds shared/projects once.
claude-multi import a --seed-shared

# Log each profile in independently:
claude-a      # then run /login inside Claude, authenticate account A, exit
claude-b      # then /login, authenticate account B, exit
```

Fresh (no import) is fine too — `claude-a` starts an empty profile; just
`/login`.

### Resume a session created by another profile

```bash
# under A:
claude-a
#   -> session UUID X is written to shared/projects/<cwd-slug>/X.jsonl, exit

# under B (same working directory):
claude-b --resume X
#   -> continues exactly that session
```

**Concurrency guard:** launching with `--resume <uuid>` takes a best-effort
`flock` on `shared/.locks/<uuid>.lock` held for the process lifetime. A second
profile trying to `--resume` the same UUID while it is live is refused. Do not
design for two accounts writing the same session at once.

> First resume of a directory under a new profile may prompt to trust the
> folder (project trust lives in the private `.claude.json`).

## Paseo integration

Point each Paseo entry at a profile wrapper — they behave like a normal
`claude` invocation (host networking, normal TTY, args passed through):

```
claude-a   "$@"      # account A
claude-b   "$@"      # account B
```

No PID namespace or `--new-session` is used, so Paseo's process/session handling
is unaffected.

### Letting external tools detect a profile's account

A tool that runs **outside** the wrapper (e.g. Paseo detecting which account is
active) can point `CLAUDE_CONFIG_DIR` at a profile's `.claude` directory — it is
a self-contained config dir (`.claude.json` + `.credentials.json`). Get the path
with:

```bash
claude-multi config-dir vcf-2            # prints .../profiles/vcf-2/.claude
eval "$(claude-multi config-dir --export vcf-2)"   # exports CLAUDE_CONFIG_DIR
```

You can safely export `CLAUDE_CONFIG_DIR` in your shell for such tools: the
wrapper **ignores an inherited `CLAUDE_CONFIG_DIR`** and always forces its own
(`$HOME/.claude`) inside the sandbox, so account isolation is never affected by
whatever you set outside.

## Verification

Automated (no login needed) — proves tests 1–6 and shared visibility:

```bash
claude-multi verify
```

Checks: (1) A sees A-only marker, (2) A does not see B's, (3) B sees B-only,
(4) both see a shared `projects` marker, (5) project-dir writes succeed,
(6) writes to host `/` fail, (8*) a file A writes under `projects` is visible
to B.

Manual login-dependent checks:

```bash
# 7. Login for A does not modify B's private state:
md5sum ~/.local/share/claude-multi/profiles/b/.claude/.credentials.json  # before
claude-a   # /login as A, exit
md5sum ~/.local/share/claude-multi/profiles/b/.claude/.credentials.json  # unchanged

# 8. Real cross-account resume:
cd /some/project && claude-a      # create a session, note its UUID, exit
claude-b --resume <that-uuid>     # continues under B
```

## Migrating / upgrading

### From an earlier version of this trick

Just **re-run the installer** — it is non-destructive:

```bash
curl -fsSL .../claude/multi/install.sh | bash
```

It preserves all profile and shared state (credentials, settings, sessions),
upgrades the config to the current format (older versions stored hard
assignments that silently blocked env overrides — this fixes that), refreshes
the `claude-multi` launcher (adding `link-main` etc.), and regenerates the
per-profile wrappers. You can change settings in the same command; env vars win
over the stored config:

```bash
curl -fsSL .../claude/multi/install.sh \
  | CLAUDE_MULTI_PROFILES="a b c" CLAUDE_MULTI_SHARED="projects file-history" bash
```

Notes:
- Wrappers are only *created*, never pruned. If you drop a profile from
  `CLAUDE_MULTI_PROFILES`, delete its leftover `~/.local/bin/claude-<name>` by
  hand (or `--purge` and reinstall). Its state under `profiles/<name>/` is kept
  until you remove it.
- If you had manually symlinked a shared dir to your main `~/.claude`, it keeps
  working; `claude-multi link-main` is now the supported way to do the same.

### From a different / older standalone bwrap launcher

Install this trick, then import your existing Claude state into a profile
(non-destructive — your real `~/.claude` is only read):

```bash
claude-multi import a --seed-shared      # copies creds/settings into profile a,
                                         # seeds shared/projects once
claude-multi link-main                   # (optional) also share with the main claude
claude-a                                 # verify; /login only if needed
```

Then point your old launcher's entrypoints at the new `claude-<profile>`
wrappers and retire the old script. Nothing in the old setup is modified.

## Caveats (Claude Code 2.1.291)

- Only `projects/` is shared by default; `/rewind` checkpoints and per-session
  env live in `file-history/` / `session-env` (UUID-keyed) and are private
  unless you add them to `CLAUDE_MULTI_SHARED`.
- The resume lock is best-effort (keyed on an explicit `--resume <uuid>`); it
  does not cover `--continue`/`-c` (most-recent) resumes.
- `~/.cache` is profile-local and disposable by default; tools expecting a
  pre-populated host cache (e.g. a downloaded Chromium) won't see it. Expose
  specific host caches via `CLAUDE_MULTI_WRITABLE` if needed.
- The host filesystem is read-only except the working tree, `/tmp`, the profile
  state, and anything in `CLAUDE_MULTI_WRITABLE`; a tool needing another
  writable path will fail until you add it.
- Your real `~/.claude` is never read or modified by the launcher (only by the
  explicit `import` command, and even then read-only).
