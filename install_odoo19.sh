#!/usr/bin/env bash
#
# install_odoo19.sh — set up an Odoo 19 Enterprise dev environment from source,
# following the team's folder convention (Config / Enterprise / Odoo19 / Servers).
#
# Creates, by default, in ~/Odoo19:
#   Config/                 odoo.conf
#   Enterprise/
#     repo_odoo_enterprise_19/   odoo/enterprise, branch 19.0
#   Odoo19/
#     repo_odoo_community_19/    odoo/odoo, branch 19.0
#   Servers/                 empty — client-specific custom addons go here
#   venv/                    Python virtualenv with all deps
#   data/                    filestore / sessions
#   logs/                    odoo.log
#   .idea/                   PyCharm project + "Odoo 19 (odoo-bin)" run configuration
#
# Usage:
#   ./install_odoo19.sh                        # everything, defaults below
#   ENTERPRISE_REPO='https://<TOKEN>@github.com/odoo/enterprise' ./install_odoo19.sh
#   ODOO_ROOT=~/dev/Odoo19 ./install_odoo19.sh
#   SKIP_APT=1 ./install_odoo19.sh             # system packages already installed
#   SKIP_DB=1 ./install_odoo19.sh              # skip database creation / module install
#
# Prerequisites you get from whoever manages repo access on your team, before
# running this:
#   - Your GitHub account added as a collaborator on odoo/enterprise (private repo)
#   - Either an SSH key loaded for that account (default below), or a GitHub PAT —
#     set ENTERPRISE_REPO to https://<TOKEN>@github.com/odoo/enterprise in that case.
#     (The script strips the token out of the stored git remote right after cloning,
#     so it doesn't sit in plain text in .git/config afterwards.)
#
set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration (override any of these via environment variables)
# ---------------------------------------------------------------------------
ODOO_BRANCH="${ODOO_BRANCH:-19.0}"
VERSION_SHORT="${VERSION_SHORT:-19}"

ROOT_DIR="${ODOO_ROOT:-$HOME/Odoo${VERSION_SHORT}}"
CONFIG_DIR="$ROOT_DIR/Config"
ENTERPRISE_PARENT_DIR="$ROOT_DIR/Enterprise"
COMMUNITY_PARENT_DIR="$ROOT_DIR/Odoo${VERSION_SHORT}"
SERVERS_DIR="$ROOT_DIR/Servers"
VENV_DIR="$ROOT_DIR/venv"
DATA_DIR="$ROOT_DIR/data"
LOGS_DIR="$ROOT_DIR/logs"
CONF_FILE="$CONFIG_DIR/odoo.conf"

COMMUNITY_DIR="$COMMUNITY_PARENT_DIR/repo_odoo_community_${VERSION_SHORT}"
ENTERPRISE_DIR="$ENTERPRISE_PARENT_DIR/repo_odoo_enterprise_${VERSION_SHORT}"

COMMUNITY_REPO="${COMMUNITY_REPO:-https://github.com/odoo/odoo.git}"
ENTERPRISE_REPO="${ENTERPRISE_REPO:-git@github.com:odoo/enterprise.git}"

PG_ROLE="$(whoami)"
DB_NAME="${ODOO_DB:-${PG_ROLE}_odoo${VERSION_SHORT}}"
HTTP_PORT="${ODOO_HTTP_PORT:-8069}"
MASTER_PASSWORD="${ODOO_MASTER_PASSWORD:-$(openssl rand -hex 12)}"
APPS="${ODOO_APPS:-sale,project,helpdesk,hr_timesheet}"
CLONE_DEPTH="${CLONE_DEPTH:-1}"          # set to 0 for a full (unshallowed) clone
SKIP_APT="${SKIP_APT:-0}"
SKIP_DB="${SKIP_DB:-0}"

log()  { printf '\033[1;32m==>\033[0m %s\n' "$1"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$1" >&2; }
err()  { printf '\033[1;31mERROR\033[0m %s\n' "$1" >&2; }

# ---------------------------------------------------------------------------
# 1. System packages
# ---------------------------------------------------------------------------
install_system_packages() {
  if [ "$SKIP_APT" = "1" ]; then
    log "SKIP_APT=1, skipping system package installation"
    return
  fi
  log "Installing system packages (sudo password may be requested)..."
  sudo apt-get update
  sudo apt-get install -y \
    git python3-pip python3-venv python3-dev build-essential \
    libxml2-dev libxslt1-dev libldap2-dev libsasl2-dev libssl-dev \
    libjpeg-dev libjpeg8-dev zlib1g-dev libpq-dev libffi-dev \
    fontconfig xfonts-75dpi xfonts-base wkhtmltopdf \
    postgresql postgresql-contrib

  if ! command -v node >/dev/null 2>&1; then
    warn "Node.js not found. Install it (e.g. via nodesource or nvm) before continuing."
  fi
  if command -v npm >/dev/null 2>&1; then
    sudo npm install -g rtlcss
  else
    warn "npm not found, skipping rtlcss install. Install Node/npm and rerun 'sudo npm install -g rtlcss'."
  fi
}

# ---------------------------------------------------------------------------
# 2. PostgreSQL role (peer auth over the local unix socket, no password)
# ---------------------------------------------------------------------------
setup_postgres_role() {
  log "Ensuring PostgreSQL role '$PG_ROLE' exists..."
  if sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$PG_ROLE'" | grep -q 1; then
    log "Role '$PG_ROLE' already exists"
  else
    sudo -u postgres createuser -d -R -S "$PG_ROLE"
    log "Created PostgreSQL role '$PG_ROLE' (createdb, not superuser)"
  fi
}

# ---------------------------------------------------------------------------
# 3. Folder layout
# ---------------------------------------------------------------------------
create_folders() {
  log "Creating folder structure under $ROOT_DIR..."
  mkdir -p "$CONFIG_DIR" "$ENTERPRISE_PARENT_DIR" "$COMMUNITY_PARENT_DIR" \
    "$SERVERS_DIR" "$DATA_DIR" "$LOGS_DIR"
}

# ---------------------------------------------------------------------------
# 4. Clone / update repos
# ---------------------------------------------------------------------------
clone_or_update() {
  local url="$1" dir="$2" label="$3"
  local depth_args=()
  if [ "$CLONE_DEPTH" != "0" ]; then
    depth_args=(--depth "$CLONE_DEPTH")
  fi

  if [ -d "$dir/.git" ]; then
    log "$label already cloned at $dir, fetching latest $ODOO_BRANCH..."
    git -C "$dir" fetch origin "$ODOO_BRANCH" "${depth_args[@]}"
    git -C "$dir" checkout "$ODOO_BRANCH"
    git -C "$dir" pull --ff-only origin "$ODOO_BRANCH" || true
  else
    log "Cloning $label ($url, branch $ODOO_BRANCH)..."
    if ! git clone --branch "$ODOO_BRANCH" --single-branch "${depth_args[@]}" "$url" "$dir"; then
      err "Could not clone $label from $url."
      if [ "$label" = "enterprise" ]; then
        err "This is almost always a permissions issue on the private odoo/enterprise repo."
        err "Ask whoever manages repo access to add your GitHub account as a collaborator,"
        err "and make sure your SSH key is loaded (ssh-add -l / ssh -T git@github.com), or"
        err "set ENTERPRISE_REPO to an https://<TOKEN>@github.com/odoo/enterprise URL if"
        err "you're using a PAT."
      fi
      return 1
    fi
    # If a token was embedded in the URL (https://<token>@github.com/...), strip it
    # from the stored remote right away so it doesn't sit in .git/config in plain text.
    # NOTE: must match only the https:// scheme with embedded credentials — the
    # default SSH URL (git@github.com:...) also contains the substring "@github.com"
    # and must NOT be rewritten, or a working SSH remote gets replaced with an HTTPS
    # one that has no stored credentials, breaking future `git pull`.
    if [ "$label" = "enterprise" ] && [[ "$url" == https://*@github.com/* ]]; then
      git -C "$dir" remote set-url origin "https://github.com/odoo/enterprise"
    fi
  fi
}

clone_repos() {
  clone_or_update "$COMMUNITY_REPO" "$COMMUNITY_DIR" "community"
  if ! clone_or_update "$ENTERPRISE_REPO" "$ENTERPRISE_DIR" "enterprise"; then
    warn "Continuing without enterprise. Helpdesk (enterprise-only) will not be installed."
    warn "Rerun this script once you have enterprise access to pick up where it left off."
    HAVE_ENTERPRISE=0
  else
    HAVE_ENTERPRISE=1
  fi
}

# ---------------------------------------------------------------------------
# 5. Python virtualenv
# ---------------------------------------------------------------------------
setup_venv() {
  if [ ! -d "$VENV_DIR" ]; then
    log "Creating virtualenv at $VENV_DIR..."
    python3 -m venv "$VENV_DIR"
  fi
  log "Installing Python dependencies (this can take a few minutes)..."
  "$VENV_DIR/bin/pip" install --upgrade pip wheel setuptools
  "$VENV_DIR/bin/pip" install -r "$COMMUNITY_DIR/requirements.txt"
  if [ -f "$ENTERPRISE_DIR/requirements.txt" ]; then
    "$VENV_DIR/bin/pip" install -r "$ENTERPRISE_DIR/requirements.txt"
  fi
}

# ---------------------------------------------------------------------------
# 6. odoo.conf
# ---------------------------------------------------------------------------
write_conf() {
  log "Writing $CONF_FILE..."

  local addons_path="$SERVERS_DIR,$COMMUNITY_DIR/addons,$COMMUNITY_DIR/odoo/addons"
  if [ "${HAVE_ENTERPRISE:-0}" = "1" ]; then
    addons_path="$SERVERS_DIR,$ENTERPRISE_DIR,$COMMUNITY_DIR/addons,$COMMUNITY_DIR/odoo/addons"
  fi

  # db_host/db_port/db_password are intentionally omitted: Odoo 19's config
  # parser casts db_port through int() when the key is present in the file
  # at all, so an empty value ("db_port =") raises ValueError instead of
  # falling back to peer auth over the local unix socket.
  cat > "$CONF_FILE" <<EOF
[options]
addons_path = $addons_path
data_dir = $DATA_DIR
logfile = $LOGS_DIR/odoo.log
admin_passwd = $MASTER_PASSWORD
http_port = $HTTP_PORT
db_user = $PG_ROLE
EOF
}

# ---------------------------------------------------------------------------
# 7. PyCharm project files
# ---------------------------------------------------------------------------
write_pycharm_config() {
  log "Writing PyCharm project + run configuration..."
  mkdir -p "$ROOT_DIR/.idea/runConfigurations"
  local module_name
  module_name="$(basename "$ROOT_DIR")"

  cat > "$ROOT_DIR/.idea/modules.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<project version="4">
  <component name="ProjectModuleManager">
    <modules>
      <module fileurl="file://\$PROJECT_DIR\$/.idea/${module_name}.iml" filepath="\$PROJECT_DIR\$/.idea/${module_name}.iml" />
    </modules>
  </component>
</project>
EOF

  cat > "$ROOT_DIR/.idea/${module_name}.iml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<module type="PYTHON_MODULE" version="4">
  <component name="NewModuleRootManager">
    <content url="file://\$MODULE_DIR\$">
      <excludeFolder url="file://\$MODULE_DIR\$/venv" />
      <excludeFolder url="file://\$MODULE_DIR\$/data" />
      <excludeFolder url="file://\$MODULE_DIR\$/logs" />
    </content>
    <orderEntry type="inheritedJdk" />
    <orderEntry type="sourceFolder" forTests="false" />
  </component>
</module>
EOF

  # No project-level SDK is registered here on purpose (that requires a global
  # jdk.table.xml entry PyCharm normally creates through its own UI). Instead the
  # run configuration below points SDK_HOME straight at the venv's python binary
  # with IS_MODULE_SDK=false, which PyCharm accepts directly without any manual
  # "Add Interpreter" step. Note there is deliberately NO "ENV_FILES" option here —
  # that field expects a text .env file; pointing it at a python binary (an easy
  # mistake in the UI) makes PyCharm try to parse the binary as text and crash
  # the debugger with "ValueError: embedded null byte".
  cat > "$ROOT_DIR/.idea/runConfigurations/Odoo_${VERSION_SHORT}__odoo_bin_.xml" <<EOF
<component name="ProjectRunConfigurationManager">
  <configuration default="false" name="Odoo ${VERSION_SHORT} (odoo-bin)" type="PythonConfigurationType" factoryName="Python" nameIsGenerated="false">
    <module name="${module_name}" />
    <option name="INTERPRETER_OPTIONS" value="" />
    <option name="PARENT_ENVS" value="true" />
    <envs>
      <env name="PYTHONUNBUFFERED" value="1" />
    </envs>
    <option name="SDK_HOME" value="\$PROJECT_DIR\$/venv/bin/python" />
    <option name="WORKING_DIRECTORY" value="\$PROJECT_DIR\$" />
    <option name="IS_MODULE_SDK" value="false" />
    <option name="ADD_CONTENT_ROOTS" value="true" />
    <option name="ADD_SOURCE_ROOTS" value="true" />
    <option name="SCRIPT_NAME" value="\$PROJECT_DIR\$/Odoo${VERSION_SHORT}/repo_odoo_community_${VERSION_SHORT}/odoo-bin" />
    <option name="PARAMETERS" value="-c \$PROJECT_DIR\$/Config/odoo.conf" />
    <option name="SHOW_COMMAND_LINE" value="false" />
    <option name="EMULATE_TERMINAL" value="false" />
    <option name="MODULE_MODE" value="false" />
    <option name="REDIRECT_INPUT" value="false" />
    <option name="INPUT_FILE" value="" />
    <method v="2" />
  </configuration>
</component>
EOF
}

# ---------------------------------------------------------------------------
# 8. Create the database and install the requested apps
# ---------------------------------------------------------------------------
init_database() {
  if [ "$SKIP_DB" = "1" ]; then
    log "SKIP_DB=1, skipping database creation"
    return
  fi

  local apps="$APPS"
  if [ "${HAVE_ENTERPRISE:-0}" != "1" ]; then
    apps="$(echo "$apps" | sed 's/,\?helpdesk,\?/,/' | sed 's/^,//;s/,$//')"
    warn "enterprise not available, installing without helpdesk: $apps"
  fi

  if psql -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'" | grep -q 1; then
    log "Database '$DB_NAME' already exists, skipping init (drop it manually to reinstall)"
    return
  fi

  log "Creating database '$DB_NAME' and installing: $apps ..."
  "$VENV_DIR/bin/python" "$COMMUNITY_DIR/odoo-bin" \
    -c "$CONF_FILE" \
    -d "$DB_NAME" \
    -i "$apps" \
    --stop-after-init
}

# ---------------------------------------------------------------------------
main() {
  log "Installing Odoo $ODOO_BRANCH Enterprise dev environment into $ROOT_DIR"
  create_folders
  install_system_packages
  setup_postgres_role
  clone_repos
  setup_venv
  write_conf
  write_pycharm_config
  init_database

  echo
  log "Done."
  cat <<EOF

Project folder : $ROOT_DIR   (open this in PyCharm)
Config file    : $CONF_FILE
Database       : $DB_NAME
URL            : http://localhost:$HTTP_PORT
Master password: $MASTER_PASSWORD   (save this somewhere — it's randomly generated)

Manual start (equivalent to the PyCharm run configuration):
  $VENV_DIR/bin/python $COMMUNITY_DIR/odoo-bin -c $CONF_FILE

In PyCharm: open $ROOT_DIR as a project, then Run/Debug the
"Odoo ${VERSION_SHORT} (odoo-bin)" configuration — the interpreter and script path
are already wired to the venv, no manual setup needed.
EOF
}

main "$@"
