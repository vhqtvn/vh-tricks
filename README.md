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
