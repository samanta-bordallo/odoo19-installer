# Odoo 19 Enterprise — local dev install

`install_odoo19.sh` sets up a from-source Odoo 19 Enterprise development
environment for a single user, following the team's folder convention, ready
to open in PyCharm with a working run/debug configuration out of the box.

## What you need first

Ask **Victor** for access to the private `odoo/enterprise` repo, either:
- an SSH key for a GitHub account that has that access (default — the
  script clones enterprise over SSH), or
- a `git clone` command with a GitHub Personal Access Token embedded (what
  Victor typically sends) — set `ENTERPRISE_REPO` to that same
  `https://<TOKEN>@github.com/odoo/enterprise` URL before running. The
  script strips the token out of the stored git remote right after cloning,
  so it doesn't sit in `.git/config` in plain text afterwards.

If using SSH, verify access works before running the script:

```
ssh -T git@github.com
```

## What it does

1. Installs system packages (git, build toolchain, PostgreSQL, wkhtmltopdf,
   rtlcss) via `apt`/`npm` — asks for your sudo password.
2. Creates a PostgreSQL role matching your Linux username (local/peer auth,
   no DB password needed).
3. Creates the folder structure below.
4. Clones `odoo/odoo` (community) and `odoo/enterprise`, both on branch
   `19.0`.
5. Creates a Python virtualenv and installs all Python dependencies.
6. Writes `Config/odoo.conf` with `addons_path` wired to Servers + enterprise
   + community.
7. Writes a PyCharm project (`.idea/`) with a ready-to-run/debug
   **"Odoo 19 (odoo-bin)"** run configuration — interpreter and script path
   already point at the venv, no manual "Add Interpreter" step needed.
8. Creates the database and installs **Sales, Project, Helpdesk,
   Timesheets**.

## Folder structure it creates

```
~/Odoo19/                              (default — override with ODOO_ROOT)
├── Config/
│   └── odoo.conf
├── Enterprise/
│   └── repo_odoo_enterprise_19/       odoo/enterprise, branch 19.0
├── Odoo19/
│   └── repo_odoo_community_19/        odoo/odoo, branch 19.0
├── Servers/                            empty — client-specific custom addons go here
├── venv/                                Python virtualenv
├── data/                                filestore / sessions (data_dir)
├── logs/                                odoo.log
└── .idea/                               PyCharm project + run configuration
```

## Usage

```
./install_odoo19.sh
```

Useful overrides (env vars, all optional):

| Variable              | Default                                | Meaning |
|------------------------|------------------------------------------|---------|
| `ODOO_ROOT`            | `~/Odoo19`                              | project folder |
| `ODOO_BRANCH`          | `19.0`                                  | branch for both repos |
| `VERSION_SHORT`        | `19`                                    | used in folder/clone names |
| `COMMUNITY_REPO`       | `https://github.com/odoo/odoo.git`      | community remote |
| `ENTERPRISE_REPO`      | `git@github.com:odoo/enterprise.git`    | enterprise remote (set to a token URL if not using SSH) |
| `ODOO_DB`              | `<your-username>_odoo19`                | database name (prefixed to avoid clashing with other devs on a shared machine) |
| `ODOO_HTTP_PORT`       | `8069`                                  | HTTP port |
| `ODOO_MASTER_PASSWORD` | random (generated with `openssl rand`)  | `admin_passwd` in odoo.conf — printed at the end |
| `ODOO_APPS`            | `sale,project,helpdesk,hr_timesheet`    | apps installed on first run |
| `CLONE_DEPTH`          | `1`                                     | shallow clone depth; `0` = full history |
| `SKIP_APT`             | `0`                                     | `1` to skip system package install |
| `SKIP_DB`              | `0`                                     | `1` to skip database creation |

The script is safe to re-run: it reuses existing clones (fetching the latest
`19.0`), reuses the venv, and skips database init if the database already
exists.

If enterprise access isn't set up yet, the script still finishes: it
installs everything else and skips Helpdesk (enterprise-only) with a
warning. Rerun it later once access is granted to pick up where it left off.

## After it finishes

Open `$ODOO_ROOT` (default `~/Odoo19`) as a PyCharm project. The interpreter
and the **"Odoo 19 (odoo-bin)"** run/debug configuration are already wired up
— just hit Run or Debug. Or start it by hand:

```
~/Odoo19/venv/bin/python ~/Odoo19/Odoo19/repo_odoo_community_19/odoo-bin -c ~/Odoo19/Config/odoo.conf
```

Then open http://localhost:8069. The master password printed at the end of
the script is needed the first time you create/manage a database.
