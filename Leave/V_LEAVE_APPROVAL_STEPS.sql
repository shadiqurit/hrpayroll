-- Workflow groups: RP recommendation, any ONE final approver, HRD record.
-- HOD/Plant Head/MD are alternatives within group 20, not sequential steps.
CREATE OR REPLACE VIEW HRMS.v_leave_approval_steps AS
SELECT h.*,
       CASE h.approver_level
           WHEN 'RP' THEN 10
           WHEN 'HOD' THEN 20
           WHEN 'PLANT_HEAD' THEN 20
           WHEN 'MANAGING_DIRECTOR' THEN 20
           WHEN 'LEAVE_RECORD' THEN 50
       END AS step_no
  FROM HRMS.leave_app_history h;
