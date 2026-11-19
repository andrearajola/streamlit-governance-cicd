-- =====================================================================
-- Skill CI/CD - 03. Deploy pipeline (runs as the pipeline role)  [adapted from SEAT]
--   <dev branch> -> <db>.<dev schema>.<SKILL>  (READ to <SKILL>_SKILL_DEV, "[DEV] " description, hidden)
--   <prd branch> -> <db>.<prd schema>.<SKILL>  (READ to <SKILL>_SKILL_USERS, certified, email)
-- Source: GitHub Actions uploads skills/ to @<db>.<cicd schema>.SKILL_SRC/<branch>/skills/<skill>/
-- and calls SP_SKILL_SYNC_ALL('<branch>', '<commit>'). Only skills whose files changed get a new version.
-- The pipeline creates the per-skill roles itself (SP_SKILL_CREATE_ROLES).
-- Optional skills/<name>/cicd.yml: dev_reader, prd_reader (override the per-skill role), prd_enabled.
-- =====================================================================
USE ROLE <% cicd_role %>;
USE WAREHOUSE <% warehouse %>;

CREATE TABLE IF NOT EXISTS <% db %>.<% cicd_schema %>.SKILL_DEPLOY_STATE (
  RUN_TS      TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP(),
  SKILL       STRING,
  BRANCH      STRING,
  EXTENSION   STRING,
  COMMIT_HASH STRING,
  ALIAS       STRING,
  STATUS      STRING,      -- DEPLOYED / FAILED
  MESSAGE     STRING,
  FINGERPRINT STRING
);

CREATE FILE FORMAT IF NOT EXISTS <% db %>.<% cicd_schema %>.FF_SKILL_TEXT
  TYPE = CSV FIELD_DELIMITER = NONE RECORD_DELIMITER = '\n'
  ESCAPE_UNENCLOSED_FIELD = NONE FIELD_OPTIONALLY_ENCLOSED_BY = NONE;

CREATE OR REPLACE PROCEDURE <% db %>.<% cicd_schema %>.SP_SKILL_SYNC(P_SKILL STRING, P_BRANCH STRING, P_COMMIT STRING)
RETURNS STRING
LANGUAGE SQL
EXECUTE AS CALLER   -- LIST is not allowed in owner's rights; the workflow runs as the pipeline role
AS
$$
DECLARE
  v_name    STRING;
  v_schema  STRING;
  v_reader  STRING;
  v_disc    STRING;
  v_prd     BOOLEAN;
  v_pfx     STRING;
  v_ext     STRING;
  v_last    STRING;
  v_alias   STRING;
  v_src     STRING;
  v_sql     STRING;
  v_ok      INTEGER;
  v_desc    STRING;
  v_exists  INTEGER;
  v_open    BOOLEAN DEFAULT FALSE;
  v_status  STRING;
  v_msg     STRING;
  v_fp      STRING;
  v_nfiles  INTEGER;
  v_hascfg  INTEGER;
  v_cfg_dev STRING;
  v_cfg_prd STRING;
  v_cfg_on  STRING;
  v_base    STRING;
  v_nrole   INTEGER;
  v_roles   STRING;
BEGIN
  -- Inputs end up in identifiers and paths: validate them
  IF (NOT REGEXP_LIKE(P_SKILL, '^[a-z0-9]+(-[a-z0-9]+)*$')) THEN
    RETURN 'Invalid skill name: ' || P_SKILL;
  END IF;
  IF (NOT REGEXP_LIKE(P_COMMIT, '^[0-9a-f]{7,40}$')) THEN
    RETURN 'Invalid commit: ' || P_COMMIT;
  END IF;
  IF (P_BRANCH = '<% dev_branch %>') THEN
    v_schema := '<% db %>.<% dev_schema %>'; v_prd := FALSE; v_disc := 'FALSE'; v_pfx := '[DEV] ';
  ELSEIF (P_BRANCH = '<% prd_branch %>') THEN
    v_schema := '<% db %>.<% prd_schema %>'; v_prd := TRUE;  v_disc := 'TRUE';  v_pfx := '';
  ELSE
    RETURN 'Branch not deployed: ' || P_BRANCH;
  END IF;

  v_name := UPPER(REPLACE(P_SKILL, '-', '_'));
  v_base := REGEXP_REPLACE(v_name, '_SKILL$', '');
  v_reader := v_base || IFF(v_prd, '_SKILL_USERS', '_SKILL_DEV');
  v_ext := v_schema || '.' || v_name;
  v_src := '@<% db %>.<% cicd_schema %>.SKILL_SRC/' || P_BRANCH || '/skills/' || P_SKILL || '/';

  BEGIN
    -- Fingerprint of this skill's folder only (md5 is stable: the stage uses server-side encryption)
    v_sql := 'LIST ' || v_src;
    EXECUTE IMMEDIATE :v_sql;
    SELECT COUNT(*), MD5(LISTAGG(REGEXP_SUBSTR("name", 'skills/.*$') || ':' || "md5", ',') WITHIN GROUP (ORDER BY "name")),
           COUNT_IF(ENDSWITH("name", '/' || :P_SKILL || '/cicd.yml'))
      INTO :v_nfiles, :v_fp, :v_hascfg
      FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
    SELECT MAX_BY(FINGERPRINT, RUN_TS) INTO :v_last
      FROM <% db %>.<% cicd_schema %>.SKILL_DEPLOY_STATE
      WHERE SKILL = :P_SKILL AND BRANCH = :P_BRANCH;

    IF (v_nfiles > 0 AND v_hascfg > 0) THEN
      v_sql := 'SELECT MAX(IFF(k = ''dev_reader'', v, NULL)), MAX(IFF(k = ''prd_reader'', v, NULL)), MAX(IFF(k = ''prd_enabled'', LOWER(v), NULL)) ' ||
               'FROM (SELECT TRIM(SPLIT_PART($1, '':'', 1)) k, TRIM(SPLIT_PART($1, '':'', 2), '' "'''''') v ' ||
               'FROM ' || v_src || 'cicd.yml (FILE_FORMAT => ''<% db %>.<% cicd_schema %>.FF_SKILL_TEXT''))';
      EXECUTE IMMEDIATE :v_sql;
      SELECT $1, $2, $3 INTO :v_cfg_dev, :v_cfg_prd, :v_cfg_on FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
      IF (NOT v_prd AND REGEXP_LIKE(v_cfg_dev, '^[A-Za-z_][A-Za-z0-9_]*$')) THEN v_reader := v_cfg_dev; END IF;
      IF (v_prd AND REGEXP_LIKE(v_cfg_prd, '^[A-Za-z_][A-Za-z0-9_]*$')) THEN v_reader := v_cfg_prd; END IF;
    END IF;

    IF (v_nfiles = 0) THEN
      v_status := 'SKIP'; v_msg := 'skill not on this branch';
    ELSEIF (v_prd AND v_cfg_on = 'false') THEN
      v_status := 'SKIP'; v_msg := 'prd_enabled: false';
    ELSEIF (v_last = v_fp) THEN
      v_status := 'SKIP'; v_msg := 'unchanged since last run';
    ELSE
      -- RBAC from the CI/CD: per-skill roles (idempotent; owner's-rights procedure)
      CALL <% db %>.<% cicd_schema %>.SP_SKILL_CREATE_ROLES(:P_SKILL) INTO :v_roles;
      v_sql := 'SHOW ROLES LIKE ''' || v_reader || '''';
      EXECUTE IMMEDIATE :v_sql;
      SELECT COUNT(*) INTO :v_nrole FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
      v_alias := 'G' || UPPER(LEFT(P_COMMIT, 7));

      -- SKILL.md exists and its front-matter has name + description
      v_sql := 'SELECT COUNT_IF(STARTSWITH(TRIM($1), ''name:'')) * COUNT_IF(STARTSWITH(TRIM($1), ''description:'')), ' ||
               'MIN(IFF(STARTSWITH(TRIM($1), ''description:''), TRIM(SUBSTR(TRIM($1), 13), '' "''''''), NULL)) ' ||
               'FROM ' || v_src || 'SKILL.md (FILE_FORMAT => ''<% db %>.<% cicd_schema %>.FF_SKILL_TEXT'')';
      EXECUTE IMMEDIATE :v_sql;
      SELECT $1, LEFT(REPLACE($2, '''', ''''''), 1024) INTO :v_ok, :v_desc FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
      IF (COALESCE(v_desc, '') = '') THEN v_ok := 0; ELSE v_desc := LEFT(v_pfx || v_desc, 1024); END IF;

      IF (v_nrole = 0) THEN
        v_status := 'FAILED'; v_msg := 'reader role ' || v_reader || ' not found (cicd.yml override?)';
      ELSEIF (COALESCE(v_ok, 0) = 0) THEN
        v_status := 'FAILED'; v_msg := 'SKILL.md missing name or description';
      ELSE
        v_sql := 'SHOW CORTEX EXTENSIONS LIKE ''' || v_name || ''' IN SCHEMA ' || v_schema;
        EXECUTE IMMEDIATE :v_sql;
        SELECT COUNT(*) INTO :v_exists FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

        IF (v_exists = 0) THEN
          -- Day 1: create the extension (root must contain only skills/<skill>/ -> SEED stage)
          v_sql := 'COPY FILES INTO @<% db %>.<% cicd_schema %>.SEED/' || v_alias || '/skills/' || P_SKILL || '/ FROM ' || v_src;
          EXECUTE IMMEDIATE :v_sql;
          v_sql := 'CREATE CORTEX EXTENSION ' || v_ext || ' FROM ''@<% db %>.<% cicd_schema %>.SEED/' || v_alias || '/''';
          EXECUTE IMMEDIATE :v_sql;
          v_sql := 'ALTER CORTEX EXTENSION ' || v_ext || ' SET COMMENT = ''' || v_desc || '''';
          EXECUTE IMMEDIATE :v_sql;
          v_sql := 'ALTER CORTEX EXTENSION ' || v_ext || ' SET DISCOVERABLE = ' || v_disc;
          EXECUTE IMMEDIATE :v_sql;
          v_status := 'DEPLOYED'; v_msg := 'created';
        ELSE
          v_sql := 'SHOW VERSIONS IN CORTEX EXTENSION ' || v_ext;
          EXECUTE IMMEDIATE :v_sql;
          SELECT COUNT(*) INTO :v_exists FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())) WHERE "alias" = :v_alias;
          IF (v_exists > 0) THEN
            v_status := 'DEPLOYED'; v_msg := 'already present';
          ELSE
            v_sql := 'ALTER CORTEX EXTENSION ' || v_ext || ' ADD LIVE VERSION ' || v_alias || ' FROM LAST';
            EXECUTE IMMEDIATE :v_sql;
            v_open := TRUE;
            -- Replace the files: a file deleted in git disappears from the skill
            v_sql := 'REMOVE ''snow://cortex_extension/' || v_ext || '/versions/live/skills/' || P_SKILL || '/''';
            EXECUTE IMMEDIATE :v_sql;
            v_sql := 'COPY FILES INTO ''snow://cortex_extension/' || v_ext || '/versions/live/skills/' || P_SKILL || '/'' FROM ''' || v_src || '''';
            EXECUTE IMMEDIATE :v_sql;
            v_sql := 'ALTER CORTEX EXTENSION ' || v_ext || ' COMMIT DESCRIPTION = ''' || v_desc || '''';
            EXECUTE IMMEDIATE :v_sql;
            v_open := FALSE;
            v_sql := 'ALTER CORTEX EXTENSION ' || v_ext || ' SET COMMENT = ''' || v_desc || '''';
            EXECUTE IMMEDIATE :v_sql;
            v_status := 'DEPLOYED'; v_msg := 'new version';
          END IF;
        END IF;
        -- Reader grant every time (idempotent): also repairs a grant removed by hand
        v_sql := 'GRANT READ ON CORTEX EXTENSION ' || v_ext || ' TO ROLE ' || v_reader;
        EXECUTE IMMEDIATE :v_sql;

        IF (v_prd AND v_msg IN ('created', 'new version')) THEN
          IF (v_msg = 'new version') THEN
            v_sql := 'ALTER CORTEX EXTENSION ' || v_ext || ' VERSION ' || v_alias ||
                     ' SET TAG snowflake.core.certification_status = ''CERTIFIED''';
          ELSE
            v_sql := 'ALTER CORTEX EXTENSION ' || v_ext ||
                     ' SET TAG snowflake.core.certification_status = ''CERTIFIED''';
            EXECUTE IMMEDIATE :v_sql;
            v_sql := 'ALTER CORTEX EXTENSION ' || v_ext || ' VERSION VERSION$1' ||
                     ' SET TAG snowflake.core.certification_status = ''CERTIFIED''';
          END IF;
          EXECUTE IMMEDIATE :v_sql;
          v_desc := REPLACE(v_desc, '''''', '''');
          CALL <% db %>.<% cicd_schema %>.SP_SKILL_NOTIFY_RELEASE(:v_ext, :P_SKILL, :v_desc, :P_COMMIT,
            'Deployed from branch <% prd_branch %> by GitHub Actions', :v_reader) INTO :v_roles;
          v_msg := v_msg || ', certified, notified (' || v_roles || ')';
        END IF;
      END IF;
    END IF;

  EXCEPTION
    WHEN OTHER THEN
      v_status := 'FAILED'; v_msg := SQLERRM;
      IF (v_open) THEN
        v_sql := 'ALTER CORTEX EXTENSION ' || v_ext || ' ABORT';
        EXECUTE IMMEDIATE :v_sql;
      END IF;
  END;

  IF (v_status <> 'SKIP') THEN
    INSERT INTO <% db %>.<% cicd_schema %>.SKILL_DEPLOY_STATE (SKILL, BRANCH, EXTENSION, COMMIT_HASH, ALIAS, STATUS, MESSAGE, FINGERPRINT)
      VALUES (:P_SKILL, :P_BRANCH, :v_ext, :P_COMMIT, :v_alias, :v_status, :v_msg, :v_fp);
  END IF;
  RETURN P_BRANCH || ': ' || COALESCE(v_alias || ' ', '') || v_status || ' (' || v_msg || ')';
END;
$$;

-- All skills uploaded for one branch
CREATE OR REPLACE PROCEDURE <% db %>.<% cicd_schema %>.SP_SKILL_SYNC_ALL(P_BRANCH STRING, P_COMMIT STRING)
RETURNS STRING
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
  v_r    STRING;
  v_s    STRING;
  v_sql  STRING;
  v_out  STRING DEFAULT '';
  skills RESULTSET;
BEGIN
  IF (P_BRANCH NOT IN ('<% dev_branch %>', '<% prd_branch %>')) THEN
    RETURN 'Branch not deployed: ' || P_BRANCH;
  END IF;
  v_sql := 'LIST @<% db %>.<% cicd_schema %>.SKILL_SRC/' || P_BRANCH || '/skills/ PATTERN = ''.*/[a-z0-9-]+/SKILL[.]md''';
  EXECUTE IMMEDIATE :v_sql;
  skills := (SELECT DISTINCT REGEXP_SUBSTR("name", 'skills/([a-z0-9-]+)/SKILL[.]md$', 1, 1, 'e', 1) AS SKILL
             FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())) WHERE SKILL IS NOT NULL ORDER BY 1);
  FOR s IN skills DO
    v_r := NULL; v_s := s.SKILL;
    CALL <% db %>.<% cicd_schema %>.SP_SKILL_SYNC(:v_s, :P_BRANCH, :P_COMMIT) INTO :v_r;
    v_out := v_out || v_s || ' => ' || COALESCE(v_r, 'no result') || CHR(10);
  END FOR;
  RETURN COALESCE(NULLIF(v_out, ''), 'no skills found for ' || P_BRANCH);
END;
$$;
