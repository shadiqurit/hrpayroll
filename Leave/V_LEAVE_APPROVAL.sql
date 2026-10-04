/* Formatted on 10/4/2026 8:55:15 AM (QP5 v5.362) */
CREATE OR REPLACE FORCE VIEW V_LEAVE_APPROVAL
AS
    SELECT ma.leave_id,
           ma.EMPID,
           v.ipi     empcode,
           v.FULLNAME,
           v.DEPARTMENT,
           v.DESIGNATION,
           ma.LEAVE_PURPOSE,
           ma.L_START_DATE,
           ma.L_END_DATE,
           ma.LEAVE_STATUS,
           -- ma.COMMENTS     action_comment,
           mh.id     did,
           mh.APPROVER_LEVEL,
           mh.APPROVER_ID,
           ap.IPI,
           mh.APPROVAL_DATE,
           mh.APPROVAL_STATUS,
           mh.COMMENTS,
           ma.REQUEST_STATUS,
           CASE ma.REQUEST_STATUS
               WHEN 'D' THEN 'Draft'
               WHEN 'F' THEN 'Forwarded'
               WHEN 'A' THEN 'Final'
           END AS REQUEST_STATUS_TEXT
      FROM LEAVE_REQUEST      ma,
           leave_app_history  mh,
           v_emp              v,
           v_emp              ap
     WHERE     ma.leave_id = mh.leave_id
           AND v.EMP_ID = ma.EMPID
           AND mh.APPROVER_ID = ap.EMP_ID;
