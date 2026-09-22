SET DEFINE OFF;

/* ============================================================================
   CONTRACT RENEWAL - LETTER CONFIGURATION

   This script is rerunnable. It reuses the generic signatory and recipient
   masters already used by the promotion module, but also creates them when the
   promotion module has not been installed.
   ============================================================================ */

BEGIN
    EXECUTE IMMEDIATE q'~
        CREATE TABLE HRMS.HR_LETTER_SIGNATORY
        (
            SIGNATORY_ID     NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
            SIGNATORY_CODE   VARCHAR2(30 BYTE) NOT NULL,
            NAME_EN          VARCHAR2(200 CHAR) NOT NULL,
            TITLE_EN         VARCHAR2(200 CHAR) NOT NULL,
            NAME_BN          VARCHAR2(200 CHAR) NOT NULL,
            TITLE_BN         VARCHAR2(200 CHAR) NOT NULL,
            DISPLAY_ORDER    NUMBER(3) DEFAULT 10 NOT NULL,
            IS_ACTIVE        VARCHAR2(1 BYTE) DEFAULT 'Y' NOT NULL,
            CREATED_BY       NUMBER,
            CREATED_DATE     DATE DEFAULT SYSDATE NOT NULL,
            UPDATED_BY       NUMBER,
            UPDATED_DATE     DATE,
            CONSTRAINT UK_HR_LETTER_SIGNATORY_CODE UNIQUE (SIGNATORY_CODE),
            CONSTRAINT CHK_HR_LETTER_SIGNATORY_ACTIVE
                CHECK (IS_ACTIVE IN ('Y', 'N'))
        )
    ~';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE <> -955 THEN RAISE; END IF;
END;
/

/* These are the signatories already used in this repository. Review names and
   titles with HR before production use. Existing administrator edits are not
   overwritten. */
MERGE INTO HRMS.HR_LETTER_SIGNATORY t
USING (
    SELECT 'MD' signatory_code,
           'Professor Dr. A. K. M. Sadrul Islam' name_en,
           'Managing Director' title_en,
           'প্রফেসর ডা. এ. কে. এম. সদরুল ইসলাম' name_bn,
           'ব্যবস্থাপনা পরিচালক' title_bn,
           10 display_order
      FROM dual
    UNION ALL
    SELECT 'ED',
           'Md. Yanoor Rahman',
           'Executive Director (Administration)',
           'মোঃ ইয়ানুর রহমান',
           'নির্বাহী পরিচালক (প্রশাসন)',
           20
      FROM dual
) s
ON (t.signatory_code = s.signatory_code)
WHEN NOT MATCHED THEN
    INSERT (signatory_code, name_en, title_en, name_bn, title_bn,
            display_order, is_active)
    VALUES (s.signatory_code, s.name_en, s.title_en, s.name_bn, s.title_bn,
            s.display_order, 'Y');


BEGIN
    EXECUTE IMMEDIATE q'~
        CREATE TABLE HRMS.HR_LETTER_RECIPIENT
        (
            LETTER_RECIPIENT_ID NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
            RECIPIENT_CODE      VARCHAR2(50 BYTE),
            RECIPIENT_NAME_EN   VARCHAR2(300 CHAR) NOT NULL,
            RECIPIENT_NAME_BN   VARCHAR2(300 CHAR),
            DISPLAY_ORDER       NUMBER(4) DEFAULT 10 NOT NULL,
            IS_ACTIVE           VARCHAR2(1 BYTE) DEFAULT 'Y' NOT NULL,
            CREATED_BY          NUMBER,
            CREATED_DATE        DATE DEFAULT SYSDATE NOT NULL,
            UPDATED_BY          NUMBER,
            UPDATED_DATE        DATE,
            CONSTRAINT UK_HR_LETTER_RECIP_CODE UNIQUE (RECIPIENT_CODE),
            CONSTRAINT CHK_HR_LETTER_RECIP_ACTIVE
                CHECK (IS_ACTIVE IN ('Y', 'N'))
        )
    ~';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE <> -955 THEN RAISE; END IF;
END;
/

/* Default distribution follows the supplied Bengali renewal-letter layout. */
MERGE INTO HRMS.HR_LETTER_RECIPIENT t
USING (
    SELECT 'MD_BOARD_INFO' recipient_code,
           'Managing Director / Board Member - for kind information' recipient_name_en,
           'মাননীয় ব্যবস্থাপনা পরিচালক মহোদয়ের সদয় জ্ঞাতার্থে' recipient_name_bn,
           10 display_order
      FROM dual
    UNION ALL
    SELECT 'ADMIN_CIVIL',
           'Assistant Manager, Admin (Civil Engineering)',
           'এসিস্ট্যান্ট ম্যানেজার, এডমিন (সিভিল ইঞ্জিনিয়ারিং)',
           20
      FROM dual
    UNION ALL
    SELECT 'ACCOUNTS_PAYROLL',
           'Accounts Department (Pay-Roll Section)',
           'হিসাব বিভাগ (Pay-Roll Section)',
           30
      FROM dual
    UNION ALL
    SELECT 'PERSONAL_FILE', 'Personal File', 'ব্যক্তিগত নথি', 40 FROM dual
    UNION ALL
    SELECT 'OFFICE_COPY', 'Office Copy', 'অফিস কপি', 50 FROM dual
) s
ON (t.recipient_code = s.recipient_code)
WHEN NOT MATCHED THEN
    INSERT (recipient_code, recipient_name_en, recipient_name_bn,
            display_order, is_active)
    VALUES (s.recipient_code, s.recipient_name_en, s.recipient_name_bn,
            s.display_order, 'Y');


BEGIN
    EXECUTE IMMEDIATE q'~
        CREATE TABLE HRMS.HR_CONTRACT_RENEW_RECIPIENT
        (
            RECIPIENT_ID        NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
            RENEWAL_ID          NUMBER NOT NULL,
            SECTION_TYPE        VARCHAR2(10 BYTE) DEFAULT 'COPY' NOT NULL,
            LETTER_RECIPIENT_ID NUMBER,
            LINE_TEXT           VARCHAR2(1000 CHAR),
            DISPLAY_ORDER       NUMBER(4) DEFAULT 10 NOT NULL,
            IS_ACTIVE           VARCHAR2(1 BYTE) DEFAULT 'Y' NOT NULL,
            CREATED_BY          NUMBER,
            CREATED_DATE        DATE DEFAULT SYSDATE NOT NULL,
            UPDATED_BY          NUMBER,
            UPDATED_DATE        DATE,
            CONSTRAINT FK_HR_CON_REN_REC_RENEW FOREIGN KEY (RENEWAL_ID)
                REFERENCES HRMS.HR_CONTRACT_RENEWAL (RENEWAL_ID)
                ON DELETE CASCADE,
            CONSTRAINT FK_HR_CON_REN_REC_MASTER FOREIGN KEY (LETTER_RECIPIENT_ID)
                REFERENCES HRMS.HR_LETTER_RECIPIENT (LETTER_RECIPIENT_ID),
            CONSTRAINT CK_HR_CON_REN_REC_SECTION CHECK
                (SECTION_TYPE IN ('TO', 'COPY')),
            CONSTRAINT CK_HR_CON_REN_REC_ACTIVE CHECK
                (IS_ACTIVE IN ('Y', 'N')),
            CONSTRAINT CK_HR_CON_REN_REC_SOURCE CHECK
                ((LETTER_RECIPIENT_ID IS NOT NULL AND LINE_TEXT IS NULL)
                 OR
                 (LETTER_RECIPIENT_ID IS NULL AND TRIM(LINE_TEXT) IS NOT NULL)),
            CONSTRAINT UK_HR_CON_REN_REC_SELECT UNIQUE
                (RENEWAL_ID, SECTION_TYPE, LETTER_RECIPIENT_ID)
        )
    ~';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE <> -955 THEN RAISE; END IF;
END;
/

BEGIN
    EXECUTE IMMEDIATE
        'CREATE INDEX HRMS.IX_HR_CON_REN_REC_RENEW '
        || 'ON HRMS.HR_CONTRACT_RENEW_RECIPIENT '
        || '(RENEWAL_ID, SECTION_TYPE, DISPLAY_ORDER)';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE <> -955 THEN RAISE; END IF;
END;
/

/* Link each issued letter directly to its renewal. */
DECLARE
    l_count PLS_INTEGER;
BEGIN
    SELECT COUNT(*) INTO l_count
      FROM user_tab_columns
     WHERE table_name = 'HR_EMPLOYEE_LETTER'
       AND column_name = 'CONTRACT_RENEWAL_ID';

    IF l_count = 0 THEN
        EXECUTE IMMEDIATE
            'ALTER TABLE HRMS.HR_EMPLOYEE_LETTER ADD CONTRACT_RENEWAL_ID NUMBER';
    END IF;
END;
/

DECLARE
    l_count PLS_INTEGER;
BEGIN
    SELECT COUNT(*) INTO l_count
      FROM user_constraints
     WHERE table_name = 'HR_EMPLOYEE_LETTER'
       AND constraint_name = 'FK_HR_EMP_LET_CON_RENEW';

    IF l_count = 0 THEN
        EXECUTE IMMEDIATE q'~
            ALTER TABLE HRMS.HR_EMPLOYEE_LETTER ADD CONSTRAINT
                FK_HR_EMP_LET_CON_RENEW FOREIGN KEY (CONTRACT_RENEWAL_ID)
                REFERENCES HRMS.HR_CONTRACT_RENEWAL (RENEWAL_ID)
        ~';
    END IF;
END;
/

DECLARE
    l_count PLS_INTEGER;
BEGIN
    SELECT COUNT(*) INTO l_count
      FROM user_constraints
     WHERE table_name = 'HR_CONTRACT_RENEWAL'
       AND constraint_name = 'FK_HR_CON_RENEW_SIGN';

    IF l_count = 0 THEN
        EXECUTE IMMEDIATE q'~
            ALTER TABLE HRMS.HR_CONTRACT_RENEWAL ADD CONSTRAINT
                FK_HR_CON_RENEW_SIGN FOREIGN KEY (SIGNATORY_ID)
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
     WHERE table_name = 'HR_CONTRACT_RENEWAL'
       AND constraint_name = 'FK_HR_CON_RENEW_LETTER';

    IF l_count = 0 THEN
        EXECUTE IMMEDIATE q'~
            ALTER TABLE HRMS.HR_CONTRACT_RENEWAL ADD CONSTRAINT
                FK_HR_CON_RENEW_LETTER FOREIGN KEY (LETTER_ID)
                REFERENCES HRMS.HR_EMPLOYEE_LETTER (LETTER_ID)
        ~';
    END IF;
END;
/

/* Bengali body follows the supplied scan. Page 522 supplies the header,
   employee address, salary rows, signature and copy list. */
MERGE INTO HRMS.HR_LETTER_TEMPLATE t
USING (
    SELECT 'CONTRACT_RENEWAL_BN' template_code,
           'Bengali Contract Renewal Letter' template_name,
           'CONTRACT_RENEWAL' action_type,
           'চুক্তি নবায়ন' subject_template,
           TO_CLOB(q'~
<p>জনাব,</p>
<p>আসসালামু আলাইকুম ওয়া রাহমাতুল্লাহ।</p>
<p>#COMPANY_NAME_BN#-এর ব্যবস্থাপনা কর্তৃপক্ষ আপনার চুক্তিভিত্তিক নিয়োগ
<strong>#CONTRACT_TERM_BN#</strong>-এর জন্য নবায়ন করেছেন। নবায়নকৃত মেয়াদ
<strong>#NEW_FROM_DATE_BN#</strong> থেকে <strong>#NEW_TO_DATE_BN#</strong> পর্যন্ত।</p>
<p><strong><u>চুক্তি নবায়নের শর্তাবলী:</u></strong></p>
<ol class="conditions">
  <li>ব্যবস্থাপনা কর্তৃপক্ষের এই সিদ্ধান্ত #NEW_FROM_DATE_BN# তারিখ থেকে কার্যকর বলে গণ্য হবে।</li>
  <li>নবায়নকৃত চুক্তিকালীন কোম্পানির <strong>#GRADE_BN# নং গ্রেডে</strong>
      (<strong>#PAY_SCALE_BN#</strong>) আপনার বেতন-ভাতা নিম্নরূপ:</li>
</ol>
#SALARY_DETAILS#
<ol class="conditions" start="3">
  <li>নবায়নকৃত চুক্তির মেয়াদ শেষ হওয়ার পর আপনার সার্বিক কর্মমূল্যায়নের ভিত্তিতে পরবর্তী সিদ্ধান্ত গ্রহণ করা হবে।</li>
  <li>আপনি কোম্পানির প্রচলিত বিধি অনুযায়ী মাসিক ছুটি ভোগের সুবিধা পাবেন।</li>
  <li>আপনি বিধিমাফিক বছরে দুটি উৎসব বোনাস প্রাপ্য হবেন।</li>
  <li>কোম্পানির প্রয়োজনে আপনাকে কোম্পানির কার্যক্রমের আওতাভুক্ত যে কোনো স্থানে কাজে নিয়োজিত করা যেতে পারে।</li>
  <li>সকল বিষয়ে আপনি কোম্পানিতে বর্তমানে প্রচলিত এবং ভবিষ্যতে সংশোধিত চাকরি বিধি ও প্রশাসনিক আদেশ-নির্দেশ অনুযায়ী নিয়ন্ত্রিত ও পরিচালিত হবেন।</li>
</ol>
<p>#SPECIAL_TERMS#</p>
<p>সর্বশক্তিমান আল্লাহ তায়ালা আমাদের সবাইকে নিজ নিজ দায়িত্ব ও কর্তব্য যথাযথভাবে পালন করার তাওফিক দান করুন।</p>
<p>মা''আসসালাম।</p>
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
