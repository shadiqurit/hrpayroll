/*
  Install or update the default promotion-letter template.

  BODY_HTML stores narrative text and the #SALARY_DETAILS# marker only.
  Page 483 replaces that marker with the database comparison, including salary
  heads 025 and 026.

  No COMMIT is included. Review and commit through the deployment transaction.
*/
MERGE INTO hr_letter_template t
USING (
    SELECT 'PROMOTION_DEFAULT' AS template_code,
           'Default Promotion Letter' AS template_name,
           'PROMOTION' AS action_type,
           '#PROMOTION_TYPE# Promotion Letter - #EMP_NAME#' AS subject_template,
           '<p>To<br><strong>#EMP_NAME#</strong><br>Employee ID: #EMP_CODE#</p>
<p>Dear #EMP_NAME#,</p>
<p>We are pleased to inform you that you have been granted <strong>#PROMOTION_TYPE# Promotion</strong> from <strong>#OLD_DESIGNATION#</strong> to <strong>#NEW_DESIGNATION#</strong> with effect from <strong>#EFFECTIVE_DATE#</strong>.</p>
<p>Your salary structure has been revised. The complete salary-head comparison before and after promotion, including salary heads 025 and 026, is provided below.</p>
#SALARY_DETAILS#
<p>All salary heads shown above will take effect from <strong>#EFFECTIVE_DATE#</strong>.</p>
<p>We congratulate you and wish you continued success in your new role.</p>
<p style="margin-top:45px">Human Resources</p>' AS body_template
      FROM dual
) s
ON (t.template_code = s.template_code)
WHEN MATCHED THEN
    UPDATE SET t.template_name     = s.template_name,
               t.action_type      = s.action_type,
               t.subject_template = s.subject_template,
               t.body_template    = s.body_template,
               t.is_active        = 'Y',
               t.upd_date         = SYSDATE
WHEN NOT MATCHED THEN
    INSERT (
        template_code,
        template_name,
        action_type,
        subject_template,
        body_template,
        is_active,
        ent_date
    ) VALUES (
        s.template_code,
        s.template_name,
        s.action_type,
        s.subject_template,
        s.body_template,
        'Y',
        SYSDATE
    );
