-- =====================================================================
-- Skill CI/CD - 02. Release email (ACCOUNTADMIN)  [from SEAT, unchanged logic]
-- Called by SP_SKILL_SYNC after each PRD deploy (one email per skill).
-- Recipients: every enabled user with an email who has the skill's users role (<SKILL>_SKILL_USERS),
-- directly or through other roles, at any depth. System roles (notify_exclude_roles) are not followed.
-- Run with --enable-templating STANDARD (the HTML below contains '&').
-- =====================================================================
USE ROLE ACCOUNTADMIN;

CREATE NOTIFICATION INTEGRATION IF NOT EXISTS <% email_int %>
  TYPE = EMAIL
  ENABLED = TRUE
  COMMENT = 'Skill CI/CD: release emails to the users of each skill';

CREATE OR REPLACE PROCEDURE <% db %>.<% cicd_schema %>.SP_SKILL_NOTIFY_RELEASE(
  P_EXT STRING, P_SKILL STRING, P_DESC STRING, P_COMMIT STRING, P_NOTES STRING,
  P_ROLE STRING DEFAULT '<% users_role %>')
RETURNS STRING
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
DECLARE
  v_sent   INTEGER DEFAULT 0;
  v_failed INTEGER DEFAULT 0;
  v_user   STRING;
  v_email  STRING;
  v_html   STRING;
  v_link   STRING;
  v_skill  STRING;
  v_desc   STRING;
  v_subj   STRING;
  v_role   STRING;
  v_sql    STRING;
  v_queue  ARRAY;
  v_seen   ARRAY DEFAULT ARRAY_CONSTRUCT();
  v_users  ARRAY DEFAULT ARRAY_CONSTRUCT();
  v_new_u  ARRAY;
  v_new_r  ARRAY;
  v_steps  INTEGER DEFAULT 0;
  rs       RESULTSET;
BEGIN
  v_queue := ARRAY_CONSTRUCT(P_ROLE);
  v_link := 'snow://skill_catalog/' || P_EXT;
  v_skill := REPLACE(REPLACE(REPLACE(COALESCE(P_SKILL, P_EXT), '&', '&amp;'), '<', '&lt;'), '>', '&gt;');
  v_desc  := REPLACE(REPLACE(REPLACE(COALESCE(P_DESC, '-'), '&', '&amp;'), '<', '&lt;'), '>', '&gt;');
  v_subj  := 'Skill ' || COALESCE(P_SKILL, P_EXT) || ' - new version available';
  v_html := '<h3>New version of the skill <code>' || v_skill || '</code> is available</h3>' ||
            '<p><b>Skill:</b> ' || v_skill || '<br><b>Description:</b> ' || v_desc || '</p>' ||
            '<p><b>Changes:</b><br>' || REPLACE(COALESCE(P_NOTES, '-'), '\n', '<br>') || '</p>' ||
            '<p><b>Commit:</b> ' || P_COMMIT || '</p>' ||
            '<p><b>Snowsight:</b> nothing to do, it already uses the new version.</p>' ||
            '<p><b>CoCo Desktop:</b> <a href="coco://install_catalog_uri?uri=snow%3A%2F%2Fskill_catalog%2F' || P_EXT || '">click here to install / update</a></p>' ||
            '<p><b>CLI:</b><br><code>cortex skill update ' || v_link || '</code></p>';

  WHILE (ARRAY_SIZE(v_queue) > 0 AND v_steps < 500) DO
    v_steps := v_steps + 1;
    v_role := v_queue[0]::STRING;
    v_queue := ARRAY_SLICE(v_queue, 1, ARRAY_SIZE(v_queue));
    IF (NOT ARRAY_CONTAINS(v_role::VARIANT, v_seen)) THEN
      v_seen := ARRAY_APPEND(v_seen, v_role);
      v_sql := 'SHOW GRANTS OF ROLE "' || REPLACE(v_role, '"', '""') || '"';
      EXECUTE IMMEDIATE :v_sql;
      SELECT ARRAY_AGG(IFF("granted_to" = 'USER', "grantee_name", NULL)),
             ARRAY_AGG(IFF("granted_to" = 'ROLE' AND "grantee_name" NOT IN (<% notify_exclude_roles %>), "grantee_name", NULL))
        INTO :v_new_u, :v_new_r
        FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
      v_users := ARRAY_CAT(v_users, COALESCE(v_new_u, ARRAY_CONSTRUCT()));
      v_queue := ARRAY_CAT(v_queue, COALESCE(v_new_r, ARRAY_CONSTRUCT()));
    END IF;
  END WHILE;
  v_users := ARRAY_DISTINCT(v_users);

  rs := (SELECT VALUE::STRING AS U FROM TABLE(FLATTEN(INPUT => :v_users)));
  FOR r IN rs DO
    v_user := r.U;
    v_email := NULL;
    SHOW USERS LIKE :v_user;
    SELECT MAX("email") INTO :v_email FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
      WHERE "name" = :v_user AND "disabled" = 'false';
    IF (v_email IS NOT NULL) THEN
      BEGIN
        CALL SYSTEM$SEND_SNOWFLAKE_NOTIFICATION(
          SNOWFLAKE.NOTIFICATION.TEXT_HTML(:v_html),
          SNOWFLAKE.NOTIFICATION.EMAIL_INTEGRATION_CONFIG('<% email_int %>', :v_subj, ARRAY_CONSTRUCT(:v_email)));
        v_sent := v_sent + 1;
      EXCEPTION
        WHEN OTHER THEN v_failed := v_failed + 1;
      END;
    END IF;
  END FOR;
  RETURN 'Emails sent: ' || v_sent || ', failed: ' || v_failed ||
         ' (users found: ' || ARRAY_SIZE(v_users) || ', roles walked: ' || ARRAY_SIZE(v_seen) || ')';
END;
$$;

GRANT USAGE ON PROCEDURE <% db %>.<% cicd_schema %>.SP_SKILL_NOTIFY_RELEASE(STRING, STRING, STRING, STRING, STRING, STRING)
  TO ROLE <% cicd_role %>;
