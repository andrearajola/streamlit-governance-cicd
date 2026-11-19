-- =====================================================================
-- Streamlit CI/CD - 02b. Data access for RESTRICTED CALLER'S RIGHTS apps (ACCOUNTADMIN)
-- The app queries with the VIEWER's privileges (st.connection("snowflake-callers-rights")).
-- Caller grants give no access: they only allow the app to USE the viewer's own SELECT.
-- The viewer still needs SELECT on the data and USAGE on the warehouse through their own role,
-- and row access policies are evaluated for the viewer (note: the viewer's DEFAULT role).
-- Requires MANAGE CALLER GRANTS (ACCOUNTADMIN has it).
-- =====================================================================
USE ROLE ACCOUNTADMIN;
GRANT CALLER USAGE ON DATABASE <% data_db %> TO ROLE <% owner_role %>;
GRANT CALLER USAGE ON SCHEMA <% data_db %>.<% data_schema %> TO ROLE <% owner_role %>;
GRANT INHERITED CALLER SELECT ON ALL TABLES IN SCHEMA <% data_db %>.<% data_schema %> TO ROLE <% owner_role %>;
GRANT INHERITED CALLER SELECT ON ALL VIEWS IN SCHEMA <% data_db %>.<% data_schema %> TO ROLE <% owner_role %>;
GRANT CALLER USAGE ON WAREHOUSE <% warehouse %> TO ROLE <% owner_role %>;
