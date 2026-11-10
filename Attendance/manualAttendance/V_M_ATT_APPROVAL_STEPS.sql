CREATE OR REPLACE VIEW HRMS.v_m_att_approval_steps AS
SELECT h.*,
       CASE h.approver_level
           WHEN 'RP' THEN 10
           WHEN 'HOD' THEN 20
           WHEN 'PLANT_HEAD' THEN 20
           WHEN 'MANAGING_DIRECTOR' THEN 20
           WHEN 'LEAVE_RECORD' THEN 50
       END AS step_no,
       CASE h.approver_level
           WHEN 'RP' THEN 'Reporting Person'
           WHEN 'HOD' THEN 'Head of Department'
           WHEN 'PLANT_HEAD' THEN 'Plant Head'
           WHEN 'MANAGING_DIRECTOR' THEN 'Managing Director'
           WHEN 'LEAVE_RECORD' THEN 'HRD Record Keeping'
           ELSE h.approver_level
       END AS approver_level_text
  FROM HRMS.m_att_app_history h;
