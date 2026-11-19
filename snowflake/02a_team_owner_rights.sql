-- =====================================================================
-- Streamlit CI/CD - 02a. Data access for OWNER'S RIGHTS apps (ACCOUNTADMIN)
-- The app runs with the owner role: the owner role reads the data, viewers need no data access.
-- Row access policies see the OWNER role, not the viewer (use 02b if rows depend on the viewer).
-- =====================================================================
USE ROLE ACCOUNTADMIN;
GRANT USAGE ON DATABASE <% data_db %> TO ROLE <% owner_role %>;
GRANT USAGE ON SCHEMA <% data_db %>.<% data_schema %> TO ROLE <% owner_role %>;
GRANT SELECT ON ALL TABLES IN SCHEMA <% data_db %>.<% data_schema %> TO ROLE <% owner_role %>;
GRANT SELECT ON FUTURE TABLES IN SCHEMA <% data_db %>.<% data_schema %> TO ROLE <% owner_role %>;
GRANT SELECT ON ALL VIEWS IN SCHEMA <% data_db %>.<% data_schema %> TO ROLE <% owner_role %>;
GRANT SELECT ON FUTURE VIEWS IN SCHEMA <% data_db %>.<% data_schema %> TO ROLE <% owner_role %>;
