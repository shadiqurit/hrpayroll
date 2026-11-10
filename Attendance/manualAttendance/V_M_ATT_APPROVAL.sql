-- Keep the original leading columns for existing report consumers.
CREATE OR REPLACE VIEW HRMS.v_m_att_approval AS
SELECT ma.id, ma.empid, ma.empcode, ma.fullname, ma.department, ma.designation,
       ma.reason, ma.m_intime, ma.m_outtime, ma.status, ma.comments AS action_comment,
       mh.id AS did, mh.m_att_id, mh.approver_level, mh.approver_id, ap.ipi,
       mh.approval_date, mh.approval_status, mh.comments,
       ma.att_date, ma.com_id, ma.request_status, ma.workflow_version,
       ma.status_text, ma.request_status_text, ma.pending_with, ma.recording_status,
       mh.step_no, mh.approver_level_text
  FROM HRMS.v_m_att_report ma
  JOIN HRMS.v_m_att_approval_steps mh ON mh.m_att_id = ma.id
  LEFT JOIN HRMS.v_emp ap ON ap.emp_id = mh.approver_id;
