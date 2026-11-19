-- =====================================================================
-- Skill CI/CD - 01. One-time setup (ACCOUNTADMIN)
-- Schemas, roles, grants, source stage and the role procedure the pipeline calls.
-- =====================================================================
USE ROLE ACCOUNTADMIN;

-- 1. Database, schemas, stages
CREATE DATABASE IF NOT EXISTS <% db %>;
CREATE SCHEMA IF NOT EXISTS <% db %>.<% dev_schema %>  COMMENT = 'Skills - DEV';
CREATE SCHEMA IF NOT EXISTS <% db %>.<% prd_schema %>  COMMENT = 'Skills - PRD';
CREATE SCHEMA IF NOT EXISTS <% db %>.<% cicd_schema %> COMMENT = 'Skills - CI/CD pipeline';
-- SKILL_SRC: GitHub Actions uploads skills/ here (<branch>/skills/<skill>/...). SSE = stable md5.
CREATE STAGE IF NOT EXISTS <% db %>.<% cicd_schema %>.SKILL_SRC ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE');
-- SEED: used only for the first CREATE of each skill
CREATE STAGE IF NOT EXISTS <% db %>.<% cicd_schema %>.SEED;

-- 2. Pipeline role: deploys and owns the skills
CREATE ROLE IF NOT EXISTS <% cicd_role %>;
GRANT ROLE <% cicd_role %> TO ROLE SYSADMIN;
GRANT USAGE ON WAREHOUSE <% warehouse %>                    TO ROLE <% cicd_role %>;
GRANT USAGE ON DATABASE  <% db %>                           TO ROLE <% cicd_role %>;
GRANT USAGE ON SCHEMA    <% db %>.<% cicd_schema %>         TO ROLE <% cicd_role %>;
GRANT USAGE ON SCHEMA    <% db %>.<% dev_schema %>          TO ROLE <% cicd_role %>;
GRANT USAGE ON SCHEMA    <% db %>.<% prd_schema %>          TO ROLE <% cicd_role %>;
GRANT CREATE CORTEX EXTENSION ON SCHEMA <% db %>.<% dev_schema %> TO ROLE <% cicd_role %>;
GRANT CREATE CORTEX EXTENSION ON SCHEMA <% db %>.<% prd_schema %> TO ROLE <% cicd_role %>;
GRANT CREATE TABLE, CREATE PROCEDURE, CREATE FILE FORMAT
  ON SCHEMA <% db %>.<% cicd_schema %> TO ROLE <% cicd_role %>;
GRANT READ, WRITE ON STAGE <% db %>.<% cicd_schema %>.SEED      TO ROLE <% cicd_role %>;
GRANT READ, WRITE ON STAGE <% db %>.<% cicd_schema %>.SKILL_SRC TO ROLE <% cicd_role %>;
GRANT APPLY TAG ON ACCOUNT TO ROLE <% cicd_role %>;   -- certification tag on PRD
GRANT ROLE <% cicd_role %> TO USER <% svc_user_dev %>;
GRANT ROLE <% cicd_role %> TO USER <% svc_user_prd %>;

-- 3. Generic consumer roles
CREATE ROLE IF NOT EXISTS <% dev_role %>;
CREATE ROLE IF NOT EXISTS <% users_role %>;
GRANT USAGE ON DATABASE <% db %>                  TO ROLE <% dev_role %>;
GRANT USAGE ON SCHEMA   <% db %>.<% dev_schema %> TO ROLE <% dev_role %>;
GRANT USAGE ON DATABASE <% db %>                  TO ROLE <% users_role %>;
GRANT USAGE ON SCHEMA   <% db %>.<% prd_schema %> TO ROLE <% users_role %>;

-- 4. Per-skill roles. Owner's rights (owned by ACCOUNTADMIN) so the pipeline can call it without
--    holding CREATE ROLE itself. The name is validated: kebab-case only, fixed suffixes.
CREATE OR REPLACE PROCEDURE <% db %>.<% cicd_schema %>.SP_SKILL_CREATE_ROLES(P_SKILL STRING)
RETURNS STRING
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
DECLARE
  v_base  STRING;
  v_users STRING;
  v_dev   STRING;
  v_sql   STRING;
BEGIN
  IF (NOT REGEXP_LIKE(P_SKILL, '^[a-z0-9]+(-[a-z0-9]+)*$')) THEN
    RETURN 'Invalid skill name: ' || P_SKILL;
  END IF;
  v_base  := REGEXP_REPLACE(UPPER(REPLACE(P_SKILL, '-', '_')), '_SKILL$', '');
  v_users := v_base || '_SKILL_USERS';
  v_dev   := v_base || '_SKILL_DEV';

  v_sql := 'CREATE ROLE IF NOT EXISTS ' || v_users || ' COMMENT = ''Skill ' || P_SKILL || ' - PRD users''';
  EXECUTE IMMEDIATE :v_sql;
  v_sql := 'CREATE ROLE IF NOT EXISTS ' || v_dev || ' COMMENT = ''Skill ' || P_SKILL || ' - DEV''';
  EXECUTE IMMEDIATE :v_sql;
  v_sql := 'GRANT USAGE ON DATABASE <% db %> TO ROLE ' || v_users;                 EXECUTE IMMEDIATE :v_sql;
  v_sql := 'GRANT USAGE ON SCHEMA <% db %>.<% prd_schema %> TO ROLE ' || v_users;  EXECUTE IMMEDIATE :v_sql;
  v_sql := 'GRANT USAGE ON DATABASE <% db %> TO ROLE ' || v_dev;                   EXECUTE IMMEDIATE :v_sql;
  v_sql := 'GRANT USAGE ON SCHEMA <% db %>.<% dev_schema %> TO ROLE ' || v_dev;    EXECUTE IMMEDIATE :v_sql;
  v_sql := 'GRANT ROLE ' || v_users || ' TO ROLE <% users_role %>';                EXECUTE IMMEDIATE :v_sql;
  v_sql := 'GRANT ROLE ' || v_dev   || ' TO ROLE <% dev_role %>';                  EXECUTE IMMEDIATE :v_sql;
  RETURN 'Roles ready: ' || v_users || ' -> <% users_role %>, ' || v_dev || ' -> <% dev_role %>';
END;
$$;
GRANT USAGE ON PROCEDURE <% db %>.<% cicd_schema %>.SP_SKILL_CREATE_ROLES(STRING) TO ROLE <% cicd_role %>;
GRANT USAGE ON PROCEDURE <% db %>.<% cicd_schema %>.SP_SKILL_CREATE_ROLES(STRING) TO ROLE SECURITYADMIN;
