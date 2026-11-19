#!/usr/bin/env python3
"""Upload skills/ to the skill stage for one branch and run the Snowflake skill sync.

  sync_skills.py --branch dev|main --commit <sha> [--schema DB_COCO_SKILLS.SKILLS_CICD]

Runs as the SKILL_CICD role. Same connection rules as deploy_app.py (SNOW_CONN_ARGS, default -x).
Exit 1 if any skill FAILED.
"""
from __future__ import annotations

import argparse
import os
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from deploy_app import Snow, sql_str  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--branch", required=True, choices=["dev", "main"])
    ap.add_argument("--commit", required=True)
    ap.add_argument("--schema", default=os.environ.get("SKILLS_CICD_SCHEMA", "DB_COCO_SKILLS.SKILLS_CICD"))
    ap.add_argument("--role", default="SKILL_CICD")
    ap.add_argument("--warehouse", default="COMPUTE_WH")
    a = ap.parse_args()
    if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*", a.schema):
        sys.exit(f"invalid schema {a.schema}")
    if not re.fullmatch(r"[0-9a-f]{7,40}", a.commit):
        sys.exit(f"invalid commit {a.commit}")

    snow = Snow(a.role, a.warehouse)
    stage = f"@{a.schema}.SKILL_SRC/{a.branch}"
    skills_dir = ROOT / "skills"
    files = [p for p in sorted(skills_dir.rglob("*")) if p.is_file() and "__pycache__" not in p.parts]
    stmts = [f"REMOVE {stage}/;"]  # deleted files in git must disappear from the stage
    for p in files:
        rel = p.parent.relative_to(ROOT).as_posix()
        stmts.append(f"PUT {sql_str('file://' + p.as_posix())} {stage}/{rel}/ AUTO_COMPRESS=FALSE OVERWRITE=TRUE;")
    snow.run("\n".join(stmts))
    print(f"uploaded {len(files)} files to {stage}")

    rows = snow.run(f"CALL {a.schema}.SP_SKILL_SYNC_ALL({sql_str(a.branch)}, {sql_str(a.commit)});")
    out = next(iter(rows[0].values())) if rows else "no result"
    print(out)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as f:
            f.write(f"### Skill sync ({a.branch} @ {a.commit[:7]})\n```\n{out}\n```\n")
    return 1 if "FAILED" in out else 0


if __name__ == "__main__":
    sys.exit(main())
