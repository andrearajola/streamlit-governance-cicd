#!/usr/bin/env bash
# Onboard a team in one environment (admin, ACCOUNTADMIN):
#   ./onboard_team.sh <snow-connection> <dev|prd> <TEAM> <owner|caller> <DATA_DB.DATA_SCHEMA> [max_nodes]
# Creates schema, owner/users roles, compute pool, tags and the data access for the chosen model.
# The team must also exist in config/teams.yml (the CI/CD rejects unknown teams).
set -euo pipefail
cd "$(dirname "$0")"
usage="usage: onboard_team.sh <conn> <dev|prd> <TEAM> <owner|caller> <DATA_DB.DATA_SCHEMA> [max_nodes]"
conn=${1:?$usage}; env=${2:?$usage}; team=${3:?$usage}; rights=${4:?$usage}; data=${5:?$usage}
team=$(tr '[:lower:]' '[:upper:]' <<<"$team")
[[ $team =~ ^[A-Z][A-Z0-9_]{1,30}$ ]] || { echo "invalid team: $team"; exit 1; }
[[ $rights == owner || $rights == caller ]] || { echo "rights must be owner or caller"; exit 1; }
[[ $data =~ ^[A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*$ ]] || { echo "data must be DB.SCHEMA"; exit 1; }
cfg="config.${env}.env"; [[ -f $cfg ]] || { echo "missing $cfg"; exit 1; }

# shellcheck disable=SC1090
source "$cfg"
max_nodes=${6:-$max_nodes}
[[ $max_nodes =~ ^[0-9]+$ ]] || { echo "max_nodes must be a number"; exit 1; }

# Warehouse comes from config/teams.yml (same file the CI/CD reads)
warehouse=$(python3 - "$team" <<'PY'
import re, sys
team = sys.argv[1]
cur = None
for line in open("../config/teams.yml"):
    m = re.match(r"^([A-Z][A-Z0-9_]*):\s*$", line)
    if m:
        cur = m.group(1)
        continue
    m = re.match(r"^\s+warehouse:\s*([A-Za-z0-9_]+)", line)
    if m and cur == team:
        print(m.group(1))
PY
)
[[ -n $warehouse ]] || { echo "team $team (and its warehouse) not found in config/teams.yml"; exit 1; }

owner_role="${team}_STREAMLIT_OWNER${role_suffix}"
users_role="${team}_STREAMLIT_USERS${role_suffix}"
pool="${team}_STREAMLIT_POOL${role_suffix}"
vars=(-D "env=$env" -D "env_db=$env_db" -D "admin_db=$admin_db" -D "team=$team"
      -D "owner_role=$owner_role" -D "users_role=$users_role" -D "cicd_role=$cicd_role"
      -D "pool=$pool" -D "max_nodes=$max_nodes" -D "instance_family=$instance_family"
      -D "warehouse=$warehouse" -D "pypi_eai=$pypi_eai"
      -D "data_db=${data%%.*}" -D "data_schema=${data#*.}")

echo "== onboarding $team in $env ($rights's rights, data $data, pool $pool, warehouse $warehouse)"
snow sql -c "$conn" --enable-templating STANDARD -f 02_team.sql "${vars[@]}"
if [[ $rights == owner ]]; then
  snow sql -c "$conn" --enable-templating STANDARD -f 02a_team_owner_rights.sql "${vars[@]}"
else
  snow sql -c "$conn" --enable-templating STANDARD -f 02b_team_caller_rights.sql "${vars[@]}"
fi
echo "== done: grant $users_role to the functional roles that should open the apps"
