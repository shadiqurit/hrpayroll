/* Only employee confirmation due dates drive eligibility and preparation. */
CREATE OR REPLACE VIEW HRMS.V_HR_CONTRACT_EXT_ELIGIBLE AS
SELECT e.id AS emp_id, e.com_id, e.emp_id AS employee_code,
       TRIM(e.f_name || ' ' || e.l_name) AS employee_name,
       TRIM(e.emp_type) AS emp_type,
       CASE TRIM(e.emp_type) WHEN '1' THEN 'Probationary' WHEN '3' THEN 'Contractual' END AS employee_type,
       d.designation, dp.dept_name AS department, e.grade,
       NVL(TRUNC(e.join_date), TRUNC(e.confirmation_due_date)) AS current_from_date,
       TRUNC(e.confirmation_due_date) AS current_to_date
  FROM hrms.employees e
  LEFT JOIN hrms.designations d ON d.id = e.desig_id
  LEFT JOIN hrms.departments dp ON dp.id = e.dept_id
 WHERE TRIM(e.emp_type) IN ('1', '3')
   AND e.conf_date IS NULL AND e.confirmation_due_date IS NOT NULL
   AND (e.sep_date IS NULL OR TRUNC(e.sep_date) > TRUNC(SYSDATE));
