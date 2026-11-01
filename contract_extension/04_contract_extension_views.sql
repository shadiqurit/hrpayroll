/* Common eligibility source. Grade and salary are never eligibility conditions. */
CREATE OR REPLACE VIEW HRMS.V_HR_CONTRACT_EXT_ELIGIBLE AS
SELECT e.id AS emp_id, e.com_id, e.emp_id AS employee_code,
       TRIM(e.f_name || ' ' || e.l_name) AS employee_name,
       TRIM(e.emp_type) AS emp_type,
       CASE TRIM(e.emp_type) WHEN '1' THEN 'Probationary' WHEN '3' THEN 'Contractual' END AS employee_type,
       d.designation, dp.dept_name AS department, e.grade,
       NVL(c.contract_from_date, CASE WHEN TRIM(e.emp_type) = '1' THEN e.join_date END) AS current_from_date,
       NVL(c.contract_to_date, CASE WHEN TRIM(e.emp_type) = '1' THEN e.confirmation_due_date END) AS current_to_date,
       c.contract_status
  FROM hrms.employees e
  LEFT JOIN hrms.hr_employee_contract c ON c.emp_id = e.id
  LEFT JOIN hrms.designations d ON d.id = e.desig_id
  LEFT JOIN hrms.departments dp ON dp.id = e.dept_id
 WHERE TRIM(e.emp_type) IN ('1', '3')
   AND (e.sep_date IS NULL OR TRUNC(e.sep_date) > TRUNC(SYSDATE))
   AND NOT EXISTS (SELECT 1 FROM hrms.hr_contract_renewal r
                    WHERE r.emp_id = e.id AND r.status = 'DRAFT')
   AND (c.emp_id IS NULL OR c.contract_status <> 'CLOSED');
