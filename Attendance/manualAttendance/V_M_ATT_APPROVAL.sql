CREATE OR REPLACE FORCE VIEW V_M_ATT_APPROVAL
AS
    SELECT ma.id,
           ma.EMPID,
           ma.EMPCODE,
           v.FULLNAME,
           v.DEPARTMENT,
           v.DESIGNATION,
           ma.REASON,
           ma.M_INTIME,
           ma.M_OUTTIME,
           ma.STATUS,
           ma.COMMENTS     action_comment,
           mh.id           did,
           mh.M_ATT_ID,
           mh.APPROVER_LEVEL,
           mh.APPROVER_ID,
           ap.IPI,
           mh.APPROVAL_DATE,
           mh.APPROVAL_STATUS,
           mh.COMMENTS
      FROM manual_att         ma,
           M_ATT_APP_HISTORY  mh,
           v_emp              v,
           v_emp              ap
     WHERE     ma.id = mh.M_ATT_ID
           AND v.EMP_ID = ma.EMPID
           AND mh.APPROVER_ID = ap.EMP_ID;
