-- Approved request totals by START month; not an allocation/consumption balance.
-- Preserve the existing seven-column interface and SL+CL+EL total definition.
CREATE OR REPLACE VIEW HRMS.v_emp_leave_total
    (empid, yearmn, sl_days, cl_days, el_days, total_leave, el_encash)
AS
SELECT lr.empid,
       TO_CHAR(lr.l_start_date, 'YYYYMM') AS yearmn,
       SUM(CASE WHEN UPPER(TRIM(lt.short_code)) = 'SL' THEN lr.proposed_days ELSE 0 END),
       SUM(CASE WHEN UPPER(TRIM(lt.short_code)) = 'CL' THEN lr.proposed_days ELSE 0 END),
       SUM(CASE WHEN UPPER(TRIM(lt.short_code)) = 'EL' THEN lr.proposed_days ELSE 0 END),
       SUM(CASE WHEN UPPER(TRIM(lt.short_code)) IN ('SL', 'CL', 'EL')
                THEN lr.proposed_days ELSE 0 END),
       SUM(CASE WHEN UPPER(TRIM(lt.short_code)) = 'EC' THEN lr.proposed_days ELSE 0 END)
  FROM HRMS.leave_request lr
  JOIN HRMS.leave_types lt ON TRIM(lr.leave_type) = TO_CHAR(lt.lt_id)
 WHERE lr.leave_status = 'A' AND lr.request_status = 'A'
 GROUP BY lr.empid, TO_CHAR(lr.l_start_date, 'YYYYMM');
