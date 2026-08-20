/* ============================================================
   HRMS EMPLOYEE ACTION PROMOTION COLUMNS
   ============================================================ */

ALTER TABLE hr_employee_action
    ADD (promotion_type VARCHAR2 (20),
         accelerated_count NUMBER (3));

