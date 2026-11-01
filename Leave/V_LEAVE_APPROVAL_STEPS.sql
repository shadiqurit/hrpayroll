-- Fixed role order supplies sequencing without adding columns to the tables.
CREATE OR REPLACE VIEW HRMS.v_leave_approval_steps AS
SELECT h.*,
       CASE h.approver_level
           WHEN 'RP' THEN 10
           WHEN 'HOD' THEN 20
           WHEN 'PLANT_HEAD' THEN 30
           WHEN 'MANAGING_DIRECTOR' THEN 40
           WHEN 'LEAVE_RECORD' THEN 50
       END AS step_no
  FROM HRMS.leave_app_history h;
