SET DEFINE OFF;
/* Extension-only templates and links. Shared signatory/recipient masters
   already exist from renewal. Renewal templates are never merged here. */

BEGIN
    EXECUTE IMMEDIATE q'~
        CREATE TABLE HRMS.HR_CONTRACT_EXT_RECIPIENT
        (
            RECIPIENT_ID        NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
            EXTENSION_ID          NUMBER NOT NULL,
            SECTION_TYPE        VARCHAR2(10 BYTE) DEFAULT 'COPY' NOT NULL,
            LETTER_RECIPIENT_ID NUMBER,
            LINE_TEXT           VARCHAR2(1000 CHAR),
            DISPLAY_ORDER       NUMBER(4) DEFAULT 10 NOT NULL,
            IS_ACTIVE           VARCHAR2(1 BYTE) DEFAULT 'Y' NOT NULL,
            CREATED_BY          NUMBER,
            CREATED_DATE        DATE DEFAULT SYSDATE NOT NULL,
            UPDATED_BY          NUMBER,
            UPDATED_DATE        DATE,
            CONSTRAINT FK_HR_CON_EXT_REC_EXT FOREIGN KEY (EXTENSION_ID)
                REFERENCES HRMS.HR_CONTRACT_EXTENSION (EXTENSION_ID)
                ON DELETE CASCADE,
            CONSTRAINT FK_HR_CON_EXT_REC_MASTER FOREIGN KEY (LETTER_RECIPIENT_ID)
                REFERENCES HRMS.HR_LETTER_RECIPIENT (LETTER_RECIPIENT_ID),
            CONSTRAINT CK_HR_CON_EXT_REC_SECTION CHECK
                (SECTION_TYPE IN ('TO', 'COPY')),
            CONSTRAINT CK_HR_CON_EXT_REC_ACTIVE CHECK
                (IS_ACTIVE IN ('Y', 'N')),
            CONSTRAINT CK_HR_CON_EXT_REC_SOURCE CHECK
                ((LETTER_RECIPIENT_ID IS NOT NULL AND LINE_TEXT IS NULL)
                 OR
                 (LETTER_RECIPIENT_ID IS NULL AND TRIM(LINE_TEXT) IS NOT NULL)),
            CONSTRAINT UK_HR_CON_EXT_REC_SELECT UNIQUE
                (EXTENSION_ID, SECTION_TYPE, LETTER_RECIPIENT_ID)
        )
    ~';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE <> -955 THEN RAISE; END IF;
END;
/

BEGIN
    EXECUTE IMMEDIATE
        'CREATE INDEX HRMS.IX_HR_CON_EXT_REC_EXT '
        || 'ON HRMS.HR_CONTRACT_EXT_RECIPIENT '
        || '(EXTENSION_ID, SECTION_TYPE, DISPLAY_ORDER)';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE <> -955 THEN RAISE; END IF;
END;
/

/* Link each issued letter directly to its extension. */
DECLARE
    l_count PLS_INTEGER;
BEGIN
    SELECT COUNT(*) INTO l_count
      FROM user_tab_columns
     WHERE table_name = 'HR_EMPLOYEE_LETTER'
       AND column_name = 'CONTRACT_EXTENSION_ID';

    IF l_count = 0 THEN
        EXECUTE IMMEDIATE
            'ALTER TABLE HRMS.HR_EMPLOYEE_LETTER ADD CONTRACT_EXTENSION_ID NUMBER';
    END IF;
END;
/

DECLARE
    l_count PLS_INTEGER;
BEGIN
    SELECT COUNT(*) INTO l_count
      FROM user_constraints
     WHERE table_name = 'HR_EMPLOYEE_LETTER'
       AND constraint_name = 'FK_HR_EMP_LET_CON_EXT';

    IF l_count = 0 THEN
        EXECUTE IMMEDIATE q'~
            ALTER TABLE HRMS.HR_EMPLOYEE_LETTER ADD CONSTRAINT
                FK_HR_EMP_LET_CON_EXT FOREIGN KEY (CONTRACT_EXTENSION_ID)
                REFERENCES HRMS.HR_CONTRACT_EXTENSION (EXTENSION_ID)
        ~';
    END IF;
END;
/

DECLARE
    l_count PLS_INTEGER;
BEGIN
    SELECT COUNT(*) INTO l_count
      FROM user_constraints
     WHERE table_name = 'HR_CONTRACT_EXTENSION'
       AND constraint_name = 'FK_HR_CON_EXT_SIGN';

    IF l_count = 0 THEN
        EXECUTE IMMEDIATE q'~
            ALTER TABLE HRMS.HR_CONTRACT_EXTENSION ADD CONSTRAINT
                FK_HR_CON_EXT_SIGN FOREIGN KEY (SIGNATORY_ID)
                REFERENCES HRMS.HR_LETTER_SIGNATORY (SIGNATORY_ID)
        ~';
    END IF;
END;
/

DECLARE
    l_count PLS_INTEGER;
BEGIN
    SELECT COUNT(*) INTO l_count
      FROM user_constraints
     WHERE table_name = 'HR_CONTRACT_EXTENSION'
       AND constraint_name = 'FK_HR_CON_EXT_LETTER';

    IF l_count = 0 THEN
        EXECUTE IMMEDIATE q'~
            ALTER TABLE HRMS.HR_CONTRACT_EXTENSION ADD CONSTRAINT
                FK_HR_CON_EXT_LETTER FOREIGN KEY (LETTER_ID)
                REFERENCES HRMS.HR_EMPLOYEE_LETTER (LETTER_ID)
        ~';
    END IF;
END;
/

/* Simple English body for any eligible employee. Page 525 supplies the header, employee address,
   signature and copy list; no salary breakdown is needed. */
MERGE INTO HRMS.HR_LETTER_TEMPLATE t
USING (
    SELECT 'CONTRACT_EXTENSION_EN' template_code,
           'English Contract Extension Letter' template_name,
           'CONTRACT_EXTENSION' action_type,
           'Extension of Confirmation Due Date' subject_template,
           TO_CLOB(q'~
<p>Janab,<br>Assalamu Alaikum Wa Rahmatullah</p>
<p>The management of #COMPANY_NAME# has decided to extend your confirmation due date.</p>
<ol>
<li>Your confirmation due date is extended from <strong>#CURRENT_TO_DATE#</strong>
to <strong>#NEW_TO_DATE#</strong>. Employment confirmation remains pending.</li>
<li>Your salary and other benefits will remain unchanged.</li>
<li>All other existing terms and conditions, including your employment category,
remain unchanged.</li>
</ol>
<p>May Allah, the Almighty, help us all. Ameen.<br>Ma-Assalam.</p>
~') body_template
      FROM dual
) s
ON (t.template_code = s.template_code)
WHEN MATCHED THEN
    UPDATE SET t.template_name      = s.template_name,
               t.action_type       = s.action_type,
               t.subject_template  = s.subject_template,
               t.body_template     = s.body_template,
               t.is_active         = 'Y',
               t.upd_date          = SYSDATE
WHEN NOT MATCHED THEN
    INSERT (template_code, template_name, action_type, subject_template,
            body_template, is_active)
    VALUES (s.template_code, s.template_name, s.action_type,
            s.subject_template, s.body_template, 'Y');

/* Retain the Bengali template for existing letters and future manual use.
   New simple extensions use English without a grade requirement. */
MERGE INTO HRMS.HR_LETTER_TEMPLATE t
USING (
    SELECT 'CONTRACT_EXTENSION_BN' template_code,
           'Bengali Contract Extension Letter' template_name,
           'CONTRACT_EXTENSION' action_type,
           'চুক্তি নবায়ন' subject_template,
           TO_CLOB(q'~
<p>জনাব,</p>
<p>#COMPANY_NAME_BN#-এর ব্যবস্থাপনা কর্তৃপক্ষ আপনার চাকরি স্থায়ীকরণের নির্ধারিত তারিখ
<strong>#NEW_TO_DATE_BN#</strong> পর্যন্ত বৃদ্ধি করেছেন। চাকরি স্থায়ীকরণ অপেক্ষমাণ থাকবে।</p>
<p>আপনার বেতন ও অন্যান্য সুবিধা অপরিবর্তিত থাকবে।</p>
<p>প্রবেশন মেয়াদ বৃদ্ধির ক্ষেত্রে চাকরি স্থায়ীকরণের নির্ধারিত তারিখ
<strong>#NEW_TO_DATE_BN#</strong> পর্যন্ত বৃদ্ধি পাবে; চাকরি স্থায়ীকরণ অপেক্ষমাণ থাকবে।</p>
<p>নিয়োগের ধরন ও অন্যান্য বিদ্যমান শর্ত অপরিবর্তিত থাকবে।</p>
~') body_template
      FROM dual
) s
ON (t.template_code = s.template_code)
WHEN MATCHED THEN
    UPDATE SET t.template_name      = s.template_name,
               t.action_type       = s.action_type,
               t.subject_template  = s.subject_template,
               t.body_template     = s.body_template,
               t.is_active         = 'Y',
               t.upd_date          = SYSDATE
WHEN NOT MATCHED THEN
    INSERT (template_code, template_name, action_type, subject_template,
            body_template, is_active)
    VALUES (s.template_code, s.template_name, s.action_type,
            s.subject_template, s.body_template, 'Y');

COMMIT;
