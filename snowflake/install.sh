#!/usr/bin/env bash
# One-time platform setup for one environment.
#   ./install.sh <snow-connection> <dev|prd>
# Uses config.<env>.env. Idempotent.
set -euo pipefail
cd "$(dirname "$0")"
conn=${1:?usage: install.sh <snow-connection> <dev|prd>}
env=${2:?usage: install.sh <snow-connection> <dev|prd>}
cfg="config.${env}.env"
[[ -f $cfg ]] || { echo "missing $cfg"; exit 1; }

# config -> -D key=value for snow templating (identifiers are validated: letters, digits, _ . : / @ -)
vars=()
while IFS='=' read -r k v; do
  [[ -z $k || $k == \#* ]] && continue
  [[ $v =~ ^[A-Za-z0-9_.:/@-]*$ ]] || { echo "invalid value for $k: $v"; exit 1; }
  vars+=(-D "$k=$v")
done < "$cfg"

echo "== 01_platform.sql ($env)"
snow sql -c "$conn" --enable-templating STANDARD -f 01_platform.sql "${vars[@]}"
echo "== done. Next: ./onboard_team.sh $conn $env <TEAM> <owner|caller> <DATA_DB.DATA_SCHEMA>"
