/*
  Promotion letter signatory and variable TO/COPY configuration.

  Run once before recompiling PKG_HR_PROMOTION and before configuring the
  Page 477 signatory item/recipient Interactive Grid. Fixed recipients are
  maintained in HR_LETTER_RECIPIENT; Page 477 stores only the selected master
  ID in HR_PROMOTION_LETTER_RECIPIENT. The detail table retains LINE_TEXT for
  legacy/custom recipients maintained outside this simplified Page 477 region.
  The DDL portions are rerunnable. Remember that Oracle commits implicitly
  around DDL statements.
*/

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
        IF SQLCODE <> -955 THEN
            RAISE;
        END IF;
END;
/

MERGE INTO HRMS.HR_LETTER_SIGNATORY t
USING (
    SELECT 'MD' AS signatory_code,
           'Professor Dr. A. K. M. Sadrul Islam' AS name_en,
           'Managing Director' AS title_en,
           'প্রফেসর ডা. এ. কে. এম. সদরুল ইসলাম' AS name_bn,
           'ব্যবস্থাপনা পরিচালক' AS title_bn,
           10 AS display_order
      FROM dual
    UNION ALL
    SELECT 'ED',
           'Md. Yanoor Rahman',
           'Executive Director (Administration)',
           'মোঃ ইয়ানুর রহমান',
           'নির্বাহী পরিচালক (প্রশাসন)',
           20
      FROM dual
    UNION ALL
    SELECT 'ED_PLANTS',
           'Md. Kabir Hossain',
           'Executive Director (Plants)',
           'মোঃ কবির হোসেন',
           'নির্বাহী পরিচালক (প্ল্যান্টস)',
           30
      FROM dual
) s
ON (t.signatory_code = s.signatory_code)
WHEN MATCHED THEN
    UPDATE SET t.name_en       = s.name_en,
               t.title_en      = s.title_en,
               t.name_bn       = s.name_bn,
               t.title_bn      = s.title_bn,
               t.display_order = s.display_order,
               t.updated_date  = SYSDATE
WHEN NOT MATCHED THEN
    INSERT (
        signatory_code, name_en, title_en, name_bn, title_bn,
        display_order, is_active
    ) VALUES (
        s.signatory_code, s.name_en, s.title_en, s.name_bn, s.title_bn,
        s.display_order, 'Y'
    );

DECLARE
    l_count PLS_INTEGER;
BEGIN
    SELECT COUNT(*)
      INTO l_count
      FROM user_tab_columns
     WHERE table_name = 'HR_EMPLOYEE_PROMOTION'
       AND column_name = 'SIGNATORY_ID';

    IF l_count = 0 THEN
        EXECUTE IMMEDIATE
            'ALTER TABLE HRMS.HR_EMPLOYEE_PROMOTION ADD SIGNATORY_ID NUMBER';
    END IF;
END;
/

DECLARE
    l_count PLS_INTEGER;
BEGIN
    SELECT COUNT(*)
      INTO l_count
      FROM user_constraints
     WHERE table_name = 'HR_EMPLOYEE_PROMOTION'
       AND constraint_name = 'FK_HR_EMP_PROMO_SIGNATORY';

    IF l_count = 0 THEN
        EXECUTE IMMEDIATE q'~
            ALTER TABLE HRMS.HR_EMPLOYEE_PROMOTION ADD CONSTRAINT
                FK_HR_EMP_PROMO_SIGNATORY FOREIGN KEY (SIGNATORY_ID)
                REFERENCES HRMS.HR_LETTER_SIGNATORY (SIGNATORY_ID)
        ~';
    END IF;
END;
/

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
        IF SQLCODE <> -955 THEN
            RAISE;
        END IF;
END;
/

/* Standard copy recipients from the approved promotion-letter format.
   Only missing codes are inserted so administrators can edit the master names
   without a later rerun overwriting their changes. */
MERGE INTO HRMS.HR_LETTER_RECIPIENT t
USING (
    SELECT 'HEAD_OF_SALES' AS recipient_code,
           'Head of Sales' AS recipient_name_en,
           'হেড অব সেলস্' AS recipient_name_bn,
           10 AS display_order
      FROM dual
    UNION ALL
    SELECT 'DGM_OPERATIONS_SALES',
           'DGM, Operations (Sales)',
           'ডিজিএম, অপারেশন (সেলস্)',
           20
      FROM dual
    UNION ALL
    SELECT 'DGM_MONITORING_SALES',
           'DGM, Monitoring (Sales)',
           'ডিজিএম, মনিটরিং (সেলস্)',
           30
      FROM dual
    UNION ALL
    SELECT 'ACCOUNTS_PAYROLL',
           'Accounts Department (Pay-Roll Section)',
           'হিসাব বিভাগ (Pay-Roll Section)',
           40
      FROM dual
    UNION ALL
    SELECT 'SOFTWARE_DATA_ENTRY_OFFICER',
           'Officer Responsible for Software Data Entry',
           'সফটওয়্যার এ ডাটা এন্ট্রির জন্য দায়িত্ব প্রাপ্ত কর্মকর্তা',
           50
      FROM dual
    UNION ALL
    SELECT 'PERSONAL_FILE',
           'Personal File',
           'ব্যক্তিগত নথি',
           60
      FROM dual
    UNION ALL
    SELECT 'OFFICE_COPY',
           'Office Copy',
           'অফিস কপি',
           70
      FROM dual
) s
ON (t.recipient_code = s.recipient_code)
WHEN NOT MATCHED THEN
    INSERT (
        recipient_code, recipient_name_en, recipient_name_bn,
        display_order, is_active
    ) VALUES (
        s.recipient_code, s.recipient_name_en, s.recipient_name_bn,
        s.display_order, 'Y'
    );

BEGIN
    EXECUTE IMMEDIATE q'~
        CREATE TABLE HRMS.HR_PROMOTION_LETTER_RECIPIENT
        (
            RECIPIENT_ID       NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
            PROMOTION_ID       NUMBER NOT NULL,
            SECTION_TYPE       VARCHAR2(10 BYTE) DEFAULT 'COPY' NOT NULL,
            LETTER_RECIPIENT_ID NUMBER,
            LINE_TEXT          VARCHAR2(1000 CHAR),
            DISPLAY_ORDER      NUMBER(4) DEFAULT 10 NOT NULL,
            IS_ACTIVE          VARCHAR2(1 BYTE) DEFAULT 'Y' NOT NULL,
            CREATED_BY         NUMBER,
            CREATED_DATE       DATE DEFAULT SYSDATE NOT NULL,
            UPDATED_BY         NUMBER,
            UPDATED_DATE       DATE,
            CONSTRAINT FK_HR_PROMO_LETTER_RECIPIENT
                FOREIGN KEY (PROMOTION_ID)
                REFERENCES HRMS.HR_EMPLOYEE_PROMOTION (PROMOTION_ID)
                ON DELETE CASCADE,
            CONSTRAINT FK_HR_PROMO_RECIP_MASTER
                FOREIGN KEY (LETTER_RECIPIENT_ID)
                REFERENCES HRMS.HR_LETTER_RECIPIENT (LETTER_RECIPIENT_ID),
            CONSTRAINT CHK_HR_PROMO_RECIP_SECTION
                CHECK (SECTION_TYPE IN ('TO', 'COPY')),
            CONSTRAINT CHK_HR_PROMO_RECIP_ACTIVE
                CHECK (IS_ACTIVE IN ('Y', 'N')),
            CONSTRAINT CHK_HR_PROMO_RECIP_SOURCE CHECK (
                (LETTER_RECIPIENT_ID IS NOT NULL AND LINE_TEXT IS NULL)
                OR
                (LETTER_RECIPIENT_ID IS NULL AND TRIM(LINE_TEXT) IS NOT NULL)
            ),
            CONSTRAINT UK_HR_PROMO_RECIP_SELECTION UNIQUE
                (PROMOTION_ID, SECTION_TYPE, LETTER_RECIPIENT_ID)
        )
    ~';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE <> -955 THEN
            RAISE;
        END IF;
END;
/

/* Upgrade an earlier version of HR_PROMOTION_LETTER_RECIPIENT without losing
   its custom text rows. */
DECLARE
    l_count PLS_INTEGER;
BEGIN
    SELECT COUNT(*)
      INTO l_count
      FROM user_tab_columns
     WHERE table_name = 'HR_PROMOTION_LETTER_RECIPIENT'
       AND column_name = 'LETTER_RECIPIENT_ID';

    IF l_count = 0 THEN
        EXECUTE IMMEDIATE q'~
            ALTER TABLE HRMS.HR_PROMOTION_LETTER_RECIPIENT
                ADD LETTER_RECIPIENT_ID NUMBER
        ~';
    END IF;
END;
/

/* Page 477 only supplies PROMOTION_ID and LETTER_RECIPIENT_ID. The selected
   master recipients are copy recipients unless another maintenance process
   explicitly supplies a different section type. */
BEGIN
    EXECUTE IMMEDIATE q'~
        ALTER TABLE HRMS.HR_PROMOTION_LETTER_RECIPIENT
            MODIFY SECTION_TYPE DEFAULT 'COPY'
    ~';
END;
/

DECLARE
    l_nullable user_tab_columns.nullable%TYPE;
BEGIN
    SELECT nullable
      INTO l_nullable
      FROM user_tab_columns
     WHERE table_name = 'HR_PROMOTION_LETTER_RECIPIENT'
       AND column_name = 'LINE_TEXT';

    IF l_nullable = 'N' THEN
        EXECUTE IMMEDIATE q'~
            ALTER TABLE HRMS.HR_PROMOTION_LETTER_RECIPIENT
                MODIFY LINE_TEXT NULL
        ~';
    END IF;
END;
/

DECLARE
    l_count PLS_INTEGER;
BEGIN
    SELECT COUNT(*)
      INTO l_count
      FROM user_constraints
     WHERE table_name = 'HR_PROMOTION_LETTER_RECIPIENT'
       AND constraint_name = 'FK_HR_PROMO_RECIP_MASTER';

    IF l_count = 0 THEN
        EXECUTE IMMEDIATE q'~
            ALTER TABLE HRMS.HR_PROMOTION_LETTER_RECIPIENT ADD CONSTRAINT
                FK_HR_PROMO_RECIP_MASTER FOREIGN KEY (LETTER_RECIPIENT_ID)
                REFERENCES HRMS.HR_LETTER_RECIPIENT (LETTER_RECIPIENT_ID)
        ~';
    END IF;
END;
/

DECLARE
    l_count PLS_INTEGER;
BEGIN
    SELECT COUNT(*)
      INTO l_count
      FROM user_constraints
     WHERE table_name = 'HR_PROMOTION_LETTER_RECIPIENT'
       AND constraint_name = 'CHK_HR_PROMO_RECIP_SOURCE';

    IF l_count = 0 THEN
        EXECUTE IMMEDIATE q'~
            ALTER TABLE HRMS.HR_PROMOTION_LETTER_RECIPIENT ADD CONSTRAINT
                CHK_HR_PROMO_RECIP_SOURCE CHECK (
                    (LETTER_RECIPIENT_ID IS NOT NULL AND LINE_TEXT IS NULL)
                    OR
                    (LETTER_RECIPIENT_ID IS NULL AND TRIM(LINE_TEXT) IS NOT NULL)
                )
        ~';
    END IF;
END;
/

DECLARE
    l_count PLS_INTEGER;
BEGIN
    SELECT COUNT(*)
      INTO l_count
      FROM user_constraints
     WHERE table_name = 'HR_PROMOTION_LETTER_RECIPIENT'
       AND constraint_name = 'UK_HR_PROMO_RECIP_SELECTION';

    IF l_count = 0 THEN
        EXECUTE IMMEDIATE q'~
            ALTER TABLE HRMS.HR_PROMOTION_LETTER_RECIPIENT ADD CONSTRAINT
                UK_HR_PROMO_RECIP_SELECTION UNIQUE
                (PROMOTION_ID, SECTION_TYPE, LETTER_RECIPIENT_ID)
        ~';
    END IF;
END;
/

BEGIN
    EXECUTE IMMEDIATE q'~
        CREATE INDEX HRMS.IDX_HR_PROMO_LETTER_RECIPIENT
            ON HRMS.HR_PROMOTION_LETTER_RECIPIENT
               (PROMOTION_ID, SECTION_TYPE, IS_ACTIVE, DISPLAY_ORDER)
    ~';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE <> -955 THEN
            RAISE;
        END IF;
END;
/

BEGIN
    EXECUTE IMMEDIATE q'~
        CREATE INDEX HRMS.IDX_HR_PROMO_RECIP_MASTER
            ON HRMS.HR_PROMOTION_LETTER_RECIPIENT (LETTER_RECIPIENT_ID)
    ~';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE <> -955 THEN
            RAISE;
        END IF;
END;
/
