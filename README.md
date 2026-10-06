# vh-tricks

Personal shell/dev environment tricks, installable via `curl | bash`.

## Tricks

### nvm/global — Auto-switching node version wrapper

Wraps `node`, `npm`, `pnpm`, `yarn` to automatically switch node versions based on `.nvmrc` files. Also provides a `npm-global` command for managing global npm packages with a dedicated LTS node version.

**What it does:**
- Intercepts `node`/`npm`/`pnpm`/`yarn` calls, auto-detects `.nvmrc`, installs & switches node version
- Global npm packages (`~/.npm-global/`) always use LTS node regardless of project `.nvmrc`
- `npm-global install <pkg>` — install packages globally with LTS node
- `npm-global vhpatch` — patch shebangs in global bins to use the wrapper

**Requires:** [nvm](https://github.com/nvm-sh/nvm)

**Install:**
```bash
curl -fsSL https://raw.githubusercontent.com/vhqtvn/vh-tricks/main/nvm/global/install.sh | bash
```

**Uninstall:**
```bash
curl -fsSL https://raw.githubusercontent.com/vhqtvn/vh-tricks/main/nvm/global/install.sh | bash -s -- --uninstall
```

### claude/multi — Multi-account Claude Code launcher

Run multiple Claude Code accounts on one machine with **isolated auth/identity**
per profile but a **shared, resumable session history** — stop a session under
account A, resume it under account B. Pure `bwrap` bind mounts over the real
`~/.claude` / `~/.claude.json` (no symlinks, no `CLAUDE_CONFIG_DIR`, no
sandbox-HOME swap); host filesystem stays read-only except the working tree.

**What it does:**
- Each profile gets a private `~/.claude` + `~/.claude.json` (creds, settings)
- Shares `~/.claude/projects` (session transcripts) across profiles
- Generates per-profile wrappers (`claude-a`, `claude-b`, …) for Paseo
- `claude-multi verify` — sandbox isolation self-test
- Config persisted to `~/.config/claude-multi/config` (reused on update/reinstall)

**Requires:** [bubblewrap](https://github.com/containers/bubblewrap) (`bwrap`)

See [claude/multi/README.md](claude/multi/README.md) for full docs.

**Install:**
```bash
curl -fsSL https://raw.githubusercontent.com/vhqtvn/vh-tricks/main/claude/multi/install.sh | bash
```

**Uninstall** (keeps state; `--purge` wipes everything):
```bash
curl -fsSL https://raw.githubusercontent.com/vhqtvn/vh-tricks/main/claude/multi/install.sh | bash -s -- --uninstall
```
