CREATE OR REPLACE PACKAGE HRMS.PKG_HR_CONTRACT_RENEWAL AS

    /* Create one editable renewal and copy the employee's live salary. */
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

    /* Page 520 one-click preparation. Dates, grade, scale, step and salary
       details are derived from the employee's active contract/salary. */
    PROCEDURE CREATE_DUE_RENEWAL (
        P_EMP_ID       IN  NUMBER,
        P_SALARY_MODE  IN  VARCHAR2,
        P_TERM_MONTHS  IN  NUMBER,
        P_USER_ID      IN  NUMBER,
        P_RENEWAL_ID   OUT NUMBER
    );

    /* Save the editable header. Page 521 saves the salary/recipient grids first. */
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

    /* Discard proposed amounts and copy the current live salary again. */
    PROCEDURE REFRESH_SALARY_SNAPSHOT (
        P_RENEWAL_ID IN NUMBER,
        P_USER_ID    IN NUMBER
    );

    /* One final action: update salary/contract and generate the issued letter. */
    PROCEDURE FINAL_SUBMIT (
        P_RENEWAL_ID IN  NUMBER,
        P_USER_ID    IN  NUMBER,
        P_ACTION_ID  OUT NUMBER,
        P_LETTER_ID  OUT NUMBER
    );

    /* Remove an unwanted draft. Posted renewals cannot be deleted. */
    PROCEDURE DELETE_DRAFT (
        P_RENEWAL_ID IN NUMBER,
        P_USER_ID    IN NUMBER
    );

END PKG_HR_CONTRACT_RENEWAL;
/

SHOW ERRORS;


CREATE OR REPLACE PACKAGE BODY HRMS.PKG_HR_CONTRACT_RENEWAL AS

    C_DRAFT  CONSTANT VARCHAR2(20) := 'DRAFT';
    C_POSTED CONSTANT VARCHAR2(20) := 'POSTED';

    PROCEDURE ASSERT_USER (P_USER_ID IN NUMBER) IS
    BEGIN
        IF P_USER_ID IS NULL THEN
            RAISE_APPLICATION_ERROR(
                -20700,
                'Numeric application user ID is required. Pass the populated APEX USER_ID session item.'
            );
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
        L_GRADE_ORDER  HRMS.JOB_GRADES.GRADE_ORDER%TYPE;
        L_GRADE_CODE   HRMS.JOB_GRADES.GRADE_CODE%TYPE;
        L_START_BASIC  HRMS.PAY_SCALE_MASTER.START_BASIC%TYPE;
        L_INCREMENT_1  HRMS.PAY_SCALE_MASTER.INCREMENT_1%TYPE;
        L_EB_BASIC     HRMS.PAY_SCALE_MASTER.EB_BASIC%TYPE;
        L_INCREMENT_2  HRMS.PAY_SCALE_MASTER.INCREMENT_2%TYPE;
        L_MAX_BASIC    HRMS.PAY_SCALE_MASTER.MAX_BASIC%TYPE;
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
            RAISE_APPLICATION_ERROR(-20706, 'Selected grade has no grade order or grade code.');
        END IF;

        P_PAY_SCALE := MONEY(L_START_BASIC)
                       || '-' || MONEY(L_INCREMENT_1)
                       || '-' || MONEY(L_EB_BASIC)
                       || '-EB-' || MONEY(L_INCREMENT_2)
                       || '-' || MONEY(L_MAX_BASIC);
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(
                -20707,
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
               NVL(SUM(CASE WHEN HEAD_TYPE = 'EARNING'
                            THEN OLD_AMOUNT ELSE 0 END), 0),
               NVL(SUM(CASE WHEN HEAD_TYPE = 'EARNING'
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
            RAISE_APPLICATION_ERROR(-20708, 'At least one salary detail is required.');
        ELSIF L_BASIC_COUNT <> 1 THEN
            RAISE_APPLICATION_ERROR(-20709, 'Exactly one Basic Salary head is required.');
        END IF;

        SELECT COUNT(*)
          INTO L_BAD_COUNT
          FROM HRMS.HR_CONTRACT_RENEWAL_SALARY D
         WHERE D.RENEWAL_ID = P_RENEWAL_ID
           AND (
               D.SLNO IS NULL OR D.HEADCODE IS NULL
               OR D.OLD_AMOUNT IS NULL OR D.OLD_AMOUNT < 0
               OR D.NEW_AMOUNT IS NULL OR D.NEW_AMOUNT < 0
               OR NOT EXISTS (
                   SELECT 1
                     FROM HRMS.ALLOWANCE_HEAD AH
                    WHERE AH.HEAD_ID = D.SLNO
                      AND LPAD(TRIM(AH.HEAD_CODE), 3, '0') =
                          LPAD(TRIM(D.HEADCODE), 3, '0')
                      AND AH.HEAD_TYPE = D.HEAD_TYPE
               )
           );

        IF L_BAD_COUNT > 0 THEN
            RAISE_APPLICATION_ERROR(
                -20710,
                'Salary details contain an invalid amount or Allowance Head.'
            );
        END IF;
    END CALCULATE_TOTALS;

    PROCEDURE APPLY_SCALE_BASIC (
        P_RENEWAL_ID IN NUMBER,
        P_BASIC      IN NUMBER,
        P_USER_ID    IN NUMBER
    ) IS
    BEGIN
        UPDATE HRMS.HR_CONTRACT_RENEWAL_SALARY
           SET NEW_AMOUNT   = P_BASIC,
               UPDATED_BY   = P_USER_ID,
               UPDATED_DATE = SYSDATE
         WHERE RENEWAL_ID = P_RENEWAL_ID
           AND (LPAD(TRIM(HEADCODE), 3, '0') = '001' OR SLNO = 1);

        IF SQL%ROWCOUNT <> 1 THEN
            RAISE_APPLICATION_ERROR(-20709, 'Exactly one Basic Salary head is required.');
        END IF;
    END APPLY_SCALE_BASIC;

    PROCEDURE COPY_LIVE_SALARY (
        P_RENEWAL_ID IN NUMBER,
        P_EMP_ID     IN NUMBER,
        P_BASIC      IN NUMBER,
        P_USER_ID    IN NUMBER
    ) IS
        L_BAD_COUNT PLS_INTEGER;
    BEGIN
        SELECT COUNT(*)
          INTO L_BAD_COUNT
          FROM HRMS.EMP_SALARY_STRUCTURE S
          LEFT JOIN HRMS.ALLOWANCE_HEAD AH ON AH.HEAD_ID = S.SLNO
         WHERE S.EMPLOYEE_ID = P_EMP_ID
           AND NVL(S.IS_ACTIVE, 'Y') = 'Y'
           AND (S.HEADCODE IS NULL OR AH.HEAD_ID IS NULL
                OR LPAD(TRIM(AH.HEAD_CODE), 3, '0') <>
                   LPAD(TRIM(S.HEADCODE), 3, '0'));

        IF L_BAD_COUNT > 0 THEN
            RAISE_APPLICATION_ERROR(
                -20711,
                'Live salary contains a missing or mismatched Allowance Head.'
            );
        END IF;

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
          JOIN HRMS.ALLOWANCE_HEAD AH ON AH.HEAD_ID = S.SLNO
         WHERE S.EMPLOYEE_ID = P_EMP_ID
           AND NVL(S.IS_ACTIVE, 'Y') = 'Y';

        IF SQL%ROWCOUNT = 0 THEN
            RAISE_APPLICATION_ERROR(-20712, 'Employee has no active salary structure.');
        END IF;

        APPLY_SCALE_BASIC(P_RENEWAL_ID, P_BASIC, P_USER_ID);
    END COPY_LIVE_SALARY;

    /* Recalculate only salary heads that are explicitly configured on the
       selected pay scale. Unconfigured heads keep their copied live amount. */
    PROCEDURE APPLY_AUTO_SALARY (
        P_RENEWAL_ID IN NUMBER,
        P_SCALE_ID   IN NUMBER,
        P_BASIC      IN NUMBER,
        P_USER_ID    IN NUMBER
    ) IS
        L_HR         HRMS.PAY_SCALE_MASTER.HR%TYPE;
        L_CPF        HRMS.PAY_SCALE_MASTER.CPF%TYPE;
        L_PFCONT     HRMS.PAY_SCALE_MASTER.PFCONT%TYPE;
        L_CONV       HRMS.PAY_SCALE_MASTER.CONV%TYPE;
        L_MEDICAL    HRMS.PAY_SCALE_MASTER.MEDICAL%TYPE;
        L_ALLOWANCE  HRMS.PAY_SCALE_MASTER.ALLOWANCE%TYPE;
        L_SAF        HRMS.PAY_SCALE_MASTER.SAF%TYPE;
    BEGIN
        SELECT HR, CPF, PFCONT, CONV, MEDICAL, ALLOWANCE, SAF
          INTO L_HR, L_CPF, L_PFCONT, L_CONV, L_MEDICAL, L_ALLOWANCE, L_SAF
          FROM HRMS.PAY_SCALE_MASTER
         WHERE SCALE_ID = P_SCALE_ID;

        UPDATE HRMS.HR_CONTRACT_RENEWAL_SALARY
           SET NEW_AMOUNT =
                   CASE LPAD(TRIM(HEADCODE), 3, '0')
                       WHEN '001' THEN P_BASIC
                       WHEN '005' THEN
                           CASE WHEN L_HR IS NOT NULL
                                THEN ROUND(P_BASIC * L_HR / 100)
                                ELSE NEW_AMOUNT END
                       WHEN '013' THEN
                           CASE WHEN L_PFCONT IS NOT NULL
                                THEN ROUND(P_BASIC * L_PFCONT / 100)
                                ELSE NEW_AMOUNT END
                       WHEN '057' THEN
                           CASE WHEN L_CPF IS NOT NULL
                                THEN ROUND(P_BASIC * L_CPF / 100)
                                ELSE NEW_AMOUNT END
                       WHEN '007' THEN NVL(L_CONV, NEW_AMOUNT)
                       WHEN '010' THEN NVL(L_MEDICAL, NEW_AMOUNT)
                       WHEN '037' THEN NVL(L_ALLOWANCE, NEW_AMOUNT)
                       WHEN '075' THEN NVL(L_SAF, NEW_AMOUNT)
                       ELSE NEW_AMOUNT
                   END,
               UPDATED_BY   = P_USER_ID,
               UPDATED_DATE = SYSDATE
         WHERE RENEWAL_ID = P_RENEWAL_ID
           AND LPAD(TRIM(HEADCODE), 3, '0') IN
               ('001', '005', '007', '010', '013', '037', '057', '075');
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20744, 'The selected pay scale was not found.');
    END APPLY_AUTO_SALARY;

    PROCEDURE UPDATE_TOTALS (
        P_RENEWAL_ID IN NUMBER,
        P_USER_ID    IN NUMBER
    ) IS
        L_OLD_BASIC NUMBER;
        L_NEW_BASIC NUMBER;
        L_OLD_GROSS NUMBER;
        L_NEW_GROSS NUMBER;
    BEGIN
        CALCULATE_TOTALS(P_RENEWAL_ID, L_OLD_BASIC, L_NEW_BASIC,
                         L_OLD_GROSS, L_NEW_GROSS);

        UPDATE HRMS.HR_CONTRACT_RENEWAL
           SET OLD_BASIC    = L_OLD_BASIC,
               NEW_BASIC    = L_NEW_BASIC,
               OLD_GROSS    = L_OLD_GROSS,
               NEW_GROSS    = L_NEW_GROSS,
               UPDATED_BY   = P_USER_ID,
               UPDATED_DATE = SYSDATE,
               VERSION_NO   = VERSION_NO + 1
         WHERE RENEWAL_ID = P_RENEWAL_ID;
    END UPDATE_TOTALS;

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
        L_CURRENT_FROM  DATE;
        L_CURRENT_TO    DATE;
        L_OLD_GRADE_ID  NUMBER;
        L_OLD_SCALE_ID  NUMBER;
        L_OLD_STEP_NO   NUMBER;
        L_BASIC         NUMBER;
        L_GRADE_TEXT    VARCHAR2(100);
        L_PAY_SCALE     VARCHAR2(300);
        L_EMP_CODE      VARCHAR2(30);
        L_EMP_NAME      VARCHAR2(200);
        L_DESIGNATION   VARCHAR2(150);
        L_DEPARTMENT    VARCHAR2(150);
        L_LOCATION      VARCHAR2(150);
        L_ADDRESS       VARCHAR2(500);
        L_COMPANY       VARCHAR2(200);
        L_COUNT         PLS_INTEGER;
        L_BASELINE_YN   VARCHAR2(1) := 'N';
        L_SIGNATORY_ID  NUMBER;
        L_TEMPLATE_ID   NUMBER;
    BEGIN
        ASSERT_USER(P_USER_ID);

        IF P_EMP_ID IS NULL THEN
            RAISE_APPLICATION_ERROR(-20713, 'Employee is required.');
        END IF;

        SELECT COUNT(*) INTO L_COUNT
          FROM HRMS.HR_CONTRACT_RENEWAL
         WHERE EMP_ID = P_EMP_ID
           AND STATUS = C_DRAFT;

        IF L_COUNT > 0 THEN
            RAISE_APPLICATION_ERROR(-20714, 'This employee already has a renewal draft.');
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
                        -20715,
                        'First renewal requires current contract dates, grade, scale, and step.'
                    );
                END IF;

                IF TRUNC(P_CURRENT_TO_DATE) < TRUNC(P_CURRENT_FROM_DATE) THEN
                    RAISE_APPLICATION_ERROR(-20716, 'Current contract dates are invalid.');
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
                L_BASELINE_YN := 'Y';
        END;

        ASSERT_DATES(L_CURRENT_TO, P_NEW_FROM_DATE, P_NEW_TO_DATE);
        GET_SCALE_VALUES(P_NEW_GRADE_ID, P_NEW_SCALE_ID, P_NEW_STEP_NO,
                         P_NEW_FROM_DATE, L_BASIC, L_GRADE_TEXT, L_PAY_SCALE);

        BEGIN
            SELECT E.EMP_ID,
                   NVL(TRIM(E.NAME_BN), TRIM(E.F_NAME || ' ' || E.L_NAME)),
                   NVL(TRIM(D.DESIGNATION_BN), D.DESIGNATION),
                   NVL(TRIM(DP.DEPT_NAME_BN), DP.DEPT_NAME),
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
                RAISE_APPLICATION_ERROR(-20717, 'Employee was not found.');
        END;

        SELECT MIN(SIGNATORY_ID)
                   KEEP (DENSE_RANK FIRST ORDER BY DISPLAY_ORDER, SIGNATORY_ID)
          INTO L_SIGNATORY_ID
          FROM HRMS.HR_LETTER_SIGNATORY
         WHERE IS_ACTIVE = 'Y';

        SELECT MIN(TEMPLATE_ID)
                   KEEP (
                       DENSE_RANK FIRST ORDER BY
                       CASE WHEN TEMPLATE_CODE = 'CONTRACT_RENEWAL_BN' THEN 0 ELSE 1 END,
                       TEMPLATE_ID
                   )
          INTO L_TEMPLATE_ID
          FROM HRMS.HR_LETTER_TEMPLATE
         WHERE ACTION_TYPE = 'CONTRACT_RENEWAL'
           AND IS_ACTIVE = 'Y';

        INSERT INTO HRMS.HR_CONTRACT_RENEWAL (
            RENEWAL_NO, EMP_ID,
            EMP_CODE_SNAPSHOT, EMP_NAME_SNAPSHOT, DESIGNATION_SNAPSHOT,
            DEPARTMENT_SNAPSHOT, LOCATION_SNAPSHOT, ADDRESS_SNAPSHOT,
            COMPANY_SNAPSHOT, GRADE_SNAPSHOT, PAY_SCALE_SNAPSHOT,
            CURRENT_FROM_DATE, CURRENT_TO_DATE, NEW_FROM_DATE, NEW_TO_DATE,
            OLD_GRADE_ID, NEW_GRADE_ID, OLD_SCALE_ID, NEW_SCALE_ID,
            OLD_STEP_NO, NEW_STEP_NO, SALARY_MODE,
            SIGNATORY_ID, TEMPLATE_ID,
            STATUS, BASELINE_CREATED_YN, VERSION_NO,
            CREATED_BY, CREATED_DATE
        ) VALUES (
            NULL, P_EMP_ID,
            L_EMP_CODE, L_EMP_NAME, L_DESIGNATION,
            L_DEPARTMENT, L_LOCATION, L_ADDRESS,
            L_COMPANY, L_GRADE_TEXT, L_PAY_SCALE,
            L_CURRENT_FROM, L_CURRENT_TO,
            TRUNC(P_NEW_FROM_DATE), TRUNC(P_NEW_TO_DATE),
            L_OLD_GRADE_ID, P_NEW_GRADE_ID, L_OLD_SCALE_ID, P_NEW_SCALE_ID,
            L_OLD_STEP_NO, P_NEW_STEP_NO, 'MANUAL',
            L_SIGNATORY_ID, L_TEMPLATE_ID,
            C_DRAFT, L_BASELINE_YN, 0,
            P_USER_ID, SYSDATE
        ) RETURNING RENEWAL_ID INTO P_RENEWAL_ID;

        COPY_LIVE_SALARY(P_RENEWAL_ID, P_EMP_ID, L_BASIC, P_USER_ID);
        UPDATE_TOTALS(P_RENEWAL_ID, P_USER_ID);

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

    EXCEPTION
        WHEN DUP_VAL_ON_INDEX THEN
            RAISE_APPLICATION_ERROR(-20714, 'This employee already has a renewal draft.');
        WHEN OTHERS THEN
            IF SQLCODE = -54 THEN
                RAISE_APPLICATION_ERROR(-20718, 'The employee contract is being edited by another user.');
            ELSE
                RAISE;
            END IF;
    END CREATE_DRAFT;

    PROCEDURE CREATE_DUE_RENEWAL (
        P_EMP_ID       IN  NUMBER,
        P_SALARY_MODE  IN  VARCHAR2,
        P_TERM_MONTHS  IN  NUMBER,
        P_USER_ID      IN  NUMBER,
        P_RENEWAL_ID   OUT NUMBER
    ) IS
        L_MODE          VARCHAR2(10) := UPPER(TRIM(P_SALARY_MODE));
        L_CURRENT_FROM  DATE;
        L_CURRENT_TO    DATE;
        L_GRADE_ID      NUMBER;
        L_SCALE_ID      NUMBER;
        L_NEW_SCALE_ID  NUMBER;
        L_OLD_STEP_NO   NUMBER;
        L_NEW_STEP_NO   NUMBER;
        L_NEW_FROM      DATE;
        L_NEW_TO        DATE;
        L_NEW_BASIC     NUMBER;
        L_CURRENT_BASIC NUMBER;
        L_GRADE_TEXT    VARCHAR2(100);
        L_PAY_SCALE     VARCHAR2(300);
    BEGIN
        ASSERT_USER(P_USER_ID);

        IF L_MODE IS NULL OR L_MODE NOT IN ('AUTO', 'MANUAL') THEN
            RAISE_APPLICATION_ERROR(-20740, 'Salary method must be AUTO or MANUAL.');
        END IF;

        IF P_TERM_MONTHS IS NULL OR P_TERM_MONTHS <> TRUNC(P_TERM_MONTHS)
           OR P_TERM_MONTHS < 1 OR P_TERM_MONTHS > 60
        THEN
            RAISE_APPLICATION_ERROR(-20741, 'Renewal term must be 1 to 60 whole months.');
        END IF;

        BEGIN
            SELECT C.CONTRACT_FROM_DATE, C.CONTRACT_TO_DATE,
                   NVL(C.GRADE_ID, NVL(D.GRADE, E.JOB_ID)),
                   C.SCALE_ID, C.STEP_NO
              INTO L_CURRENT_FROM, L_CURRENT_TO,
                   L_GRADE_ID, L_SCALE_ID, L_OLD_STEP_NO
              FROM HRMS.HR_EMPLOYEE_CONTRACT C
              JOIN HRMS.EMPLOYEES E ON E.ID = C.EMP_ID
              LEFT JOIN HRMS.DESIGNATIONS D ON D.ID = E.DESIG_ID
             WHERE C.EMP_ID = P_EMP_ID
               AND C.CONTRACT_STATUS = 'ACTIVE'
             FOR UPDATE OF C.GRADE_ID NOWAIT;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(-20742, 'Employee has no active contract to renew.');
        END;

        IF L_GRADE_ID IS NULL THEN
            RAISE_APPLICATION_ERROR(
                -20743,
                'Current grade cannot be derived. Set DESIGNATIONS.GRADE or EMPLOYEES.JOB_ID.'
            );
        END IF;

        L_NEW_FROM := TRUNC(L_CURRENT_TO) + 1;
        L_NEW_TO   := ADD_MONTHS(L_NEW_FROM, P_TERM_MONTHS) - 1;

        /* Older contract rows may not contain scale/step. Derive them from the
           employee grade and live Basic so Page 520 remains one-click. */
        IF L_SCALE_ID IS NULL THEN
            SELECT MIN(M.SCALE_ID)
                       KEEP (
                           DENSE_RANK FIRST ORDER BY
                           M.REVISION_NO DESC,
                           NVL(M.EFFECTIVE_FROM, DATE '1900-01-01') DESC,
                           M.SCALE_ID DESC
                       )
              INTO L_SCALE_ID
              FROM HRMS.PAY_SCALE_MASTER M
             WHERE M.GRADE_ID = L_GRADE_ID
               AND M.IS_ACTIVE = 'Y'
               AND (M.EFFECTIVE_FROM IS NULL OR M.EFFECTIVE_FROM <= L_NEW_FROM)
               AND (M.EFFECTIVE_TO IS NULL OR M.EFFECTIVE_TO >= L_NEW_FROM);

            IF L_SCALE_ID IS NULL THEN
                RAISE_APPLICATION_ERROR(
                    -20746,
                    'No active pay scale can be derived for the employee grade.'
                );
            END IF;
        END IF;

        IF L_OLD_STEP_NO IS NULL THEN
            SELECT MAX(CASE
                           WHEN LPAD(TRIM(S.HEADCODE), 3, '0') = '001'
                                OR S.SLNO = 1
                           THEN S.AMOUNT
                       END)
              INTO L_CURRENT_BASIC
              FROM HRMS.EMP_SALARY_STRUCTURE S
             WHERE S.EMPLOYEE_ID = P_EMP_ID
               AND NVL(S.IS_ACTIVE, 'Y') = 'Y';

            IF L_CURRENT_BASIC IS NULL THEN
                RAISE_APPLICATION_ERROR(
                    -20747,
                    'Current Basic salary is required to derive the pay-scale step.'
                );
            END IF;

            SELECT COALESCE(
                       MAX(CASE
                               WHEN D.BASIC_AMOUNT <= L_CURRENT_BASIC THEN D.STEP_NO
                           END),
                       MIN(D.STEP_NO)
                   )
              INTO L_OLD_STEP_NO
              FROM HRMS.PAY_SCALE_DETAIL D
             WHERE D.SCALE_ID = L_SCALE_ID;

            IF L_OLD_STEP_NO IS NULL THEN
                RAISE_APPLICATION_ERROR(
                    -20748,
                    'Pay-scale step cannot be derived from the current Basic salary.'
                );
            END IF;
        END IF;

        UPDATE HRMS.HR_EMPLOYEE_CONTRACT
           SET GRADE_ID     = L_GRADE_ID,
               SCALE_ID     = L_SCALE_ID,
               STEP_NO      = L_OLD_STEP_NO,
               UPDATED_BY   = P_USER_ID,
               UPDATED_DATE = SYSDATE
         WHERE EMP_ID = P_EMP_ID;

        L_NEW_STEP_NO := L_OLD_STEP_NO;

        /* Prefer the current scale while it is still effective. If its
           revision expired, use the latest active revision for the grade. */
        SELECT MIN(M.SCALE_ID)
                   KEEP (
                       DENSE_RANK FIRST ORDER BY
                       CASE WHEN M.SCALE_ID = L_SCALE_ID THEN 0 ELSE 1 END,
                       M.REVISION_NO DESC,
                       NVL(M.EFFECTIVE_FROM, DATE '1900-01-01') DESC,
                       M.SCALE_ID DESC
                   )
          INTO L_NEW_SCALE_ID
          FROM HRMS.PAY_SCALE_MASTER M
         WHERE M.GRADE_ID = L_GRADE_ID
           AND M.IS_ACTIVE = 'Y'
           AND (M.EFFECTIVE_FROM IS NULL OR M.EFFECTIVE_FROM <= L_NEW_FROM)
           AND (M.EFFECTIVE_TO IS NULL OR M.EFFECTIVE_TO >= L_NEW_FROM);

        IF L_NEW_SCALE_ID IS NULL THEN
            RAISE_APPLICATION_ERROR(-20744, 'No active pay scale exists for the renewal date.');
        END IF;

        IF L_MODE = 'AUTO' THEN
            SELECT MIN(STEP_NO)
              INTO L_NEW_STEP_NO
              FROM HRMS.PAY_SCALE_DETAIL
             WHERE SCALE_ID = L_NEW_SCALE_ID
               AND STEP_NO > L_OLD_STEP_NO;

            IF L_NEW_STEP_NO IS NULL THEN
                RAISE_APPLICATION_ERROR(
                    -20745,
                    'No higher pay-scale step is available. Select Manual adjustment.'
                );
            END IF;
        END IF;

        CREATE_DRAFT(
            P_EMP_ID            => P_EMP_ID,
            P_CURRENT_FROM_DATE => L_CURRENT_FROM,
            P_CURRENT_TO_DATE   => L_CURRENT_TO,
            P_OLD_GRADE_ID      => L_GRADE_ID,
            P_OLD_SCALE_ID      => L_SCALE_ID,
            P_OLD_STEP_NO       => L_OLD_STEP_NO,
            P_NEW_FROM_DATE     => L_NEW_FROM,
            P_NEW_TO_DATE       => L_NEW_TO,
            P_NEW_GRADE_ID      => L_GRADE_ID,
            P_NEW_SCALE_ID      => L_NEW_SCALE_ID,
            P_NEW_STEP_NO       => L_NEW_STEP_NO,
            P_USER_ID           => P_USER_ID,
            P_RENEWAL_ID        => P_RENEWAL_ID
        );

        UPDATE HRMS.HR_CONTRACT_RENEWAL
           SET SALARY_MODE = L_MODE,
               UPDATED_BY = P_USER_ID,
               UPDATED_DATE = SYSDATE
         WHERE RENEWAL_ID = P_RENEWAL_ID;

        IF L_MODE = 'AUTO' THEN
            GET_SCALE_VALUES(L_GRADE_ID, L_NEW_SCALE_ID, L_NEW_STEP_NO,
                             L_NEW_FROM, L_NEW_BASIC, L_GRADE_TEXT, L_PAY_SCALE);
            APPLY_AUTO_SALARY(P_RENEWAL_ID, L_NEW_SCALE_ID, L_NEW_BASIC, P_USER_ID);
            UPDATE_TOTALS(P_RENEWAL_ID, P_USER_ID);
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE = -54 THEN
                RAISE_APPLICATION_ERROR(-20718, 'The employee contract is being edited by another user.');
            ELSE
                RAISE;
            END IF;
    END CREATE_DUE_RENEWAL;

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
        L_STATUS       VARCHAR2(20);
        L_SALARY_MODE  VARCHAR2(10);
        L_CURRENT_TO   DATE;
        L_BASIC        NUMBER;
        L_GRADE_TEXT   VARCHAR2(100);
        L_PAY_SCALE    VARCHAR2(300);
    BEGIN
        ASSERT_USER(P_USER_ID);

        SELECT STATUS, CURRENT_TO_DATE, SALARY_MODE
          INTO L_STATUS, L_CURRENT_TO, L_SALARY_MODE
          FROM HRMS.HR_CONTRACT_RENEWAL
         WHERE RENEWAL_ID = P_RENEWAL_ID
         FOR UPDATE NOWAIT;

        IF L_STATUS <> C_DRAFT THEN
            RAISE_APPLICATION_ERROR(-20719, 'Only a DRAFT renewal can be edited.');
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

        APPLY_SCALE_BASIC(P_RENEWAL_ID, L_BASIC, P_USER_ID);
        IF L_SALARY_MODE = 'AUTO' THEN
            APPLY_AUTO_SALARY(P_RENEWAL_ID, P_NEW_SCALE_ID, L_BASIC, P_USER_ID);
        END IF;
        UPDATE_TOTALS(P_RENEWAL_ID, P_USER_ID);
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20720, 'Renewal was not found.');
        WHEN OTHERS THEN
            IF SQLCODE = -54 THEN
                RAISE_APPLICATION_ERROR(-20721, 'The renewal is being edited by another user.');
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
        L_SALARY_MODE  VARCHAR2(10);
        L_BASIC        NUMBER;
        L_GRADE_TEXT   VARCHAR2(100);
        L_PAY_SCALE    VARCHAR2(300);
    BEGIN
        ASSERT_USER(P_USER_ID);

        SELECT STATUS, EMP_ID, NEW_GRADE_ID, NEW_SCALE_ID,
               NEW_STEP_NO, NEW_FROM_DATE, SALARY_MODE
          INTO L_STATUS, L_EMP_ID, L_NEW_GRADE_ID, L_NEW_SCALE_ID,
               L_NEW_STEP_NO, L_NEW_FROM, L_SALARY_MODE
          FROM HRMS.HR_CONTRACT_RENEWAL
         WHERE RENEWAL_ID = P_RENEWAL_ID
         FOR UPDATE NOWAIT;

        IF L_STATUS <> C_DRAFT THEN
            RAISE_APPLICATION_ERROR(-20719, 'Only a DRAFT renewal can refresh salary.');
        END IF;

        GET_SCALE_VALUES(L_NEW_GRADE_ID, L_NEW_SCALE_ID, L_NEW_STEP_NO,
                         L_NEW_FROM, L_BASIC, L_GRADE_TEXT, L_PAY_SCALE);

        DELETE FROM HRMS.HR_CONTRACT_RENEWAL_SALARY
         WHERE RENEWAL_ID = P_RENEWAL_ID;

        COPY_LIVE_SALARY(P_RENEWAL_ID, L_EMP_ID, L_BASIC, P_USER_ID);
        IF L_SALARY_MODE = 'AUTO' THEN
            APPLY_AUTO_SALARY(P_RENEWAL_ID, L_NEW_SCALE_ID, L_BASIC, P_USER_ID);
        END IF;
        UPDATE_TOTALS(P_RENEWAL_ID, P_USER_ID);
    END REFRESH_SALARY_SNAPSHOT;

    PROCEDURE GENERATE_LETTER (
        P_RENEWAL_ID IN  NUMBER,
        P_ACTION_ID  IN  NUMBER,
        P_USER_ID    IN  NUMBER,
        P_LETTER_ID  OUT NUMBER
    ) IS
        L_EMP_ID            NUMBER;
        L_RENEWAL_NO        VARCHAR2(30);
        L_TEMPLATE_ID       NUMBER;
        L_SIGNATORY_ID      NUMBER;
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
        L_BAD_COUNT         PLS_INTEGER;
    BEGIN
        SELECT EMP_ID, RENEWAL_NO, TEMPLATE_ID, SIGNATORY_ID,
               EMP_NAME_SNAPSHOT, EMP_CODE_SNAPSHOT,
               DESIGNATION_SNAPSHOT, DEPARTMENT_SNAPSHOT,
               COMPANY_SNAPSHOT, GRADE_SNAPSHOT, PAY_SCALE_SNAPSHOT,
               NEW_FROM_DATE, NEW_TO_DATE, SPECIAL_TERMS
          INTO L_EMP_ID, L_RENEWAL_NO, L_TEMPLATE_ID, L_SIGNATORY_ID,
               L_EMP_NAME, L_EMP_CODE,
               L_DESIGNATION, L_DEPARTMENT,
               L_COMPANY, L_GRADE, L_PAY_SCALE,
               L_NEW_FROM, L_NEW_TO, L_SPECIAL_TERMS
          FROM HRMS.HR_CONTRACT_RENEWAL
         WHERE RENEWAL_ID = P_RENEWAL_ID;

        IF L_SIGNATORY_ID IS NULL OR L_TEMPLATE_ID IS NULL THEN
            RAISE_APPLICATION_ERROR(-20722, 'Letter signatory and template are required.');
        END IF;

        SELECT COUNT(*) INTO L_BAD_COUNT
          FROM HRMS.HR_LETTER_SIGNATORY
         WHERE SIGNATORY_ID = L_SIGNATORY_ID
           AND IS_ACTIVE = 'Y';
        IF L_BAD_COUNT <> 1 THEN
            RAISE_APPLICATION_ERROR(-20723, 'The selected letter signatory is not active.');
        END IF;

        SELECT COUNT(*) INTO L_BAD_COUNT
          FROM HRMS.HR_CONTRACT_RENEW_RECIPIENT X
          JOIN HRMS.HR_LETTER_RECIPIENT M
            ON M.LETTER_RECIPIENT_ID = X.LETTER_RECIPIENT_ID
         WHERE X.RENEWAL_ID = P_RENEWAL_ID
           AND X.IS_ACTIVE = 'Y'
           AND M.IS_ACTIVE <> 'Y';
        IF L_BAD_COUNT > 0 THEN
            RAISE_APPLICATION_ERROR(-20724, 'One or more selected letter recipients are inactive.');
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

        INSERT INTO HRMS.HR_EMPLOYEE_LETTER (
            EMP_ID, ACTION_ID, CONTRACT_RENEWAL_ID, TEMPLATE_ID,
            LETTER_NO, LETTER_DATE, SUBJECT_TEXT, BODY_HTML,
            STATUS, GENERATED_BY, GENERATED_DATE,
            APPROVED_BY, APPROVED_DATE, ISSUED_BY, ISSUED_DATE
        ) VALUES (
            L_EMP_ID, P_ACTION_ID, P_RENEWAL_ID, L_TEMPLATE_ID,
            L_RENEWAL_NO, SYSDATE, L_SUBJECT, L_BODY,
            'ISSUED', P_USER_ID, SYSDATE,
            P_USER_ID, SYSDATE, P_USER_ID, SYSDATE
        ) RETURNING LETTER_ID INTO P_LETTER_ID;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20725, 'Letter template or renewal configuration was not found.');
    END GENERATE_LETTER;

    PROCEDURE FINAL_SUBMIT (
        P_RENEWAL_ID IN  NUMBER,
        P_USER_ID    IN  NUMBER,
        P_ACTION_ID  OUT NUMBER,
        P_LETTER_ID  OUT NUMBER
    ) IS
        L_STATUS         VARCHAR2(20);
        L_EMP_ID         NUMBER;
        L_CURRENT_FROM   DATE;
        L_CURRENT_TO     DATE;
        L_NEW_FROM       DATE;
        L_NEW_TO         DATE;
        L_OLD_GRADE_ID   NUMBER;
        L_NEW_GRADE_ID   NUMBER;
        L_OLD_SCALE_ID   NUMBER;
        L_NEW_SCALE_ID   NUMBER;
        L_OLD_STEP_NO    NUMBER;
        L_NEW_STEP_NO    NUMBER;
        L_OLD_BASIC      NUMBER;
        L_NEW_BASIC      NUMBER;
        L_OLD_GROSS      NUMBER;
        L_NEW_GROSS      NUMBER;
        L_REASON         VARCHAR2(1000);
        L_REMARKS        VARCHAR2(1000);
        L_MASTER_FROM    DATE;
        L_MASTER_TO      DATE;
        L_MASTER_GRADE   NUMBER;
        L_MASTER_SCALE   NUMBER;
        L_MASTER_STEP    NUMBER;
        L_BAD_COUNT      PLS_INTEGER;
        L_SALS_ID        NUMBER;
        L_GRADE_VALUE    VARCHAR2(100);
        L_AFTER_GROSS    NUMBER;
        L_CALC_OLD_BASIC NUMBER;
        L_CALC_NEW_BASIC NUMBER;
        L_CALC_OLD_GROSS NUMBER;
        L_CALC_NEW_GROSS NUMBER;
    BEGIN
        ASSERT_USER(P_USER_ID);
        P_ACTION_ID := NULL;
        P_LETTER_ID := NULL;
        SAVEPOINT BEFORE_CONTRACT_POST;

        SELECT STATUS, EMP_ID,
               CURRENT_FROM_DATE, CURRENT_TO_DATE, NEW_FROM_DATE, NEW_TO_DATE,
               OLD_GRADE_ID, NEW_GRADE_ID, OLD_SCALE_ID, NEW_SCALE_ID,
               OLD_STEP_NO, NEW_STEP_NO,
               OLD_BASIC, NEW_BASIC, OLD_GROSS, NEW_GROSS,
               REASON, REMARKS
          INTO L_STATUS, L_EMP_ID,
               L_CURRENT_FROM, L_CURRENT_TO, L_NEW_FROM, L_NEW_TO,
               L_OLD_GRADE_ID, L_NEW_GRADE_ID, L_OLD_SCALE_ID, L_NEW_SCALE_ID,
               L_OLD_STEP_NO, L_NEW_STEP_NO,
               L_OLD_BASIC, L_NEW_BASIC, L_OLD_GROSS, L_NEW_GROSS,
               L_REASON, L_REMARKS
          FROM HRMS.HR_CONTRACT_RENEWAL
         WHERE RENEWAL_ID = P_RENEWAL_ID
         FOR UPDATE NOWAIT;

        IF L_STATUS <> C_DRAFT THEN
            RAISE_APPLICATION_ERROR(-20726, 'Only a DRAFT renewal can be finally submitted.');
        END IF;

        IF TRUNC(L_NEW_FROM) > TRUNC(SYSDATE) THEN
            RAISE_APPLICATION_ERROR(
                -20727,
                'Final submit is allowed on or after '
                || TO_CHAR(L_NEW_FROM, 'DD-Mon-YYYY') || '.'
            );
        END IF;

        CALCULATE_TOTALS(P_RENEWAL_ID,
                         L_CALC_OLD_BASIC, L_CALC_NEW_BASIC,
                         L_CALC_OLD_GROSS, L_CALC_NEW_GROSS);

        IF ABS(NVL(L_CALC_OLD_BASIC, 0) - NVL(L_OLD_BASIC, 0)) > 0.005
           OR ABS(NVL(L_CALC_NEW_BASIC, 0) - NVL(L_NEW_BASIC, 0)) > 0.005
           OR ABS(NVL(L_CALC_OLD_GROSS, 0) - NVL(L_OLD_GROSS, 0)) > 0.005
           OR ABS(NVL(L_CALC_NEW_GROSS, 0) - NVL(L_NEW_GROSS, 0)) > 0.005
        THEN
            RAISE_APPLICATION_ERROR(-20728, 'Salary details do not match the renewal totals.');
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
                -20729,
                'Current contract changed after this draft. Delete it and create a new draft.'
            );
        END IF;

        FOR X IN (
            SELECT SALS_ID
              FROM HRMS.EMP_SALARY_STRUCTURE
             WHERE EMPLOYEE_ID = L_EMP_ID
               AND NVL(IS_ACTIVE, 'Y') = 'Y'
             FOR UPDATE NOWAIT
        ) LOOP
            NULL;
        END LOOP;

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
                -20730,
                'Live salary changed after this draft. Use Refresh Salary and review again.'
            );
        END IF;

        SELECT COUNT(*) INTO L_BAD_COUNT
          FROM HRMS.HR_CONTRACT_RENEWAL_SALARY D
         WHERE D.RENEWAL_ID = P_RENEWAL_ID
           AND D.EMP_ID = L_EMP_ID
           AND D.SALS_ID IS NOT NULL
           AND NOT EXISTS (
               SELECT 1
                 FROM HRMS.EMP_SALARY_STRUCTURE S
                WHERE S.SALS_ID = D.SALS_ID
                  AND S.EMPLOYEE_ID = L_EMP_ID
                  AND NVL(S.IS_ACTIVE, 'Y') = 'Y'
                  AND NVL(S.AMOUNT, 0) = NVL(D.OLD_AMOUNT, 0)
           );

        IF L_BAD_COUNT > 0 THEN
            RAISE_APPLICATION_ERROR(
                -20730,
                'A captured salary row changed or became inactive. Use Refresh Salary.'
            );
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
                        -20731,
                        'A new salary detail conflicts with an existing salary head.'
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
          JOIN HRMS.ALLOWANCE_HEAD AH ON AH.HEAD_ID = S.SLNO
         WHERE S.EMPLOYEE_ID = L_EMP_ID
           AND NVL(S.IS_ACTIVE, 'Y') = 'Y';

        IF ABS(NVL(L_AFTER_GROSS, 0) - NVL(L_NEW_GROSS, 0)) > 0.005 THEN
            RAISE_APPLICATION_ERROR(-20732, 'Posted gross does not match the renewal gross.');
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
           SET GRADE     = L_GRADE_VALUE,
               UPD_BY   = P_USER_ID,
               UPD_DATE = SYSDATE
         WHERE ID = L_EMP_ID;

        GENERATE_LETTER(P_RENEWAL_ID, P_ACTION_ID, P_USER_ID, P_LETTER_ID);

        UPDATE HRMS.HR_CONTRACT_RENEWAL_SALARY
           SET IS_POSTED  = 'Y',
               POSTED_BY  = P_USER_ID,
               POSTED_DATE = SYSDATE
         WHERE RENEWAL_ID = P_RENEWAL_ID;

        UPDATE HRMS.HR_CONTRACT_RENEWAL
           SET ACTION_ID    = P_ACTION_ID,
               LETTER_ID    = P_LETTER_ID,
               STATUS       = C_POSTED,
               POSTED_BY    = P_USER_ID,
               POSTED_DATE  = SYSDATE,
               UPDATED_BY   = P_USER_ID,
               UPDATED_DATE = SYSDATE,
               VERSION_NO   = VERSION_NO + 1
         WHERE RENEWAL_ID = P_RENEWAL_ID;

    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK TO BEFORE_CONTRACT_POST;
            IF SQLCODE = -54 THEN
                RAISE_APPLICATION_ERROR(-20733, 'Employee or renewal is being processed by another user.');
            ELSE
                RAISE;
            END IF;
    END FINAL_SUBMIT;

    PROCEDURE DELETE_DRAFT (
        P_RENEWAL_ID IN NUMBER,
        P_USER_ID    IN NUMBER
    ) IS
        L_STATUS      VARCHAR2(20);
        L_EMP_ID      NUMBER;
        L_BASELINE_YN VARCHAR2(1);
    BEGIN
        ASSERT_USER(P_USER_ID);

        SELECT STATUS, EMP_ID, BASELINE_CREATED_YN
          INTO L_STATUS, L_EMP_ID, L_BASELINE_YN
          FROM HRMS.HR_CONTRACT_RENEWAL
         WHERE RENEWAL_ID = P_RENEWAL_ID
         FOR UPDATE NOWAIT;

        IF L_STATUS <> C_DRAFT THEN
            RAISE_APPLICATION_ERROR(-20734, 'Only a DRAFT renewal can be deleted.');
        END IF;

        DELETE FROM HRMS.HR_CONTRACT_RENEWAL
         WHERE RENEWAL_ID = P_RENEWAL_ID;

        IF L_BASELINE_YN = 'Y' THEN
            DELETE FROM HRMS.HR_EMPLOYEE_CONTRACT
             WHERE EMP_ID = L_EMP_ID
               AND LATEST_RENEWAL_ID IS NULL;
        END IF;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20720, 'Renewal was not found.');
    END DELETE_DRAFT;

END PKG_HR_CONTRACT_RENEWAL;
/

SHOW ERRORS;
