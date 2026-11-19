-- =====================================================================
-- Streamlit CI/CD - 02. Onboard ONE team in ONE environment (ACCOUNTADMIN)
-- Run with: ./onboard_team.sh <snow-connection> <dev|prd> <TEAM>
-- Then 02a (owner's rights) or 02b (restricted caller's rights) gives the data access.
-- =====================================================================
USE ROLE ACCOUNTADMIN;

-- 1. Team schema + source stage (server-side encryption: stable file md5 for change detection)
CREATE SCHEMA IF NOT EXISTS <% env_db %>.<% team %> COMMENT = 'Streamlit apps of team <% team %>';
CREATE STAGE IF NOT EXISTS <% env_db %>.<% team %>.APP_SRC
  ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE')
  COMMENT = 'App source files uploaded by the CI/CD (one folder per app and commit)';

-- 2. Roles
--    OWNER: technical role, only the CI/CD uses it. It creates and owns the team's apps.
--    USERS: people who open the team's apps (grant it to functional roles or users).
CREATE ROLE IF NOT EXISTS <% owner_role %> COMMENT = 'Owner of the <% team %> Streamlit apps (<% env %>) - CI/CD only';
CREATE ROLE IF NOT EXISTS <% users_role %> COMMENT = 'Can open the <% team %> Streamlit apps (<% env %>)';
GRANT ROLE <% owner_role %> TO ROLE <% cicd_role %>;
GRANT ROLE <% users_role %> TO ROLE SYSADMIN;

-- 3. Compute: one compute pool per team (cost visible per team); reuse the team warehouse
CREATE COMPUTE POOL IF NOT EXISTS <% pool %>
  MIN_NODES = 1 MAX_NODES = <% max_nodes %>
  INSTANCE_FAMILY = <% instance_family %>
  AUTO_SUSPEND_SECS = 300 AUTO_RESUME = TRUE INITIALLY_SUSPENDED = TRUE
  COMMENT = 'Streamlit apps of team <% team %> (<% env %>)';
ALTER COMPUTE POOL <% pool %> SET MAX_NODES = <% max_nodes %>;
CREATE WAREHOUSE IF NOT EXISTS <% warehouse %>
  WAREHOUSE_SIZE = XSMALL AUTO_SUSPEND = 60 AUTO_RESUME = TRUE INITIALLY_SUSPENDED = TRUE
  COMMENT = 'Team <% team %> warehouse (reused by its Streamlit apps)';
ALTER COMPUTE POOL <% pool %> SET TAG <% admin_db %>.GOVERNANCE.TEAM = '<% team %>';
ALTER WAREHOUSE <% warehouse %> SET TAG <% admin_db %>.GOVERNANCE.TEAM = '<% team %>';

-- 4. Owner role: everything needed to create the app, nothing more
GRANT USAGE ON DATABASE <% env_db %> TO ROLE <% owner_role %>;
GRANT USAGE ON SCHEMA <% env_db %>.<% team %> TO ROLE <% owner_role %>;
GRANT CREATE STREAMLIT ON SCHEMA <% env_db %>.<% team %> TO ROLE <% owner_role %>;
GRANT READ, WRITE ON STAGE <% env_db %>.<% team %>.APP_SRC TO ROLE <% owner_role %>;
GRANT USAGE ON COMPUTE POOL <% pool %> TO ROLE <% owner_role %>;
GRANT USAGE ON WAREHOUSE <% warehouse %> TO ROLE <% owner_role %>;
GRANT USAGE ON INTEGRATION <% pypi_eai %> TO ROLE <% owner_role %>;

-- 5. Users role: open every current and future app of the team
GRANT USAGE ON DATABASE <% env_db %> TO ROLE <% users_role %>;
GRANT USAGE ON SCHEMA <% env_db %>.<% team %> TO ROLE <% users_role %>;
GRANT USAGE ON FUTURE STREAMLITS IN SCHEMA <% env_db %>.<% team %> TO ROLE <% users_role %>;
