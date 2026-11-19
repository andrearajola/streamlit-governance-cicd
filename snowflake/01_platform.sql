-- =====================================================================
-- Streamlit CI/CD - 01. Platform setup for ONE environment (ACCOUNTADMIN)
-- Run with: ./install.sh <snow-connection> <dev|prd>
-- Idempotent: safe to run again.
-- =====================================================================
USE ROLE ACCOUNTADMIN;

-- 1. Shared governance objects (tag for cost visibility, PyPI access for container runtimes)
CREATE DATABASE IF NOT EXISTS <% admin_db %> COMMENT = 'Streamlit governance: tags, network rules, integrations';
CREATE SCHEMA IF NOT EXISTS <% admin_db %>.GOVERNANCE;
CREATE TAG IF NOT EXISTS <% admin_db %>.GOVERNANCE.TEAM COMMENT = 'Team that owns the object (cost and ownership reporting)';

CREATE NETWORK RULE IF NOT EXISTS <% admin_db %>.GOVERNANCE.PYPI_RULE
  MODE = EGRESS TYPE = HOST_PORT
  VALUE_LIST = ('pypi.org', 'pypi.python.org', 'pythonhosted.org', 'files.pythonhosted.org');
CREATE EXTERNAL ACCESS INTEGRATION IF NOT EXISTS <% pypi_eai %>
  ALLOWED_NETWORK_RULES = (<% admin_db %>.GOVERNANCE.PYPI_RULE)
  ENABLED = TRUE
  COMMENT = 'Container-runtime Streamlit apps: install packages from PyPI';

-- 2. Environment database: one schema per team is added by onboard_team.sh
CREATE DATABASE IF NOT EXISTS <% env_db %> COMMENT = 'Streamlit apps (<% env %>): one schema per team';

-- 3. Pipeline role. It owns nothing: it inherits every <TEAM>_STREAMLIT_OWNER role of this
--    environment and the deploy switches to the team owner role (ownership can't be transferred).
CREATE ROLE IF NOT EXISTS <% cicd_role %> COMMENT = 'Streamlit CI/CD (<% env %>): inherits the team owner roles';
GRANT ROLE <% cicd_role %> TO ROLE SYSADMIN;
GRANT USAGE ON WAREHOUSE <% pipeline_wh %> TO ROLE <% cicd_role %>;
GRANT USAGE ON DATABASE <% env_db %> TO ROLE <% cicd_role %>;

-- 4. Service user for GitHub Actions: OIDC (no password, no key). The subject is the GitHub
--    environment, so only jobs running in that environment can log in as this user.
CREATE USER IF NOT EXISTS <% svc_user %>
  TYPE = SERVICE
  DEFAULT_ROLE = <% cicd_role %>
  DEFAULT_WAREHOUSE = <% pipeline_wh %>
  COMMENT = 'GitHub Actions - Streamlit CI/CD (<% env %>)';
ALTER USER <% svc_user %> SET WORKLOAD_IDENTITY = (
  TYPE = OIDC
  ISSUER = 'https://token.actions.githubusercontent.com'
  SUBJECT = '<% svc_subject %>');
ALTER USER <% svc_user %> SET DEFAULT_ROLE = <% cicd_role %> DEFAULT_WAREHOUSE = <% pipeline_wh %>;
GRANT ROLE <% cicd_role %> TO USER <% svc_user %>;

-- Only GitHub-hosted runners may log in as the service user (account policy unchanged).
-- Self-hosted runners (Verisure): replace the rule with one that lists the runner egress IPs.
CREATE NETWORK POLICY IF NOT EXISTS <% network_policy %>
  ALLOWED_NETWORK_RULE_LIST = ('SNOWFLAKE.NETWORK_SECURITY.GITHUBACTIONS_GLOBAL')
  COMMENT = 'GitHub Actions runners -> Streamlit/Skill CI/CD service users';
ALTER USER <% svc_user %> SET NETWORK_POLICY = <% network_policy %>;
