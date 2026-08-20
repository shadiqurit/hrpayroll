/* ============================================================
   HRMS LETTER TEMPLATE TABLE
   ============================================================ */

CREATE TABLE hr_letter_template
(
    template_id       NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    template_code     VARCHAR2 (50) NOT NULL UNIQUE,
    template_name     VARCHAR2 (150) NOT NULL,
    action_type       VARCHAR2 (30) NOT NULL,
    subject_template  VARCHAR2 (500),
    body_template     CLOB NOT NULL,
    is_active         VARCHAR2 (1) DEFAULT 'Y' NOT NULL,
    ent_by            NUMBER,
    ent_date          DATE DEFAULT SYSDATE,
    upd_by            NUMBER,
    upd_date          DATE,
    CONSTRAINT chk_letter_template_active CHECK (is_active IN ('Y', 'N'))
);

INSERT INTO hr_letter_template
            (template_code,
             template_name,
             action_type,
             subject_template,
             body_template)
     SELECT 'PROMOTION_DEFAULT',
            'Default Promotion Letter',
            'PROMOTION',
            '#PROMOTION_TYPE# Promotion Letter - #EMP_NAME#',
            '<p>Date: #LETTER_DATE#</p>
<p>To<br><strong>#EMP_NAME#</strong><br>Employee ID: #EMP_CODE#</p>
<p>Subject: #PROMOTION_TYPE# Promotion</p>
<p>Dear #EMP_NAME#,</p>
<p>We are pleased to inform you that you have been granted <strong>#PROMOTION_TYPE# Promotion</strong> from <strong>#OLD_DESIGNATION#</strong> to <strong>#NEW_DESIGNATION#</strong> with effect from <strong>#EFFECTIVE_DATE#</strong>.</p>
<p>Your revised basic salary will be <strong>#NEW_BASIC#</strong> and revised gross salary will be <strong>#NEW_GROSS#</strong>.</p>
<p>We congratulate you and wish you continued success.</p>
<p>Human Resources</p>'
       FROM dual
      WHERE NOT EXISTS
                (SELECT 1
                   FROM hr_letter_template
                  WHERE template_code = 'PROMOTION_DEFAULT');

INSERT INTO hr_letter_template
            (template_code,
             template_name,
             action_type,
             subject_template,
             body_template)
     SELECT 'INCREMENT_DEFAULT',
            'Default Annual Increment Letter',
            'INCREMENT',
            'Annual Increment Letter - #EMP_NAME#',
            '<p>Date: #LETTER_DATE#</p>
<p>To<br><strong>#EMP_NAME#</strong><br>Employee ID: #EMP_CODE#</p>
<p>Designation: #DESIGNATION#<br>Department: #DEPARTMENT#</p>
<p>Subject: Annual Increment</p>
<p>Dear #EMP_NAME#,</p>
<p>Your annual increment has been approved with effect from <strong>#EFFECTIVE_DATE#</strong>.</p>
<p>Previous Basic: <strong>#OLD_BASIC#</strong><br>
Revised Basic: <strong>#NEW_BASIC#</strong><br>
Increment Amount: <strong>#INCREMENT_AMOUNT#</strong></p>
<p>Previous Gross: <strong>#OLD_GROSS#</strong><br>
Revised Gross: <strong>#NEW_GROSS#</strong></p>
<p>Human Resources</p>'
       FROM dual
      WHERE NOT EXISTS
                (SELECT 1
                   FROM hr_letter_template
                  WHERE template_code = 'INCREMENT_DEFAULT');
