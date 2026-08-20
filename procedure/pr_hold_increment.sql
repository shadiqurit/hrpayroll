CREATE OR REPLACE PROCEDURE HRMS.PR_HOLD_INCREMENT (
    P_EMP_ID          IN NUMBER,
    P_REASON          IN VARCHAR2,
    P_USER_ID         IN NUMBER,
    P_INCREMENT_ID    IN NUMBER DEFAULT NULL,
    P_HOLD_TO_DATE    IN DATE DEFAULT NULL
)
IS
    V_INCREMENT_ID NUMBER := P_INCREMENT_ID;
    V_ACTION_ID    NUMBER;
    V_DUE_DATE     DATE;
    V_EFFECTIVE    DATE;
    V_STATUS       VARCHAR2(20);
    V_DUMMY_OUT    NUMBER;
    V_ACTIVE_HOLD  NUMBER;
BEGIN
    IF V_INCREMENT_ID IS NULL THEN
        BEGIN
            SELECT INCREMENT_ID
              INTO V_INCREMENT_ID
              FROM HR_EMPLOYEE_INCREMENT
             WHERE EMP_ID = P_EMP_ID
               AND STATUS IN ('READY','EXTENDED','HOLD')
             ORDER BY DUE_DATE DESC
             FETCH FIRST 1 ROW ONLY;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                HRMS.PR_PREPARE_INCREMENT(
                    P_EMP_ID         => P_EMP_ID,
                    P_EFFECTIVE_DATE => NULL,
                    P_REMARKS        => P_REASON,
                    P_USER_ID        => P_USER_ID,
                    P_INCREMENT_ID   => V_DUMMY_OUT
                );
                V_INCREMENT_ID := V_DUMMY_OUT;
        END;
    END IF;

    SELECT DUE_DATE, EFFECTIVE_DATE, STATUS
      INTO V_DUE_DATE, V_EFFECTIVE, V_STATUS
      FROM HR_EMPLOYEE_INCREMENT
     WHERE INCREMENT_ID = V_INCREMENT_ID
       AND EMP_ID = P_EMP_ID
     FOR UPDATE;

    IF V_STATUS IN ('POSTED','CANCELLED') THEN
        RAISE_APPLICATION_ERROR(-20120,
            'Posted/cancelled increment cannot be held.');
    END IF;

    /* P_HOLD_TO_DATE is a review/carry-forward date, not a new effective date. */
    IF P_HOLD_TO_DATE IS NOT NULL AND TRUNC(P_HOLD_TO_DATE) < TRUNC(SYSDATE) THEN
        RAISE_APPLICATION_ERROR(-20122,
            'Hold review date cannot be earlier than today.');
    END IF;

    SELECT COUNT(*)
      INTO V_ACTIVE_HOLD
      FROM HR_INCREMENT_HOLD
     WHERE INCREMENT_ID = V_INCREMENT_ID
       AND HOLD_STATUS = 'ACTIVE';

    IF V_ACTIVE_HOLD > 0 THEN
        RAISE_APPLICATION_ERROR(-20121,
            'This increment cycle already has an active hold.');
    END IF;

    INSERT INTO HR_EMPLOYEE_ACTION
    (
        EMP_ID,
        INCREMENT_ID,
        ACTION_TYPE,
        ACTION_DATE,
        EFFECTIVE_DATE,
        OLD_EFFECTIVE_DATE,
        NEW_EFFECTIVE_DATE,
        REASON,
        REMARKS,
        APPROVAL_STATUS,
        ENT_BY,
        APPROVED_BY,
        APPROVED_DATE
    )
    VALUES
    (
        P_EMP_ID,
        V_INCREMENT_ID,
        'INCREMENT_HOLD',
        SYSDATE,
        V_EFFECTIVE,
        V_EFFECTIVE,
        V_EFFECTIVE,
        P_REASON,
        P_REASON,
        'APPROVED',
        P_USER_ID,
        P_USER_ID,
        SYSDATE
    )
    RETURNING ACTION_ID INTO V_ACTION_ID;

    INSERT INTO HR_INCREMENT_HOLD
    (
        EMP_ID,
        INCREMENT_ID,
        HOLD_FROM_DATE,
        HOLD_TO_DATE,
        HOLD_REASON,
        HOLD_STATUS,
        ACTION_ID,
        ENT_BY
    )
    VALUES
    (
        P_EMP_ID,
        V_INCREMENT_ID,
        SYSDATE,
        P_HOLD_TO_DATE,
        P_REASON,
        'ACTIVE',
        V_ACTION_ID,
        P_USER_ID
    );

    UPDATE HR_EMPLOYEE_INCREMENT
       SET STATUS = 'HOLD',
           CHANGE_REASON = P_REASON,
           UPDATED_BY = P_USER_ID,
           UPDATED_DATE = SYSDATE
     WHERE INCREMENT_ID = V_INCREMENT_ID;

    UPDATE EMPLOYEES
       SET INCREMENT_HOLD_STATUS = 'Y',
           INCREMENT_HOLD_REASON = P_REASON,
           INCREMENT_HOLD_DATE = SYSDATE
     WHERE ID = P_EMP_ID;
END;
/
