#!/usr/bin/env bash
# Skill CI/CD one-time setup. Usage: ./install.sh <snow-connection>
# Runs 01 (ACCOUNTADMIN), 02 (ACCOUNTADMIN), 03 (pipeline role). Idempotent.
set -euo pipefail
cd "$(dirname "$0")"
conn=${1:?usage: install.sh <snow-connection>}
vars=()
while IFS= read -r line; do
  [[ -z $line || $line == \#* ]] && continue
  k=${line%%=*}; v=${line#*=}; v=${v%%#*}; v=$(sed 's/[[:space:]]*$//' <<<"$v")
  vars+=(-D "$k=$v")
done < config.env
for f in 01_setup.sql 02_notify.sql 03_pipeline.sql; do
  echo "== $f"
  snow sql -c "$conn" --enable-templating STANDARD -f "$f" "${vars[@]}"
done
