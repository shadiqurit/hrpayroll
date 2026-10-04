/* Formatted on 10/4/2026 8:55:42 AM (QP5 v5.362) */
CREATE OR REPLACE FORCE VIEW V_EMP_LEAVE_TOTAL
(
    EMPID,
    YEARMN,
    SL_DAYS,
    CL_DAYS,
    EL_DAYS,
    TOTAL_LEAVE,
    EL_ENCASH
)
BEQUEATH DEFINER
AS
      SELECT empid,
             yearmn,
             MAX (CASE WHEN SHORT_CODE = 'SL' THEN proposed_days ELSE 0 END)
                 AS SL_Days,
             MAX (CASE WHEN SHORT_CODE = 'CL' THEN proposed_days ELSE 0 END)
                 AS CL_Days,
             MAX (CASE WHEN SHORT_CODE = 'EL' THEN proposed_days ELSE 0 END)
                 AS EL_Days,
               NVL (MAX (CASE WHEN SHORT_CODE = 'SL' THEN proposed_days END),
                    0)
             + NVL (MAX (CASE WHEN SHORT_CODE = 'CL' THEN proposed_days END),
                    0)
             + NVL (MAX (CASE WHEN SHORT_CODE = 'EL' THEN proposed_days END),
                    0)
                 AS Total_Leave,
             MAX (CASE WHEN SHORT_CODE = 'EC' THEN proposed_days ELSE 0 END)
                 AS EL_encash
        FROM (SELECT lr.leave_id,
                     lr.empid,
                     SHORT_CODE,
                     TO_CHAR (L_START_DATE, 'yyyymm')       yearmn,
                     NVL (lr.leave_type, app_leave_typ)     l_typ,
                     lr.proposed_days
                FROM leave_request lr, leave_types lt
               WHERE lr.leave_type = lt.lt_id         --and LEAVE_STATUS = 'A'
                                             )
    GROUP BY empid, yearmn;
