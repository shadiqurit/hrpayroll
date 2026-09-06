CREATE OR REPLACE TRIGGER HRMS.TRG_EMP_SAL_STRUCT_HIST
    AFTER INSERT OR UPDATE
    ON HRMS.EMP_SALARY_STRUCTURE
    FOR EACH ROW
DECLARE
    V_REMARKS         VARCHAR2 (1000);
    V_APP_ACTION      VARCHAR2 (64);
    V_PROMOTION_REF   VARCHAR2 (100);
BEGIN
    /* PKG_HR_PROMOTION temporarily sets USERENV.ACTION to
       PROMOTION:<promotion_no>. This lets the generic trigger reference the
       promotion without coupling EMP_SALARY_STRUCTURE to a promotion table. */
    V_APP_ACTION := SYS_CONTEXT ('USERENV', 'ACTION');

    IF V_APP_ACTION LIKE 'PROMOTION:%'
    THEN
        V_PROMOTION_REF :=
               '[PROMOTION:'
            || SUBSTR (V_APP_ACTION, LENGTH ('PROMOTION:') + 1)
            || '] ';
    END IF;

    ------------------------------------------------------------------
    -- INSERT HISTORY
    ------------------------------------------------------------------
    IF INSERTING
    THEN
        INSERT INTO HRMS.EMP_SALARY_STRUCTURE_HIST (ACTION_ID,
                                                    EMP_ID,
                                                    SALS_ID,
                                                    SLNO,
                                                    HEADCODE,
                                                    OLD_AMOUNT,
                                                    NEW_AMOUNT,
                                                    REVISION_TYPE,
                                                    EFFECTIVE_DATE,
                                                    REMARKS,
                                                    ENT_BY,
                                                    ENT_DATE)
             VALUES (1,                                          -- 1 = Insert
                     :NEW.EMPLOYEE_ID,
                     :NEW.SALS_ID,
                     :NEW.SLNO,
                     :NEW.HEADCODE,
                     NULL,
                     NVL (:NEW.AMOUNT, 0),
                     :NEW.REVISION_TYPE,
                     NVL (:NEW.CREATED_DATE, SYSDATE),
                     SUBSTR (V_PROMOTION_REF || 'Salary structure inserted', 1, 1000),
                     :NEW.CREATED_BY,
                     SYSDATE);
    ------------------------------------------------------------------
    -- UPDATE HISTORY
    ------------------------------------------------------------------
    ELSIF UPDATING
    THEN
        /*
           Create history only when salary-related information changes.
           NVL is used so that NULL values can also be compared properly.
        */
        IF    V_PROMOTION_REF IS NOT NULL
           OR NVL (:OLD.AMOUNT, 0) <> NVL (:NEW.AMOUNT, 0)
           OR NVL (:OLD.HEADCODE, '#NULL#') <> NVL (:NEW.HEADCODE, '#NULL#')
           OR NVL (:OLD.SLNO, -999999) <> NVL (:NEW.SLNO, -999999)
           OR NVL (:OLD.REVISION_TYPE, '#') <> NVL (:NEW.REVISION_TYPE, '#')
           OR NVL (:OLD.IS_ACTIVE, '#') <> NVL (:NEW.IS_ACTIVE, '#')
        THEN
            V_REMARKS :=
                   V_PROMOTION_REF
                || 'Salary structure updated'
                || CASE
                       WHEN NVL (:OLD.AMOUNT, 0) <> NVL (:NEW.AMOUNT, 0)
                       THEN
                              '; Amount changed from '
                           || TO_CHAR (NVL (:OLD.AMOUNT, 0),
                                       'FM9999999999990.00')
                           || ' to '
                           || TO_CHAR (NVL (:NEW.AMOUNT, 0),
                                       'FM9999999999990.00')
                   END
                || CASE
                       WHEN NVL (:OLD.HEADCODE, '#NULL#') <>
                            NVL (:NEW.HEADCODE, '#NULL#')
                       THEN
                              '; Headcode changed from '
                           || NVL (:OLD.HEADCODE, 'NULL')
                           || ' to '
                           || NVL (:NEW.HEADCODE, 'NULL')
                   END
                || CASE
                       WHEN NVL (:OLD.IS_ACTIVE, '#') <>
                            NVL (:NEW.IS_ACTIVE, '#')
                       THEN
                              '; Active status changed from '
                           || NVL (:OLD.IS_ACTIVE, 'NULL')
                           || ' to '
                           || NVL (:NEW.IS_ACTIVE, 'NULL')
                   END;

            INSERT INTO HRMS.EMP_SALARY_STRUCTURE_HIST (ACTION_ID,
                                                        EMP_ID,
                                                        SALS_ID,
                                                        SLNO,
                                                        HEADCODE,
                                                        OLD_AMOUNT,
                                                        NEW_AMOUNT,
                                                        REVISION_TYPE,
                                                        EFFECTIVE_DATE,
                                                        REMARKS,
                                                        ENT_BY,
                                                        ENT_DATE)
                 VALUES (2,                                      -- 2 = Update
                         :NEW.EMPLOYEE_ID,
                         :NEW.SALS_ID,
                         :NEW.SLNO,
                         :NEW.HEADCODE,
                         NVL (:OLD.AMOUNT, 0),
                         NVL (:NEW.AMOUNT, 0),
                         :NEW.REVISION_TYPE,
                         NVL (:NEW.UPDATED_DATE, SYSDATE),
                         SUBSTR (V_REMARKS, 1, 1000),
                         NVL (:NEW.UPDATED_BY, :NEW.CREATED_BY),
                         SYSDATE);
        END IF;
    END IF;
END;
/
SHOW ERRORS;
