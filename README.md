# Odoo 19 Enterprise — local dev install

`install_odoo19.sh` automates a from-source Odoo 19 Enterprise development setup on Ubuntu, so a new user account can go from blank to a running Odoo instance with one command.

## Requirements

- Ubuntu with `sudo` access (used for the apt package install).
- Access to the private `odoo/enterprise` repository on GitHub. Either:
  - an SSH key for a GitHub account with that access (default — the script clones over SSH), or
  - a Personal Access Token: set `ENTERPRISE_REPO` to `https://<TOKEN>@github.com/odoo/enterprise` before running. The script strips the token from the stored git remote right after cloning, so it does not stay in `.git/config` in plain text.

If using SSH, verify access first:

```bash
ssh -T git@github.com
```

## What it does

1. Installs system packages (git, build toolchain, PostgreSQL, wkhtmltopdf, rtlcss) via apt/npm.
2. Creates a PostgreSQL role matching your Linux username (local peer auth, no DB password).
3. Creates the folder structure below.
4. Clones `odoo/odoo` (community) and `odoo/enterprise`, both on branch `19.0`.
5. Creates a Python virtualenv and installs the Python dependencies.
6. Writes `Config/odoo.conf` with `addons_path` set to custom addons + enterprise + community.
7. Generates a PyCharm project (`.idea/`) with an "Odoo 19 (odoo-bin)" run configuration.
8. Creates the database and installs Sales, Project, Helpdesk and Timesheets.

## Folder structure

```
~/Odoo19/                        (default — override with ODOO_ROOT)
├── Config/odoo.conf
├── Enterprise/repo_odoo_enterprise_19/   odoo/enterprise, branch 19.0
├── Odoo19/repo_odoo_community_19/        odoo/odoo, branch 19.0
├── Servers/                              custom addons
├── venv/                                 Python virtualenv
├── data/                                 filestore / sessions
├── logs/odoo.log
└── .idea/                                PyCharm project + run configuration
```

## Usage

```bash
./install_odoo19.sh
```

With a token:

```bash
ENTERPRISE_REPO='https://<TOKEN>@github.com/odoo/enterprise' ./install_odoo19.sh
```

Optional environment variables:

| Variable | Default | Meaning |
|---|---|---|
| `ODOO_ROOT` | `~/Odoo19` | project folder |
| `ODOO_BRANCH` | `19.0` | branch for both repos |
| `VERSION_SHORT` | `19` | used in folder/clone names |
| `COMMUNITY_REPO` | `https://github.com/odoo/odoo.git` | community remote |
| `ENTERPRISE_REPO` | `git@github.com:odoo/enterprise.git` | enterprise remote (token URL if not using SSH) |
| `ODOO_DB` | `<username>_odoo19` | database name |
| `ODOO_HTTP_PORT` | `8069` | HTTP port |
| `ODOO_MASTER_PASSWORD` | random (`openssl rand`) | `admin_passwd`, printed at the end |
| `ODOO_APPS` | `sale,project,helpdesk,hr_timesheet` | apps installed on first run |
| `CLONE_DEPTH` | `1` | shallow clone depth; `0` = full history |
| `SKIP_APT` | `0` | `1` to skip system package install |
| `SKIP_DB` | `0` | `1` to skip database creation |

The script is safe to re-run: it reuses existing clones (fetching the latest `19.0`), reuses the venv, and skips database init if the database already exists.

Without enterprise access the script still finishes: it installs everything else and skips Helpdesk (enterprise-only) with a warning. Re-run it once access is granted.

## After it finishes

Start Odoo by hand:

```bash
~/Odoo19/venv/bin/python ~/Odoo19/Odoo19/repo_odoo_community_19/odoo-bin -c ~/Odoo19/Config/odoo.conf
```

Then open http://localhost:8069. The master password printed at the end is needed the first time you create or manage a database.

To use PyCharm, open `~/Odoo19` as a project.

## Known limitations

- **PyCharm interpreter:** the run configuration is generated, but PyCharm may not pick up the venv automatically. If so, add `~/Odoo19/venv/bin/python` manually under *Settings → Python Interpreter → Add Interpreter → Existing*. Automating this step is still on the to-do list.

## Bugs found while building and testing

Tested end-to-end on a fresh Ubuntu user account. Three issues came up:

1. **PyCharm run configuration — `ValueError: embedded null byte`.** Pointing the "Paths to .env files" field at the venv's python binary makes PyCharm parse the binary as a text `.env` file and crashes debugpy on launch. The generated configuration never sets `ENV_FILES`.
2. **Odoo 19 config parsing — `ValueError: invalid literal for int() with base 10: ''`.** An empty `db_port =` in `odoo.conf` crashes database init, because Odoo 19 casts `db_port` through `int()` whenever the key exists. The script omits `db_host`/`db_port`/`db_password` entirely, so Odoo falls back to peer auth over the local socket.
3. **Silent failure from bash scoping.** Setting `ENTERPRISE_REPO='...'` on its own line before the script (instead of on the same line) does not export it, so the clone silently falls back to SSH, fails without a key, and the script continues without Helpdesk.

## License

MIT
