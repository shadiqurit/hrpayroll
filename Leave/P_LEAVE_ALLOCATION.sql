CREATE OR REPLACE PROCEDURE HRMS.p_leave_allocation (p_year NUMBER)
AS
    v_year   NUMBER := p_year;
BEGIN
    MERGE INTO LEAVE_ALLOCATION LA
         USING (SELECT E.ID        AS EMPID,
                       e.com_id    AS com_id,
                       LT.LT_ID    AS LEAVE_TYPE_ID,
                       ROUND (
                           CASE
                               WHEN MONTHS_BETWEEN (
                                        LAST_DAY (
                                            ADD_MONTHS (
                                                TRUNC (SYSDATE, 'YYYY'),
                                                11)),
                                        E.JOIN_DATE) <
                                    12
                               THEN
                                     (LT.ANNUAL_QUOTA / 12)
                                   * FLOOR (
                                         MONTHS_BETWEEN (
                                             LAST_DAY (
                                                 ADD_MONTHS (
                                                     TRUNC (join_date,
                                                            'YYYY'),
                                                     11)),
                                             join_date))
                               ELSE
                                   LT.ANNUAL_QUOTA
                           END)    AS ALLOCATED_DAYS,
                       SYSDATE     AS ALLOCATED_DATE
                  FROM LEAVE_TYPES LT JOIN employees E ON E.STATUS = 1
                 WHERE LT.ACTIVE_FLAG = 'Y' AND LT.LT_ID IN (1, 2)) src
            ON (    LA.EMPID = src.EMPID
                AND LA.LEAVE_TYPE_ID = src.LEAVE_TYPE_ID
                AND LA.ALLOCATION_YEAR = v_year)
    WHEN MATCHED
    THEN
        UPDATE SET
            LA.ALLOCATED_DAYS = src.ALLOCATED_DAYS,
            LA.ALLOCATED_DATE = src.ALLOCATED_DATE,
            LA.COM_ID = src.COM_ID
    WHEN NOT MATCHED
    THEN
        INSERT     (EMPID,
                    LEAVE_TYPE_ID,
                    ALLOCATED_DAYS,
                    ALLOCATION_YEAR,
                    ALLOCATED_DATE,
                    com_id)
            VALUES (src.EMPID,
                    src.LEAVE_TYPE_ID,
                    src.ALLOCATED_DAYS,
                    v_year,
                    src.ALLOCATED_DATE,
                    src.com_id);

    COMMIT;
END;
/
