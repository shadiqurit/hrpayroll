CREATE OR REPLACE PACKAGE HRMS.PKG_HR_CONTRACT_RENEWAL AS

    PROCEDURE CREATE_DRAFT (
        P_EMP_ID             IN  NUMBER,
        P_CURRENT_FROM_DATE  IN  DATE,
        P_CURRENT_TO_DATE    IN  DATE,
        P_OLD_GRADE_ID       IN  NUMBER,
        P_OLD_SCALE_ID       IN  NUMBER,
        P_OLD_STEP_NO        IN  NUMBER,
        P_NEW_FROM_DATE      IN  DATE,
        P_NEW_TO_DATE        IN  DATE,
        P_NEW_GRADE_ID       IN  NUMBER,
        P_NEW_SCALE_ID       IN  NUMBER,
        P_NEW_STEP_NO        IN  NUMBER,
        P_USER_ID            IN  NUMBER,
        P_RENEWAL_ID         OUT NUMBER
    );

    PROCEDURE SAVE_DRAFT (
        P_RENEWAL_ID     IN NUMBER,
        P_NEW_FROM_DATE  IN DATE,
        P_NEW_TO_DATE    IN DATE,
        P_NEW_GRADE_ID   IN NUMBER,
        P_NEW_SCALE_ID   IN NUMBER,
        P_NEW_STEP_NO    IN NUMBER,
        P_REASON         IN VARCHAR2,
        P_REMARKS        IN VARCHAR2,
        P_SPECIAL_TERMS  IN CLOB,
        P_SIGNATORY_ID   IN NUMBER,
        P_TEMPLATE_ID    IN NUMBER,
        P_USER_ID        IN NUMBER
    );

    PROCEDURE REFRESH_SALARY_SNAPSHOT (
        P_RENEWAL_ID IN NUMBER,
        P_USER_ID    IN NUMBER
    );

    PROCEDURE SYNC_DRAFT_TOTALS (
        P_RENEWAL_ID IN NUMBER,
        P_USER_ID    IN NUMBER
    );

    PROCEDURE SUBMIT_FOR_APPROVAL (
        P_RENEWAL_ID IN NUMBER,
        P_USER_ID    IN NUMBER
    );

    PROCEDURE RETURN_TO_DRAFT (
        P_RENEWAL_ID IN NUMBER,
        P_REASON     IN VARCHAR2,
        P_USER_ID    IN NUMBER
    );

    PROCEDURE APPROVE_RENEWAL (
        P_RENEWAL_ID IN  NUMBER,
        P_USER_ID    IN  NUMBER,
        P_LETTER_ID  OUT NUMBER
    );

    PROCEDURE FINAL_SUBMIT (
        P_RENEWAL_ID IN  NUMBER,
        P_USER_ID    IN  NUMBER,
        P_ACTION_ID  OUT NUMBER
    );

    PROCEDURE CANCEL_RENEWAL (
        P_RENEWAL_ID IN NUMBER,
        P_REASON     IN VARCHAR2,
        P_USER_ID    IN NUMBER
    );

END PKG_HR_CONTRACT_RENEWAL;
/

SHOW ERRORS;


CREATE OR REPLACE PACKAGE BODY HRMS.PKG_HR_CONTRACT_RENEWAL AS

    C_DRAFT      CONSTANT VARCHAR2(20) := 'DRAFT';
    C_SUBMITTED  CONSTANT VARCHAR2(20) := 'SUBMITTED';
    C_APPROVED   CONSTANT VARCHAR2(20) := 'APPROVED';
    C_POSTED     CONSTANT VARCHAR2(20) := 'POSTED';
    C_CANCELLED  CONSTANT VARCHAR2(20) := 'CANCELLED';

    PROCEDURE ASSERT_USER (P_USER_ID IN NUMBER) IS
    BEGIN
        IF P_USER_ID IS NULL THEN
            RAISE_APPLICATION_ERROR(-20700, 'Numeric application user ID is required.');
        END IF;
    END ASSERT_USER;

    FUNCTION BN_DIGITS (P_VALUE IN VARCHAR2) RETURN VARCHAR2 IS
    BEGIN
        RETURN TRANSLATE(P_VALUE, '0123456789', '০১২৩৪৫৬৭৮৯');
    END BN_DIGITS;

    FUNCTION HTML (P_VALUE IN VARCHAR2) RETURN VARCHAR2 IS
        L_VALUE VARCHAR2(32767) := NVL(P_VALUE, '');
    BEGIN
        L_VALUE := REPLACE(L_VALUE, '&', '&amp;');
        L_VALUE := REPLACE(L_VALUE, '<', '&lt;');
        L_VALUE := REPLACE(L_VALUE, '>', '&gt;');
        L_VALUE := REPLACE(L_VALUE, '"', '&quot;');
        L_VALUE := REPLACE(L_VALUE, '''', '&#39;');
        RETURN L_VALUE;
    END HTML;

    FUNCTION MONEY (P_AMOUNT IN NUMBER) RETURN VARCHAR2 IS
    BEGIN
        RETURN TO_CHAR(
            NVL(P_AMOUNT, 0),
            'FM999G999G999G990',
            'NLS_NUMERIC_CHARACTERS=''.,'''
        );
    END MONEY;

    FUNCTION BN_DATE (P_DATE IN DATE) RETURN VARCHAR2 IS
        L_MONTH VARCHAR2(30);
    BEGIN
        L_MONTH := CASE TO_CHAR(P_DATE, 'MM')
            WHEN '01' THEN 'জানুয়ারি'
            WHEN '02' THEN 'ফেব্রুয়ারি'
            WHEN '03' THEN 'মার্চ'
            WHEN '04' THEN 'এপ্রিল'
            WHEN '05' THEN 'মে'
            WHEN '06' THEN 'জুন'
            WHEN '07' THEN 'জুলাই'
            WHEN '08' THEN 'আগস্ট'
            WHEN '09' THEN 'সেপ্টেম্বর'
            WHEN '10' THEN 'অক্টোবর'
            WHEN '11' THEN 'নভেম্বর'
            WHEN '12' THEN 'ডিসেম্বর'
        END;
        RETURN BN_DIGITS(TO_CHAR(P_DATE, 'DD')) || ' ' || L_MONTH || ', '
               || BN_DIGITS(TO_CHAR(P_DATE, 'YYYY')) || ' খ্রি.';
    END BN_DATE;

    PROCEDURE WRITE_AUDIT (
        P_RENEWAL_ID  IN NUMBER,
        P_EVENT_TYPE  IN VARCHAR2,
        P_FROM_STATUS IN VARCHAR2,
        P_TO_STATUS   IN VARCHAR2,
        P_REMARKS     IN VARCHAR2,
        P_USER_ID     IN NUMBER
    ) IS
    BEGIN
        INSERT INTO HRMS.HR_CONTRACT_RENEWAL_AUDIT (
            RENEWAL_ID, EVENT_TYPE, FROM_STATUS, TO_STATUS,
            EVENT_REMARKS, EVENT_BY, EVENT_DATE
        ) VALUES (
            P_RENEWAL_ID, P_EVENT_TYPE, P_FROM_STATUS, P_TO_STATUS,
            P_REMARKS, P_USER_ID, SYSDATE
        );
    END WRITE_AUDIT;

    PROCEDURE ASSERT_DATES (
        P_CURRENT_TO_DATE IN DATE,
        P_NEW_FROM_DATE   IN DATE,
        P_NEW_TO_DATE     IN DATE
    ) IS
        L_MONTHS NUMBER;
    BEGIN
        IF P_NEW_FROM_DATE IS NULL OR P_NEW_TO_DATE IS NULL THEN
            RAISE_APPLICATION_ERROR(-20701, 'New contract from and to dates are required.');
        END IF;

        IF TRUNC(P_NEW_TO_DATE) < TRUNC(P_NEW_FROM_DATE) THEN
            RAISE_APPLICATION_ERROR(-20702, 'New contract end date cannot be before its start date.');
        END IF;

        IF P_CURRENT_TO_DATE IS NOT NULL
           AND TRUNC(P_NEW_FROM_DATE) <> TRUNC(P_CURRENT_TO_DATE) + 1
        THEN
            RAISE_APPLICATION_ERROR(
                -20703,
                'The renewed term must start on the day after the current contract ends.'
            );
        END IF;

        L_MONTHS := MONTHS_BETWEEN(TRUNC(P_NEW_TO_DATE) + 1,
                                  TRUNC(P_NEW_FROM_DATE));
        IF L_MONTHS <= 0 OR L_MONTHS <> TRUNC(L_MONTHS) THEN
            RAISE_APPLICATION_ERROR(
                -20704,
                'The renewed term must contain a whole number of calendar months.'
            );
        END IF;
    END ASSERT_DATES;

    PROCEDURE GET_SCALE_VALUES (
        P_GRADE_ID      IN  NUMBER,
        P_SCALE_ID      IN  NUMBER,
        P_STEP_NO       IN  NUMBER,
        P_EFFECTIVE     IN  DATE,
        P_BASIC         OUT NUMBER,
        P_GRADE_TEXT    OUT VARCHAR2,
        P_PAY_SCALE     OUT VARCHAR2
    ) IS
        L_GRADE_ORDER   HRMS.JOB_GRADES.GRADE_ORDER%TYPE;
        L_GRADE_CODE    HRMS.JOB_GRADES.GRADE_CODE%TYPE;
        L_START_BASIC   HRMS.PAY_SCALE_MASTER.START_BASIC%TYPE;
        L_INCREMENT_1   HRMS.PAY_SCALE_MASTER.INCREMENT_1%TYPE;
        L_EB_BASIC      HRMS.PAY_SCALE_MASTER.EB_BASIC%TYPE;
        L_INCREMENT_2   HRMS.PAY_SCALE_MASTER.INCREMENT_2%TYPE;
        L_MAX_BASIC     HRMS.PAY_SCALE_MASTER.MAX_BASIC%TYPE;
    BEGIN
        IF P_GRADE_ID IS NULL OR P_SCALE_ID IS NULL OR P_STEP_NO IS NULL THEN
            RAISE_APPLICATION_ERROR(-20705, 'New grade, pay scale, and step are required.');
        END IF;

        SELECT D.BASIC_AMOUNT,
               G.GRADE_ORDER,
               G.GRADE_CODE,
               M.START_BASIC,
               M.INCREMENT_1,
               M.EB_BASIC,
               M.INCREMENT_2,
               M.MAX_BASIC
          INTO P_BASIC,
               L_GRADE_ORDER,
               L_GRADE_CODE,
               L_START_BASIC,
               L_INCREMENT_1,
               L_EB_BASIC,
               L_INCREMENT_2,
               L_MAX_BASIC
          FROM HRMS.PAY_SCALE_MASTER M
          JOIN HRMS.PAY_SCALE_DETAIL D ON D.SCALE_ID = M.SCALE_ID
          JOIN HRMS.JOB_GRADES G ON G.ID = M.GRADE_ID
         WHERE M.SCALE_ID = P_SCALE_ID
           AND M.GRADE_ID = P_GRADE_ID
           AND D.STEP_NO = P_STEP_NO
           AND M.IS_ACTIVE = 'Y'
           AND (M.EFFECTIVE_FROM IS NULL OR M.EFFECTIVE_FROM <= TRUNC(P_EFFECTIVE))
           AND (M.EFFECTIVE_TO IS NULL OR M.EFFECTIVE_TO >= TRUNC(P_EFFECTIVE));

        P_GRADE_TEXT := NVL(TO_CHAR(L_GRADE_ORDER), L_GRADE_CODE);
        IF P_GRADE_TEXT IS NULL THEN
            RAISE_APPLICATION_ERROR(-20742, 'Selected grade has no grade order or grade code.');
        END IF;
        P_PAY_SCALE := MONEY(L_START_BASIC)
                       || '-' || MONEY(L_INCREMENT_1)
                       || '-' || MONEY(L_EB_BASIC)
                       || '-EB-' || MONEY(L_INCREMENT_2)
                       || '-' || MONEY(L_MAX_BASIC);
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(
                -20706,
                'The selected active pay scale/step is not valid for the grade and renewal date.'
            );
    END GET_SCALE_VALUES;

    PROCEDURE CALCULATE_TOTALS (
        P_RENEWAL_ID IN  NUMBER,
        P_OLD_BASIC  OUT NUMBER,
        P_NEW_BASIC  OUT NUMBER,
        P_OLD_GROSS  OUT NUMBER,
        P_NEW_GROSS  OUT NUMBER
    ) IS
        L_DETAIL_COUNT PLS_INTEGER;
        L_BASIC_COUNT  PLS_INTEGER;
        L_BAD_COUNT    PLS_INTEGER;
    BEGIN
        SELECT COUNT(*),
               COUNT(CASE
                         WHEN LPAD(TRIM(HEADCODE), 3, '0') = '001' OR SLNO = 1
                         THEN 1
                     END),
               NVL(MAX(CASE
                         WHEN LPAD(TRIM(HEADCODE), 3, '0') = '001' OR SLNO = 1
                         THEN OLD_AMOUNT
                       END), 0),
               NVL(MAX(CASE
                         WHEN LPAD(TRIM(HEADCODE), 3, '0') = '001' OR SLNO = 1
                         THEN NEW_AMOUNT
                       END), 0),
               NVL(SUM(CASE WHEN NVL(HEAD_TYPE, 'EARNING') = 'EARNING'
                            THEN OLD_AMOUNT ELSE 0 END), 0),
               NVL(SUM(CASE WHEN NVL(HEAD_TYPE, 'EARNING') = 'EARNING'
                            THEN NEW_AMOUNT ELSE 0 END), 0)
          INTO L_DETAIL_COUNT,
               L_BASIC_COUNT,
               P_OLD_BASIC,
               P_NEW_BASIC,
               P_OLD_GROSS,
               P_NEW_GROSS
          FROM HRMS.HR_CONTRACT_RENEWAL_SALARY
         WHERE RENEWAL_ID = P_RENEWAL_ID;

        IF L_DETAIL_COUNT = 0 THEN
            RAISE_APPLICATION_ERROR(-20707, 'At least one salary detail is required.');
        ELSIF L_BASIC_COUNT <> 1 THEN
            RAISE_APPLICATION_ERROR(-20708, 'Exactly one Basic Salary head is required.');
        END IF;

        SELECT COUNT(*)
          INTO L_BAD_COUNT
          FROM HRMS.HR_CONTRACT_RENEWAL_SALARY
         WHERE RENEWAL_ID = P_RENEWAL_ID
           AND (SLNO IS NULL OR HEADCODE IS NULL
                OR OLD_AMOUNT IS NULL OR OLD_AMOUNT < 0
                OR NEW_AMOUNT IS NULL OR NEW_AMOUNT < 0);

        IF L_BAD_COUNT > 0 THEN
            RAISE_APPLICATION_ERROR(-20709, 'Salary details contain a missing head or invalid amount.');
        END IF;

        SELECT COUNT(*)
          INTO L_BAD_COUNT
          FROM HRMS.HR_CONTRACT_RENEWAL_SALARY D
         WHERE D.RENEWAL_ID = P_RENEWAL_ID
           AND NOT EXISTS (
               SELECT 1
                 FROM HRMS.ALLOWANCE_HEAD AH
                WHERE AH.HEAD_ID = D.SLNO
                  AND LPAD(TRIM(AH.HEAD_CODE), 3, '0') =
                      LPAD(TRIM(D.HEADCODE), 3, '0')
                  AND AH.HEAD_TYPE = D.HEAD_TYPE
           );

        IF L_BAD_COUNT > 0 THEN
            RAISE_APPLICATION_ERROR(
                -20739,
                'Every salary detail must use a valid Allowance Head and matching head code.'
            );
        END IF;
    END CALCULATE_TOTALS;

    PROCEDURE APPLY_SCALE_BASIC (
        P_RENEWAL_ID IN NUMBER,
        P_BASIC      IN NUMBER,
        P_USER_ID    IN NUMBER
    ) IS
        L_COUNT PLS_INTEGER;
    BEGIN
        UPDATE HRMS.HR_CONTRACT_RENEWAL_SALARY
           SET NEW_AMOUNT   = P_BASIC,
               UPDATED_BY   = P_USER_ID,
               UPDATED_DATE = SYSDATE
         WHERE RENEWAL_ID = P_RENEWAL_ID
           AND (LPAD(TRIM(HEADCODE), 3, '0') = '001' OR SLNO = 1);

        L_COUNT := SQL%ROWCOUNT;
        IF L_COUNT <> 1 THEN
            RAISE_APPLICATION_ERROR(
                -20708,
                'Exactly one Basic Salary head must exist before a pay-scale basic can be applied.'
            );
        END IF;
    END APPLY_SCALE_BASIC;

    PROCEDURE CREATE_DRAFT (
        P_EMP_ID             IN  NUMBER,
        P_CURRENT_FROM_DATE  IN  DATE,
        P_CURRENT_TO_DATE    IN  DATE,
        P_OLD_GRADE_ID       IN  NUMBER,
        P_OLD_SCALE_ID       IN  NUMBER,
        P_OLD_STEP_NO        IN  NUMBER,
        P_NEW_FROM_DATE      IN  DATE,
        P_NEW_TO_DATE        IN  DATE,
        P_NEW_GRADE_ID       IN  NUMBER,
        P_NEW_SCALE_ID       IN  NUMBER,
        P_NEW_STEP_NO        IN  NUMBER,
        P_USER_ID            IN  NUMBER,
        P_RENEWAL_ID         OUT NUMBER
    ) IS
        L_CURRENT_FROM       DATE;
        L_CURRENT_TO         DATE;
        L_OLD_GRADE_ID       NUMBER;
        L_OLD_SCALE_ID       NUMBER;
        L_OLD_STEP_NO        NUMBER;
        L_BASIC              NUMBER;
        L_GRADE_TEXT         VARCHAR2(100);
        L_PAY_SCALE          VARCHAR2(300);
        L_EMP_CODE           VARCHAR2(30);
        L_EMP_NAME           VARCHAR2(200);
        L_DESIGNATION        VARCHAR2(150);
        L_DEPARTMENT         VARCHAR2(150);
        L_LOCATION           VARCHAR2(150);
        L_ADDRESS            VARCHAR2(500);
        L_COMPANY            VARCHAR2(200);
        L_OLD_BASIC          NUMBER;
        L_NEW_BASIC          NUMBER;
        L_OLD_GROSS          NUMBER;
        L_NEW_GROSS          NUMBER;
        L_COUNT              PLS_INTEGER;
    BEGIN
        ASSERT_USER(P_USER_ID);

        IF P_EMP_ID IS NULL THEN
            RAISE_APPLICATION_ERROR(-20710, 'Employee is required.');
        END IF;

        SELECT COUNT(*) INTO L_COUNT
          FROM HRMS.HR_CONTRACT_RENEWAL
         WHERE EMP_ID = P_EMP_ID
           AND APPROVAL_STATUS IN (C_DRAFT, C_SUBMITTED, C_APPROVED);

        IF L_COUNT > 0 THEN
            RAISE_APPLICATION_ERROR(-20711, 'This employee already has an unfinished renewal.');
        END IF;

        BEGIN
            SELECT CONTRACT_FROM_DATE, CONTRACT_TO_DATE,
                   GRADE_ID, SCALE_ID, STEP_NO
              INTO L_CURRENT_FROM, L_CURRENT_TO,
                   L_OLD_GRADE_ID, L_OLD_SCALE_ID, L_OLD_STEP_NO
              FROM HRMS.HR_EMPLOYEE_CONTRACT
             WHERE EMP_ID = P_EMP_ID
               AND CONTRACT_STATUS = 'ACTIVE'
             FOR UPDATE NOWAIT;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                IF P_CURRENT_FROM_DATE IS NULL OR P_CURRENT_TO_DATE IS NULL
                   OR P_OLD_GRADE_ID IS NULL OR P_OLD_SCALE_ID IS NULL
                   OR P_OLD_STEP_NO IS NULL
                THEN
                    RAISE_APPLICATION_ERROR(
                        -20712,
                        'First renewal requires the employee current contract dates, grade, scale, and step.'
                    );
                END IF;

                IF TRUNC(P_CURRENT_TO_DATE) < TRUNC(P_CURRENT_FROM_DATE) THEN
                    RAISE_APPLICATION_ERROR(-20713, 'Current contract dates are invalid.');
                END IF;

                L_CURRENT_FROM := TRUNC(P_CURRENT_FROM_DATE);
                L_CURRENT_TO   := TRUNC(P_CURRENT_TO_DATE);
                L_OLD_GRADE_ID := P_OLD_GRADE_ID;
                L_OLD_SCALE_ID := P_OLD_SCALE_ID;
                L_OLD_STEP_NO  := P_OLD_STEP_NO;

                INSERT INTO HRMS.HR_EMPLOYEE_CONTRACT (
                    EMP_ID, CONTRACT_FROM_DATE, CONTRACT_TO_DATE,
                    GRADE_ID, SCALE_ID, STEP_NO, CONTRACT_STATUS,
                    CREATED_BY, CREATED_DATE
                ) VALUES (
                    P_EMP_ID, L_CURRENT_FROM, L_CURRENT_TO,
                    L_OLD_GRADE_ID, L_OLD_SCALE_ID, L_OLD_STEP_NO, 'ACTIVE',
                    P_USER_ID, SYSDATE
                );
        END;

        ASSERT_DATES(L_CURRENT_TO, P_NEW_FROM_DATE, P_NEW_TO_DATE);
        GET_SCALE_VALUES(P_NEW_GRADE_ID, P_NEW_SCALE_ID, P_NEW_STEP_NO,
                         P_NEW_FROM_DATE, L_BASIC, L_GRADE_TEXT, L_PAY_SCALE);

        BEGIN
            SELECT E.EMP_ID,
                   TRIM(E.F_NAME || ' ' || E.L_NAME),
                   D.DESIGNATION,
                   DP.DEPT_NAME,
                   L.NAME,
                   E.ADDRESS,
                   C.NAME
              INTO L_EMP_CODE,
                   L_EMP_NAME,
                   L_DESIGNATION,
                   L_DEPARTMENT,
                   L_LOCATION,
                   L_ADDRESS,
                   L_COMPANY
              FROM HRMS.EMPLOYEES E
              LEFT JOIN HRMS.DESIGNATIONS D ON D.ID = E.DESIG_ID
              LEFT JOIN HRMS.DEPARTMENTS DP ON DP.ID = E.DEPT_ID
              LEFT JOIN HRMS.LOCATIONS L ON L.ID = E.LOC_ID
              LEFT JOIN HRMS.COMPANY C ON C.ID = E.COM_ID
             WHERE E.ID = P_EMP_ID;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(-20714, 'Employee was not found.');
        END;

        INSERT INTO HRMS.HR_CONTRACT_RENEWAL (
            RENEWAL_NO, EMP_ID,
            EMP_CODE_SNAPSHOT, EMP_NAME_SNAPSHOT, DESIGNATION_SNAPSHOT,
            DEPARTMENT_SNAPSHOT, LOCATION_SNAPSHOT, ADDRESS_SNAPSHOT,
            COMPANY_SNAPSHOT, GRADE_SNAPSHOT, PAY_SCALE_SNAPSHOT,
            CURRENT_FROM_DATE, CURRENT_TO_DATE, NEW_FROM_DATE, NEW_TO_DATE,
            OLD_GRADE_ID, NEW_GRADE_ID, OLD_SCALE_ID, NEW_SCALE_ID,
            OLD_STEP_NO, NEW_STEP_NO, APPROVAL_STATUS, VERSION_NO,
            PREPARED_BY, PREPARED_DATE, CREATED_BY, CREATED_DATE
        ) VALUES (
            NULL, P_EMP_ID,
            L_EMP_CODE, L_EMP_NAME, L_DESIGNATION,
            L_DEPARTMENT, L_LOCATION, L_ADDRESS,
            L_COMPANY, L_GRADE_TEXT, L_PAY_SCALE,
            L_CURRENT_FROM, L_CURRENT_TO,
            TRUNC(P_NEW_FROM_DATE), TRUNC(P_NEW_TO_DATE),
            L_OLD_GRADE_ID, P_NEW_GRADE_ID, L_OLD_SCALE_ID, P_NEW_SCALE_ID,
            L_OLD_STEP_NO, P_NEW_STEP_NO, C_DRAFT, 0,
            P_USER_ID, SYSDATE, P_USER_ID, SYSDATE
        ) RETURNING RENEWAL_ID INTO P_RENEWAL_ID;

        INSERT INTO HRMS.HR_CONTRACT_RENEWAL_SALARY (
            RENEWAL_ID, EMP_ID, SALS_ID, SLNO, HEADCODE, HEAD_NAME,
            HEAD_TYPE, PRINT_ORDER, OLD_AMOUNT, NEW_AMOUNT,
            INCLUDE_IN_LETTER, IS_POSTED, CREATED_BY, CREATED_DATE
        )
        SELECT P_RENEWAL_ID,
               P_EMP_ID,
               S.SALS_ID,
               S.SLNO,
               S.HEADCODE,
               AH.HEAD_NAME,
               AH.HEAD_TYPE,
               AH.PRINT_ORDER,
               NVL(S.AMOUNT, 0),
               NVL(S.AMOUNT, 0),
               CASE WHEN AH.HEAD_TYPE = 'EARNING' THEN 'Y' ELSE 'N' END,
               'N',
               P_USER_ID,
               SYSDATE
          FROM HRMS.EMP_SALARY_STRUCTURE S
          LEFT JOIN HRMS.ALLOWANCE_HEAD AH ON AH.HEAD_ID = S.SLNO
         WHERE S.EMPLOYEE_ID = P_EMP_ID
           AND NVL(S.IS_ACTIVE, 'Y') = 'Y';

        IF SQL%ROWCOUNT = 0 THEN
            RAISE_APPLICATION_ERROR(-20715, 'Employee has no active salary structure to renew.');
        END IF;

        APPLY_SCALE_BASIC(P_RENEWAL_ID, L_BASIC, P_USER_ID);
        CALCULATE_TOTALS(P_RENEWAL_ID, L_OLD_BASIC, L_NEW_BASIC,
                         L_OLD_GROSS, L_NEW_GROSS);

        UPDATE HRMS.HR_CONTRACT_RENEWAL
           SET OLD_BASIC = L_OLD_BASIC,
               NEW_BASIC = L_NEW_BASIC,
               OLD_GROSS = L_OLD_GROSS,
               NEW_GROSS = L_NEW_GROSS
         WHERE RENEWAL_ID = P_RENEWAL_ID;

        /* Default copy list. Page 521 can edit this list before submit. */
        INSERT INTO HRMS.HR_CONTRACT_RENEW_RECIPIENT (
            RENEWAL_ID, SECTION_TYPE, LETTER_RECIPIENT_ID,
            DISPLAY_ORDER, IS_ACTIVE, CREATED_BY, CREATED_DATE
        )
        SELECT P_RENEWAL_ID, 'COPY', R.LETTER_RECIPIENT_ID,
               R.DISPLAY_ORDER, 'Y', P_USER_ID, SYSDATE
          FROM HRMS.HR_LETTER_RECIPIENT R
         WHERE R.IS_ACTIVE = 'Y'
           AND R.RECIPIENT_CODE IN
               ('MD_BOARD_INFO', 'ADMIN_CIVIL', 'ACCOUNTS_PAYROLL',
                'PERSONAL_FILE', 'OFFICE_COPY');

        WRITE_AUDIT(P_RENEWAL_ID, 'CREATE', NULL, C_DRAFT,
                    'Contract renewal draft created.', P_USER_ID);

    EXCEPTION
        WHEN DUP_VAL_ON_INDEX THEN
            RAISE_APPLICATION_ERROR(-20711, 'This employee already has an unfinished renewal.');
        WHEN OTHERS THEN
            IF SQLCODE = -54 THEN
                RAISE_APPLICATION_ERROR(-20716, 'The employee contract is being edited by another user.');
            ELSE
                RAISE;
            END IF;
    END CREATE_DRAFT;

    PROCEDURE SAVE_DRAFT (
        P_RENEWAL_ID     IN NUMBER,
        P_NEW_FROM_DATE  IN DATE,
        P_NEW_TO_DATE    IN DATE,
        P_NEW_GRADE_ID   IN NUMBER,
        P_NEW_SCALE_ID   IN NUMBER,
        P_NEW_STEP_NO    IN NUMBER,
        P_REASON         IN VARCHAR2,
        P_REMARKS        IN VARCHAR2,
        P_SPECIAL_TERMS  IN CLOB,
        P_SIGNATORY_ID   IN NUMBER,
        P_TEMPLATE_ID    IN NUMBER,
        P_USER_ID        IN NUMBER
    ) IS
        L_STATUS          VARCHAR2(20);
        L_CURRENT_TO      DATE;
        L_BASIC           NUMBER;
        L_GRADE_TEXT      VARCHAR2(100);
        L_PAY_SCALE       VARCHAR2(300);
        L_OLD_BASIC       NUMBER;
        L_NEW_BASIC       NUMBER;
        L_OLD_GROSS       NUMBER;
        L_NEW_GROSS       NUMBER;
    BEGIN
        ASSERT_USER(P_USER_ID);

        SELECT APPROVAL_STATUS, CURRENT_TO_DATE
          INTO L_STATUS, L_CURRENT_TO
          FROM HRMS.HR_CONTRACT_RENEWAL
         WHERE RENEWAL_ID = P_RENEWAL_ID
         FOR UPDATE NOWAIT;

        IF L_STATUS <> C_DRAFT THEN
            RAISE_APPLICATION_ERROR(-20717, 'Only a DRAFT renewal can be edited.');
        END IF;

        ASSERT_DATES(L_CURRENT_TO, P_NEW_FROM_DATE, P_NEW_TO_DATE);
        GET_SCALE_VALUES(P_NEW_GRADE_ID, P_NEW_SCALE_ID, P_NEW_STEP_NO,
                         P_NEW_FROM_DATE, L_BASIC, L_GRADE_TEXT, L_PAY_SCALE);

        UPDATE HRMS.HR_CONTRACT_RENEWAL
           SET NEW_FROM_DATE      = TRUNC(P_NEW_FROM_DATE),
               NEW_TO_DATE        = TRUNC(P_NEW_TO_DATE),
               NEW_GRADE_ID       = P_NEW_GRADE_ID,
               NEW_SCALE_ID       = P_NEW_SCALE_ID,
               NEW_STEP_NO        = P_NEW_STEP_NO,
               GRADE_SNAPSHOT     = L_GRADE_TEXT,
               PAY_SCALE_SNAPSHOT = L_PAY_SCALE,
               REASON             = P_REASON,
               REMARKS            = P_REMARKS,
               SPECIAL_TERMS      = P_SPECIAL_TERMS,
               SIGNATORY_ID       = P_SIGNATORY_ID,
               TEMPLATE_ID        = P_TEMPLATE_ID,
               UPDATED_BY         = P_USER_ID,
               UPDATED_DATE       = SYSDATE,
               VERSION_NO         = VERSION_NO + 1
         WHERE RENEWAL_ID = P_RENEWAL_ID;

        /* A scale/step change always resets Basic to the authoritative scale
           value. Other heads remain explicit Page 521 payroll decisions. */
        APPLY_SCALE_BASIC(P_RENEWAL_ID, L_BASIC, P_USER_ID);
        CALCULATE_TOTALS(P_RENEWAL_ID, L_OLD_BASIC, L_NEW_BASIC,
                         L_OLD_GROSS, L_NEW_GROSS);

        UPDATE HRMS.HR_CONTRACT_RENEWAL
           SET OLD_BASIC = L_OLD_BASIC,
               NEW_BASIC = L_NEW_BASIC,
               OLD_GROSS = L_OLD_GROSS,
               NEW_GROSS = L_NEW_GROSS
         WHERE RENEWAL_ID = P_RENEWAL_ID;

        WRITE_AUDIT(P_RENEWAL_ID, 'SAVE', C_DRAFT, C_DRAFT,
                    'Draft header and totals saved.', P_USER_ID);
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20718, 'Renewal was not found.');
        WHEN OTHERS THEN
            IF SQLCODE = -54 THEN
                RAISE_APPLICATION_ERROR(-20719, 'The renewal is being edited by another user.');
            ELSE
                RAISE;
            END IF;
    END SAVE_DRAFT;

    PROCEDURE REFRESH_SALARY_SNAPSHOT (
        P_RENEWAL_ID IN NUMBER,
        P_USER_ID    IN NUMBER
    ) IS
        L_STATUS       VARCHAR2(20);
        L_EMP_ID       NUMBER;
        L_NEW_GRADE_ID NUMBER;
        L_NEW_SCALE_ID NUMBER;
        L_NEW_STEP_NO  NUMBER;
        L_NEW_FROM     DATE;
        L_BASIC        NUMBER;
        L_GRADE_TEXT   VARCHAR2(100);
        L_PAY_SCALE    VARCHAR2(300);
    BEGIN
        ASSERT_USER(P_USER_ID);

        SELECT APPROVAL_STATUS, EMP_ID, NEW_GRADE_ID, NEW_SCALE_ID,
               NEW_STEP_NO, NEW_FROM_DATE
          INTO L_STATUS, L_EMP_ID, L_NEW_GRADE_ID, L_NEW_SCALE_ID,
               L_NEW_STEP_NO, L_NEW_FROM
          FROM HRMS.HR_CONTRACT_RENEWAL
         WHERE RENEWAL_ID = P_RENEWAL_ID
         FOR UPDATE NOWAIT;

        IF L_STATUS <> C_DRAFT THEN
            RAISE_APPLICATION_ERROR(-20717, 'Only a DRAFT renewal can refresh salary.');
        END IF;

        GET_SCALE_VALUES(L_NEW_GRADE_ID, L_NEW_SCALE_ID, L_NEW_STEP_NO,
                         L_NEW_FROM, L_BASIC, L_GRADE_TEXT, L_PAY_SCALE);

        DELETE FROM HRMS.HR_CONTRACT_RENEWAL_SALARY
         WHERE RENEWAL_ID = P_RENEWAL_ID;

        INSERT INTO HRMS.HR_CONTRACT_RENEWAL_SALARY (
            RENEWAL_ID, EMP_ID, SALS_ID, SLNO, HEADCODE, HEAD_NAME,
            HEAD_TYPE, PRINT_ORDER, OLD_AMOUNT, NEW_AMOUNT,
            INCLUDE_IN_LETTER, IS_POSTED, CREATED_BY, CREATED_DATE
        )
        SELECT P_RENEWAL_ID, L_EMP_ID, S.SALS_ID, S.SLNO, S.HEADCODE,
               AH.HEAD_NAME, AH.HEAD_TYPE, AH.PRINT_ORDER,
               NVL(S.AMOUNT, 0), NVL(S.AMOUNT, 0),
               CASE WHEN AH.HEAD_TYPE = 'EARNING' THEN 'Y' ELSE 'N' END,
               'N', P_USER_ID, SYSDATE
          FROM HRMS.EMP_SALARY_STRUCTURE S
          LEFT JOIN HRMS.ALLOWANCE_HEAD AH ON AH.HEAD_ID = S.SLNO
         WHERE S.EMPLOYEE_ID = L_EMP_ID
           AND NVL(S.IS_ACTIVE, 'Y') = 'Y';

        IF SQL%ROWCOUNT = 0 THEN
            RAISE_APPLICATION_ERROR(-20715, 'Employee has no active salary structure.');
        END IF;

        APPLY_SCALE_BASIC(P_RENEWAL_ID, L_BASIC, P_USER_ID);
        SYNC_DRAFT_TOTALS(P_RENEWAL_ID, P_USER_ID);
        WRITE_AUDIT(P_RENEWAL_ID, 'REFRESH_SALARY', C_DRAFT, C_DRAFT,
                    'Salary snapshot refreshed from live structure.', P_USER_ID);
    END REFRESH_SALARY_SNAPSHOT;

    PROCEDURE SYNC_DRAFT_TOTALS (
        P_RENEWAL_ID IN NUMBER,
        P_USER_ID    IN NUMBER
    ) IS
        L_STATUS     VARCHAR2(20);
        L_OLD_BASIC  NUMBER;
        L_NEW_BASIC  NUMBER;
        L_OLD_GROSS  NUMBER;
        L_NEW_GROSS  NUMBER;
    BEGIN
        ASSERT_USER(P_USER_ID);

        SELECT APPROVAL_STATUS
          INTO L_STATUS
          FROM HRMS.HR_CONTRACT_RENEWAL
         WHERE RENEWAL_ID = P_RENEWAL_ID
         FOR UPDATE NOWAIT;

        IF L_STATUS <> C_DRAFT THEN
            RAISE_APPLICATION_ERROR(-20717, 'Only a DRAFT renewal can recalculate totals.');
        END IF;

        CALCULATE_TOTALS(P_RENEWAL_ID, L_OLD_BASIC, L_NEW_BASIC,
                         L_OLD_GROSS, L_NEW_GROSS);

        UPDATE HRMS.HR_CONTRACT_RENEWAL
           SET OLD_BASIC   = L_OLD_BASIC,
               NEW_BASIC   = L_NEW_BASIC,
               OLD_GROSS   = L_OLD_GROSS,
               NEW_GROSS   = L_NEW_GROSS,
               UPDATED_BY  = P_USER_ID,
               UPDATED_DATE = SYSDATE,
               VERSION_NO  = VERSION_NO + 1
         WHERE RENEWAL_ID = P_RENEWAL_ID;
    END SYNC_DRAFT_TOTALS;

    PROCEDURE SUBMIT_FOR_APPROVAL (
        P_RENEWAL_ID IN NUMBER,
        P_USER_ID    IN NUMBER
    ) IS
        L_STATUS       VARCHAR2(20);
        L_SIGNATORY_ID NUMBER;
        L_TEMPLATE_ID  NUMBER;
        L_BAD_COUNT    PLS_INTEGER;
    BEGIN
        ASSERT_USER(P_USER_ID);
        SYNC_DRAFT_TOTALS(P_RENEWAL_ID, P_USER_ID);

        SELECT APPROVAL_STATUS, SIGNATORY_ID, TEMPLATE_ID
          INTO L_STATUS, L_SIGNATORY_ID, L_TEMPLATE_ID
          FROM HRMS.HR_CONTRACT_RENEWAL
         WHERE RENEWAL_ID = P_RENEWAL_ID
         FOR UPDATE NOWAIT;

        IF L_STATUS <> C_DRAFT THEN
            RAISE_APPLICATION_ERROR(-20720, 'Only a DRAFT renewal can be submitted.');
        END IF;

        IF L_SIGNATORY_ID IS NULL OR L_TEMPLATE_ID IS NULL THEN
            RAISE_APPLICATION_ERROR(-20721, 'Letter signatory and template are required before submit.');
        END IF;

        SELECT COUNT(*) INTO L_BAD_COUNT
          FROM HRMS.HR_CONTRACT_RENEWAL_SALARY
         WHERE RENEWAL_ID = P_RENEWAL_ID
           AND EMP_ID <> (SELECT EMP_ID FROM HRMS.HR_CONTRACT_RENEWAL
                           WHERE RENEWAL_ID = P_RENEWAL_ID);

        IF L_BAD_COUNT > 0 THEN
            RAISE_APPLICATION_ERROR(-20722, 'A salary row belongs to another employee.');
        END IF;

        UPDATE HRMS.HR_CONTRACT_RENEWAL
           SET APPROVAL_STATUS = C_SUBMITTED,
               SUBMITTED_BY    = P_USER_ID,
               SUBMITTED_DATE  = SYSDATE,
               UPDATED_BY      = P_USER_ID,
               UPDATED_DATE    = SYSDATE,
               VERSION_NO      = VERSION_NO + 1
         WHERE RENEWAL_ID = P_RENEWAL_ID;

        WRITE_AUDIT(P_RENEWAL_ID, 'SUBMIT', C_DRAFT, C_SUBMITTED,
                    'Submitted for approval.', P_USER_ID);
    END SUBMIT_FOR_APPROVAL;

    PROCEDURE RETURN_TO_DRAFT (
        P_RENEWAL_ID IN NUMBER,
        P_REASON     IN VARCHAR2,
        P_USER_ID    IN NUMBER
    ) IS
        L_STATUS    VARCHAR2(20);
        L_LETTER_ID NUMBER;
    BEGIN
        ASSERT_USER(P_USER_ID);
        IF TRIM(P_REASON) IS NULL THEN
            RAISE_APPLICATION_ERROR(-20723, 'Return reason is required.');
        END IF;

        SELECT APPROVAL_STATUS, LETTER_ID
          INTO L_STATUS, L_LETTER_ID
          FROM HRMS.HR_CONTRACT_RENEWAL
         WHERE RENEWAL_ID = P_RENEWAL_ID
         FOR UPDATE NOWAIT;

        IF L_STATUS NOT IN (C_SUBMITTED, C_APPROVED) THEN
            RAISE_APPLICATION_ERROR(-20724, 'Only a SUBMITTED or APPROVED renewal can return to draft.');
        END IF;

        IF L_LETTER_ID IS NOT NULL THEN
            UPDATE HRMS.HR_EMPLOYEE_LETTER
               SET STATUS = 'CANCELLED'
             WHERE LETTER_ID = L_LETTER_ID
               AND STATUS <> 'ISSUED';
        END IF;

        UPDATE HRMS.HR_CONTRACT_RENEWAL
           SET APPROVAL_STATUS = C_DRAFT,
               SUBMITTED_BY    = NULL,
               SUBMITTED_DATE  = NULL,
               APPROVED_BY     = NULL,
               APPROVED_DATE   = NULL,
               UPDATED_BY      = P_USER_ID,
               UPDATED_DATE    = SYSDATE,
               VERSION_NO      = VERSION_NO + 1
         WHERE RENEWAL_ID = P_RENEWAL_ID;

        WRITE_AUDIT(P_RENEWAL_ID, 'RETURN', L_STATUS, C_DRAFT,
                    P_REASON, P_USER_ID);
    END RETURN_TO_DRAFT;

    PROCEDURE APPROVE_RENEWAL (
        P_RENEWAL_ID IN  NUMBER,
        P_USER_ID    IN  NUMBER,
        P_LETTER_ID  OUT NUMBER
    ) IS
        L_STATUS            VARCHAR2(20);
        L_EMP_ID            NUMBER;
        L_RENEWAL_NO        VARCHAR2(30);
        L_TEMPLATE_ID       NUMBER;
        L_SIGNATORY_ID      NUMBER;
        L_OLD_LETTER_ID     NUMBER;
        L_EMP_NAME          VARCHAR2(200);
        L_EMP_CODE          VARCHAR2(30);
        L_DESIGNATION       VARCHAR2(150);
        L_DEPARTMENT        VARCHAR2(150);
        L_COMPANY           VARCHAR2(200);
        L_GRADE             VARCHAR2(100);
        L_PAY_SCALE         VARCHAR2(300);
        L_NEW_FROM          DATE;
        L_NEW_TO            DATE;
        L_SPECIAL_TERMS     CLOB;
        L_SUBJECT_TEMPLATE  VARCHAR2(500);
        L_BODY_TEMPLATE     CLOB;
        L_SUBJECT           VARCHAR2(500);
        L_BODY              CLOB;
        L_TERM              VARCHAR2(200);
        L_SPECIAL_TEXT      VARCHAR2(32767);
        L_MONTHS            NUMBER;
        L_ACTIVE_COUNT      PLS_INTEGER;
    BEGIN
        ASSERT_USER(P_USER_ID);
        P_LETTER_ID := NULL;

        SELECT APPROVAL_STATUS, EMP_ID, RENEWAL_NO, TEMPLATE_ID,
               SIGNATORY_ID, LETTER_ID,
               EMP_NAME_SNAPSHOT, EMP_CODE_SNAPSHOT,
               DESIGNATION_SNAPSHOT, DEPARTMENT_SNAPSHOT,
               COMPANY_SNAPSHOT, GRADE_SNAPSHOT, PAY_SCALE_SNAPSHOT,
               NEW_FROM_DATE, NEW_TO_DATE, SPECIAL_TERMS
          INTO L_STATUS, L_EMP_ID, L_RENEWAL_NO, L_TEMPLATE_ID,
               L_SIGNATORY_ID, L_OLD_LETTER_ID,
               L_EMP_NAME, L_EMP_CODE,
               L_DESIGNATION, L_DEPARTMENT,
               L_COMPANY, L_GRADE, L_PAY_SCALE,
               L_NEW_FROM, L_NEW_TO, L_SPECIAL_TERMS
          FROM HRMS.HR_CONTRACT_RENEWAL
         WHERE RENEWAL_ID = P_RENEWAL_ID
         FOR UPDATE NOWAIT;

        IF L_STATUS <> C_SUBMITTED THEN
            RAISE_APPLICATION_ERROR(-20725, 'Only a SUBMITTED renewal can be approved.');
        END IF;

        SELECT COUNT(*) INTO L_ACTIVE_COUNT
          FROM HRMS.HR_LETTER_SIGNATORY
         WHERE SIGNATORY_ID = L_SIGNATORY_ID
           AND IS_ACTIVE = 'Y';
        IF L_ACTIVE_COUNT <> 1 THEN
            RAISE_APPLICATION_ERROR(-20726, 'The selected letter signatory is not active.');
        END IF;

        SELECT COUNT(*) INTO L_ACTIVE_COUNT
          FROM HRMS.HR_CONTRACT_RENEW_RECIPIENT X
          JOIN HRMS.HR_LETTER_RECIPIENT M
            ON M.LETTER_RECIPIENT_ID = X.LETTER_RECIPIENT_ID
         WHERE X.RENEWAL_ID = P_RENEWAL_ID
           AND X.IS_ACTIVE = 'Y'
           AND M.IS_ACTIVE <> 'Y';

        IF L_ACTIVE_COUNT > 0 THEN
            RAISE_APPLICATION_ERROR(-20740, 'One or more selected letter recipients are inactive.');
        END IF;

        SELECT SUBJECT_TEMPLATE, BODY_TEMPLATE
          INTO L_SUBJECT_TEMPLATE, L_BODY_TEMPLATE
          FROM HRMS.HR_LETTER_TEMPLATE
         WHERE TEMPLATE_ID = L_TEMPLATE_ID
           AND ACTION_TYPE = 'CONTRACT_RENEWAL'
           AND IS_ACTIVE = 'Y';

        L_MONTHS := MONTHS_BETWEEN(TRUNC(L_NEW_TO) + 1, TRUNC(L_NEW_FROM));
        IF L_MONTHS = 12 THEN
            L_TERM := '০১ (এক) বছর';
        ELSE
            L_TERM := BN_DIGITS(TO_CHAR(L_MONTHS, 'FM990')) || ' মাস';
        END IF;

        L_SPECIAL_TEXT := CASE
            WHEN L_SPECIAL_TERMS IS NULL THEN NULL
            ELSE '<strong>বিশেষ শর্ত:</strong> '
                 || HTML(DBMS_LOB.SUBSTR(L_SPECIAL_TERMS, 30000, 1))
        END;

        L_SUBJECT := REPLACE(L_SUBJECT_TEMPLATE, '#EMP_NAME#', L_EMP_NAME);

        L_BODY := L_BODY_TEMPLATE;
        L_BODY := REPLACE(L_BODY, '#EMP_NAME#', HTML(L_EMP_NAME));
        L_BODY := REPLACE(L_BODY, '#EMP_CODE#', HTML(L_EMP_CODE));
        L_BODY := REPLACE(L_BODY, '#DESIGNATION#', HTML(L_DESIGNATION));
        L_BODY := REPLACE(L_BODY, '#DEPARTMENT#', HTML(L_DEPARTMENT));
        L_BODY := REPLACE(L_BODY, '#COMPANY_NAME_BN#', HTML(L_COMPANY));
        L_BODY := REPLACE(L_BODY, '#CONTRACT_TERM_BN#', L_TERM);
        L_BODY := REPLACE(L_BODY, '#NEW_FROM_DATE_BN#', BN_DATE(L_NEW_FROM));
        L_BODY := REPLACE(L_BODY, '#NEW_TO_DATE_BN#', BN_DATE(L_NEW_TO));
        L_BODY := REPLACE(L_BODY, '#GRADE_BN#', BN_DIGITS(L_GRADE));
        L_BODY := REPLACE(
            L_BODY,
            '#PAY_SCALE_BN#',
            BN_DIGITS(REPLACE(L_PAY_SCALE, 'EB', 'ইবি')) || '/= টাকা'
        );
        L_BODY := REPLACE(L_BODY, '#SPECIAL_TERMS#', NVL(L_SPECIAL_TEXT, ''));

        IF L_OLD_LETTER_ID IS NULL THEN
            INSERT INTO HRMS.HR_EMPLOYEE_LETTER (
                EMP_ID, ACTION_ID, CONTRACT_RENEWAL_ID, TEMPLATE_ID,
                LETTER_NO, LETTER_DATE, SUBJECT_TEXT, BODY_HTML,
                STATUS, GENERATED_BY, GENERATED_DATE,
                APPROVED_BY, APPROVED_DATE
            ) VALUES (
                L_EMP_ID, NULL, P_RENEWAL_ID, L_TEMPLATE_ID,
                L_RENEWAL_NO, SYSDATE, L_SUBJECT, L_BODY,
                'APPROVED', P_USER_ID, SYSDATE,
                P_USER_ID, SYSDATE
            ) RETURNING LETTER_ID INTO P_LETTER_ID;
        ELSE
            UPDATE HRMS.HR_EMPLOYEE_LETTER
               SET TEMPLATE_ID         = L_TEMPLATE_ID,
                   LETTER_DATE         = SYSDATE,
                   SUBJECT_TEXT        = L_SUBJECT,
                   BODY_HTML           = L_BODY,
                   STATUS              = 'APPROVED',
                   GENERATED_BY        = P_USER_ID,
                   GENERATED_DATE      = SYSDATE,
                   APPROVED_BY         = P_USER_ID,
                   APPROVED_DATE       = SYSDATE,
                   ISSUED_BY           = NULL,
                   ISSUED_DATE         = NULL
             WHERE LETTER_ID = L_OLD_LETTER_ID;
            P_LETTER_ID := L_OLD_LETTER_ID;
        END IF;

        UPDATE HRMS.HR_CONTRACT_RENEWAL
           SET LETTER_ID        = P_LETTER_ID,
               APPROVAL_STATUS = C_APPROVED,
               APPROVED_BY     = P_USER_ID,
               APPROVED_DATE   = SYSDATE,
               UPDATED_BY      = P_USER_ID,
               UPDATED_DATE    = SYSDATE,
               VERSION_NO      = VERSION_NO + 1
         WHERE RENEWAL_ID = P_RENEWAL_ID;

        WRITE_AUDIT(P_RENEWAL_ID, 'APPROVE', C_SUBMITTED, C_APPROVED,
                    'Approved and generated renewal letter.', P_USER_ID);
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20727, 'Renewal, template, or configuration was not found.');
        WHEN OTHERS THEN
            IF SQLCODE = -54 THEN
                RAISE_APPLICATION_ERROR(-20719, 'The renewal is being processed by another user.');
            ELSE
                RAISE;
            END IF;
    END APPROVE_RENEWAL;

    PROCEDURE FINAL_SUBMIT (
        P_RENEWAL_ID IN  NUMBER,
        P_USER_ID    IN  NUMBER,
        P_ACTION_ID  OUT NUMBER
    ) IS
        L_STATUS        VARCHAR2(20);
        L_EMP_ID        NUMBER;
        L_RENEWAL_NO    VARCHAR2(30);
        L_LETTER_ID     NUMBER;
        L_CURRENT_FROM  DATE;
        L_CURRENT_TO    DATE;
        L_NEW_FROM      DATE;
        L_NEW_TO        DATE;
        L_OLD_GRADE_ID  NUMBER;
        L_NEW_GRADE_ID  NUMBER;
        L_OLD_SCALE_ID  NUMBER;
        L_NEW_SCALE_ID  NUMBER;
        L_OLD_STEP_NO   NUMBER;
        L_NEW_STEP_NO   NUMBER;
        L_OLD_BASIC     NUMBER;
        L_NEW_BASIC     NUMBER;
        L_OLD_GROSS     NUMBER;
        L_NEW_GROSS     NUMBER;
        L_REASON        VARCHAR2(1000);
        L_REMARKS       VARCHAR2(1000);
        L_MASTER_FROM   DATE;
        L_MASTER_TO     DATE;
        L_MASTER_GRADE  NUMBER;
        L_MASTER_SCALE  NUMBER;
        L_MASTER_STEP   NUMBER;
        L_BAD_COUNT     PLS_INTEGER;
        L_SALS_ID       NUMBER;
        L_GRADE_VALUE   VARCHAR2(100);
        L_AFTER_GROSS   NUMBER;
        L_CALC_OLD_BASIC NUMBER;
        L_CALC_NEW_BASIC NUMBER;
        L_CALC_OLD_GROSS NUMBER;
        L_CALC_NEW_GROSS NUMBER;
    BEGIN
        ASSERT_USER(P_USER_ID);
        P_ACTION_ID := NULL;
        SAVEPOINT BEFORE_CONTRACT_POST;

        SELECT APPROVAL_STATUS, EMP_ID, RENEWAL_NO, LETTER_ID,
               CURRENT_FROM_DATE, CURRENT_TO_DATE, NEW_FROM_DATE, NEW_TO_DATE,
               OLD_GRADE_ID, NEW_GRADE_ID, OLD_SCALE_ID, NEW_SCALE_ID,
               OLD_STEP_NO, NEW_STEP_NO,
               OLD_BASIC, NEW_BASIC, OLD_GROSS, NEW_GROSS,
               REASON, REMARKS
          INTO L_STATUS, L_EMP_ID, L_RENEWAL_NO, L_LETTER_ID,
               L_CURRENT_FROM, L_CURRENT_TO, L_NEW_FROM, L_NEW_TO,
               L_OLD_GRADE_ID, L_NEW_GRADE_ID, L_OLD_SCALE_ID, L_NEW_SCALE_ID,
               L_OLD_STEP_NO, L_NEW_STEP_NO,
               L_OLD_BASIC, L_NEW_BASIC, L_OLD_GROSS, L_NEW_GROSS,
               L_REASON, L_REMARKS
          FROM HRMS.HR_CONTRACT_RENEWAL
         WHERE RENEWAL_ID = P_RENEWAL_ID
         FOR UPDATE NOWAIT;

        IF L_STATUS <> C_APPROVED THEN
            RAISE_APPLICATION_ERROR(-20728, 'Only an APPROVED renewal can be finally submitted.');
        END IF;

        IF TRUNC(L_NEW_FROM) > TRUNC(SYSDATE) THEN
            RAISE_APPLICATION_ERROR(
                -20729,
                'Future-effective renewal cannot update current salary. Final submit on or after '
                || TO_CHAR(L_NEW_FROM, 'DD-Mon-YYYY') || '.'
            );
        END IF;

        IF L_LETTER_ID IS NULL THEN
            RAISE_APPLICATION_ERROR(-20730, 'Approved renewal letter is missing.');
        END IF;

        CALCULATE_TOTALS(P_RENEWAL_ID,
                         L_CALC_OLD_BASIC, L_CALC_NEW_BASIC,
                         L_CALC_OLD_GROSS, L_CALC_NEW_GROSS);

        IF ABS(NVL(L_CALC_OLD_BASIC, 0) - NVL(L_OLD_BASIC, 0)) > 0.005
           OR ABS(NVL(L_CALC_NEW_BASIC, 0) - NVL(L_NEW_BASIC, 0)) > 0.005
           OR ABS(NVL(L_CALC_OLD_GROSS, 0) - NVL(L_OLD_GROSS, 0)) > 0.005
           OR ABS(NVL(L_CALC_NEW_GROSS, 0) - NVL(L_NEW_GROSS, 0)) > 0.005
        THEN
            RAISE_APPLICATION_ERROR(
                -20741,
                'Approved salary details no longer match the renewal totals.'
            );
        END IF;

        SELECT CONTRACT_FROM_DATE, CONTRACT_TO_DATE, GRADE_ID, SCALE_ID, STEP_NO
          INTO L_MASTER_FROM, L_MASTER_TO, L_MASTER_GRADE, L_MASTER_SCALE, L_MASTER_STEP
          FROM HRMS.HR_EMPLOYEE_CONTRACT
         WHERE EMP_ID = L_EMP_ID
           AND CONTRACT_STATUS = 'ACTIVE'
         FOR UPDATE NOWAIT;

        IF TRUNC(L_MASTER_FROM) <> TRUNC(L_CURRENT_FROM)
           OR TRUNC(L_MASTER_TO) <> TRUNC(L_CURRENT_TO)
           OR NVL(L_MASTER_GRADE, -1) <> NVL(L_OLD_GRADE_ID, -1)
           OR NVL(L_MASTER_SCALE, -1) <> NVL(L_OLD_SCALE_ID, -1)
           OR NVL(L_MASTER_STEP, -1) <> NVL(L_OLD_STEP_NO, -1)
        THEN
            RAISE_APPLICATION_ERROR(
                -20731,
                'Current employee contract changed after this renewal draft. Return it to draft and recreate it.'
            );
        END IF;

        /* Lock every current salary row before stale-snapshot validation. */
        FOR X IN (
            SELECT SALS_ID
              FROM HRMS.EMP_SALARY_STRUCTURE
             WHERE EMPLOYEE_ID = L_EMP_ID
               AND NVL(IS_ACTIVE, 'Y') = 'Y'
             FOR UPDATE NOWAIT
        ) LOOP
            NULL;
        END LOOP;

        /* Every active live head must still exist with the amount captured in
           the draft. This prevents final submit from overwriting later payroll
           changes. */
        SELECT COUNT(*) INTO L_BAD_COUNT
          FROM HRMS.EMP_SALARY_STRUCTURE S
         WHERE S.EMPLOYEE_ID = L_EMP_ID
           AND NVL(S.IS_ACTIVE, 'Y') = 'Y'
           AND NOT EXISTS (
               SELECT 1
                 FROM HRMS.HR_CONTRACT_RENEWAL_SALARY D
                WHERE D.RENEWAL_ID = P_RENEWAL_ID
                  AND D.EMP_ID = L_EMP_ID
                  AND D.SALS_ID = S.SALS_ID
                  AND D.SLNO = S.SLNO
                  AND NVL(D.OLD_AMOUNT, 0) = NVL(S.AMOUNT, 0)
           );

        IF L_BAD_COUNT > 0 THEN
            RAISE_APPLICATION_ERROR(
                -20732,
                'Live salary changed after the renewal draft. Return to draft and refresh the salary snapshot.'
            );
        END IF;

        SELECT COUNT(*) INTO L_BAD_COUNT
          FROM HRMS.HR_CONTRACT_RENEWAL_SALARY D
         WHERE D.RENEWAL_ID = P_RENEWAL_ID
           AND D.EMP_ID = L_EMP_ID
           AND D.SALS_ID IS NOT NULL
           AND NOT EXISTS (
               SELECT 1 FROM HRMS.EMP_SALARY_STRUCTURE S
                WHERE S.SALS_ID = D.SALS_ID
                  AND S.EMPLOYEE_ID = L_EMP_ID
                  AND NVL(S.IS_ACTIVE, 'Y') = 'Y'
                  AND NVL(S.AMOUNT, 0) = NVL(D.OLD_AMOUNT, 0)
           );

        IF L_BAD_COUNT > 0 THEN
            RAISE_APPLICATION_ERROR(-20732, 'A captured live salary row is stale or inactive.');
        END IF;

        INSERT INTO HRMS.HR_EMPLOYEE_ACTION (
            EMP_ID, ACTION_TYPE, ACTION_DATE, EFFECTIVE_DATE,
            OLD_BASIC, NEW_BASIC, OLD_GROSS, NEW_GROSS,
            INCREMENT_AMOUNT, INCREMENT_PERCENT,
            REASON, REMARKS, APPROVAL_STATUS,
            ENT_BY, ENT_DATE, APPROVED_BY, APPROVED_DATE
        ) VALUES (
            L_EMP_ID, 'CONTRACT_RENEWAL', SYSDATE, L_NEW_FROM,
            L_OLD_BASIC, L_NEW_BASIC, L_OLD_GROSS, L_NEW_GROSS,
            L_NEW_BASIC - L_OLD_BASIC,
            CASE WHEN NVL(L_OLD_BASIC, 0) = 0 THEN NULL
                 ELSE ROUND(((L_NEW_BASIC - L_OLD_BASIC) / L_OLD_BASIC) * 100, 2)
            END,
            NVL(L_REASON, 'Contract renewal'), L_REMARKS, 'APPROVED',
            P_USER_ID, SYSDATE, P_USER_ID, SYSDATE
        ) RETURNING ACTION_ID INTO P_ACTION_ID;

        FOR R IN (
            SELECT RENEWAL_SALARY_ID, SALS_ID, SLNO, HEADCODE, NEW_AMOUNT
              FROM HRMS.HR_CONTRACT_RENEWAL_SALARY
             WHERE RENEWAL_ID = P_RENEWAL_ID
             ORDER BY SLNO
        ) LOOP
            IF R.SALS_ID IS NOT NULL THEN
                UPDATE HRMS.EMP_SALARY_STRUCTURE
                   SET AMOUNT        = R.NEW_AMOUNT,
                       REVISION_TYPE = 'R',
                       UPDATED_BY    = P_USER_ID,
                       UPDATED_DATE  = SYSDATE
                 WHERE SALS_ID = R.SALS_ID
                   AND EMPLOYEE_ID = L_EMP_ID;
            ELSE
                BEGIN
                    SELECT SALS_ID INTO L_SALS_ID
                      FROM HRMS.EMP_SALARY_STRUCTURE
                     WHERE EMPLOYEE_ID = L_EMP_ID
                       AND SLNO = R.SLNO
                     FOR UPDATE NOWAIT;

                    RAISE_APPLICATION_ERROR(
                        -20733,
                        'A new salary detail conflicts with an existing employee salary head.'
                    );
                EXCEPTION
                    WHEN NO_DATA_FOUND THEN
                        INSERT INTO HRMS.EMP_SALARY_STRUCTURE (
                            EMPLOYEE_ID, SLNO, HEADCODE, AMOUNT,
                            REVISION_TYPE, IS_ACTIVE, CREATED_BY, CREATED_DATE
                        ) VALUES (
                            L_EMP_ID, R.SLNO, R.HEADCODE, R.NEW_AMOUNT,
                            'R', 'Y', P_USER_ID, SYSDATE
                        ) RETURNING SALS_ID INTO L_SALS_ID;

                        UPDATE HRMS.HR_CONTRACT_RENEWAL_SALARY
                           SET SALS_ID = L_SALS_ID
                         WHERE RENEWAL_SALARY_ID = R.RENEWAL_SALARY_ID;
                END;
            END IF;
        END LOOP;

        SELECT NVL(SUM(CASE WHEN AH.HEAD_TYPE = 'EARNING'
                            THEN NVL(S.AMOUNT, 0) ELSE 0 END), 0)
          INTO L_AFTER_GROSS
          FROM HRMS.EMP_SALARY_STRUCTURE S
          LEFT JOIN HRMS.ALLOWANCE_HEAD AH ON AH.HEAD_ID = S.SLNO
         WHERE S.EMPLOYEE_ID = L_EMP_ID
           AND NVL(S.IS_ACTIVE, 'Y') = 'Y';

        IF ABS(NVL(L_AFTER_GROSS, 0) - NVL(L_NEW_GROSS, 0)) > 0.005 THEN
            RAISE_APPLICATION_ERROR(-20734, 'Posted gross does not match the approved renewal gross.');
        END IF;

        SELECT NVL(GRADE_CODE, NVL(TO_CHAR(GRADE_ORDER), GRADE_NAME))
          INTO L_GRADE_VALUE
          FROM HRMS.JOB_GRADES
         WHERE ID = L_NEW_GRADE_ID;

        UPDATE HRMS.HR_EMPLOYEE_CONTRACT
           SET CONTRACT_FROM_DATE = L_NEW_FROM,
               CONTRACT_TO_DATE   = L_NEW_TO,
               GRADE_ID           = L_NEW_GRADE_ID,
               SCALE_ID           = L_NEW_SCALE_ID,
               STEP_NO            = L_NEW_STEP_NO,
               LATEST_RENEWAL_ID  = P_RENEWAL_ID,
               CONTRACT_STATUS    = 'ACTIVE',
               UPDATED_BY         = P_USER_ID,
               UPDATED_DATE       = SYSDATE
         WHERE EMP_ID = L_EMP_ID;

        UPDATE HRMS.EMPLOYEES
           SET GRADE    = L_GRADE_VALUE,
               UPD_BY  = P_USER_ID,
               UPD_DATE = SYSDATE
         WHERE ID = L_EMP_ID;

        UPDATE HRMS.HR_CONTRACT_RENEWAL_SALARY
           SET IS_POSTED  = 'Y',
               POSTED_BY  = P_USER_ID,
               POSTED_DATE = SYSDATE
         WHERE RENEWAL_ID = P_RENEWAL_ID;

        UPDATE HRMS.HR_EMPLOYEE_LETTER
           SET ACTION_ID  = P_ACTION_ID,
               STATUS     = 'ISSUED',
               ISSUED_BY  = P_USER_ID,
               ISSUED_DATE = SYSDATE
         WHERE LETTER_ID = L_LETTER_ID
           AND CONTRACT_RENEWAL_ID = P_RENEWAL_ID
           AND STATUS = 'APPROVED';

        IF SQL%ROWCOUNT <> 1 THEN
            RAISE_APPLICATION_ERROR(-20735, 'Approved renewal letter could not be issued.');
        END IF;

        UPDATE HRMS.HR_CONTRACT_RENEWAL
           SET ACTION_ID        = P_ACTION_ID,
               APPROVAL_STATUS = C_POSTED,
               POSTED_BY       = P_USER_ID,
               POSTED_DATE     = SYSDATE,
               UPDATED_BY      = P_USER_ID,
               UPDATED_DATE    = SYSDATE,
               VERSION_NO      = VERSION_NO + 1
         WHERE RENEWAL_ID = P_RENEWAL_ID;

        WRITE_AUDIT(P_RENEWAL_ID, 'FINAL_SUBMIT', C_APPROVED, C_POSTED,
                    'Salary structure and current contract updated atomically.', P_USER_ID);

    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK TO BEFORE_CONTRACT_POST;
            IF SQLCODE = -54 THEN
                RAISE_APPLICATION_ERROR(-20736, 'Employee or renewal is being processed by another user.');
            ELSE
                RAISE;
            END IF;
    END FINAL_SUBMIT;

    PROCEDURE CANCEL_RENEWAL (
        P_RENEWAL_ID IN NUMBER,
        P_REASON     IN VARCHAR2,
        P_USER_ID    IN NUMBER
    ) IS
        L_STATUS    VARCHAR2(20);
        L_LETTER_ID NUMBER;
    BEGIN
        ASSERT_USER(P_USER_ID);
        IF TRIM(P_REASON) IS NULL THEN
            RAISE_APPLICATION_ERROR(-20737, 'Cancellation reason is required.');
        END IF;

        SELECT APPROVAL_STATUS, LETTER_ID
          INTO L_STATUS, L_LETTER_ID
          FROM HRMS.HR_CONTRACT_RENEWAL
         WHERE RENEWAL_ID = P_RENEWAL_ID
         FOR UPDATE NOWAIT;

        IF L_STATUS NOT IN (C_DRAFT, C_SUBMITTED, C_APPROVED) THEN
            RAISE_APPLICATION_ERROR(-20738, 'Posted or already cancelled renewal cannot be cancelled.');
        END IF;

        IF L_LETTER_ID IS NOT NULL THEN
            UPDATE HRMS.HR_EMPLOYEE_LETTER
               SET STATUS = 'CANCELLED'
             WHERE LETTER_ID = L_LETTER_ID
               AND STATUS <> 'ISSUED';
        END IF;

        UPDATE HRMS.HR_CONTRACT_RENEWAL
           SET APPROVAL_STATUS = C_CANCELLED,
               CANCELLED_BY    = P_USER_ID,
               CANCELLED_DATE  = SYSDATE,
               REMARKS         = SUBSTR(NVL(REMARKS || CHR(10), '')
                                        || 'Cancelled: ' || P_REASON, 1, 1000),
               UPDATED_BY      = P_USER_ID,
               UPDATED_DATE    = SYSDATE,
               VERSION_NO      = VERSION_NO + 1
         WHERE RENEWAL_ID = P_RENEWAL_ID;

        WRITE_AUDIT(P_RENEWAL_ID, 'CANCEL', L_STATUS, C_CANCELLED,
                    P_REASON, P_USER_ID);
    END CANCEL_RENEWAL;

END PKG_HR_CONTRACT_RENEWAL;
/

SHOW ERRORS;
