/* Remove ONLY the marked print sample created by the companion script.
   Run as HRMS in a fresh SQL session after printing; matching deletions commit.
   Employee/payroll/contract data is never changed.
*/
SET SERVEROUTPUT ON;
SET DEFINE OFF;

DECLARE
    c_emp_id       CONSTANT NUMBER := 155008361;
    c_reference    CONSTANT VARCHAR2(30) := 'TMP-CEX-155008361';
    c_marker       CONSTANT VARCHAR2(100) := 'TEMP_PRINT_SAMPLE_155008361';
    l_extension_id NUMBER;
    l_letter_id    NUMBER;
    l_action_id    NUMBER;
    l_count        PLS_INTEGER;
BEGIN
    SAVEPOINT BEFORE_REMOVE_PRINT_SAMPLE;
    SELECT COUNT(*) INTO l_count FROM hrms.hr_contract_extension
     WHERE emp_id = c_emp_id AND extension_no = c_reference AND reason = c_marker;
    IF l_count > 0 THEN
        SELECT extension_id, letter_id, action_id
          INTO l_extension_id, l_letter_id, l_action_id
          FROM hrms.hr_contract_extension
         WHERE emp_id = c_emp_id AND extension_no = c_reference AND reason = c_marker
           FOR UPDATE NOWAIT;

        /* Clear the circular header -> letter link before removing the letter. */
        UPDATE hrms.hr_contract_extension SET letter_id = NULL
         WHERE extension_id = l_extension_id;
        DELETE FROM hrms.hr_employee_letter
         WHERE letter_id = l_letter_id AND emp_id = c_emp_id
           AND contract_extension_id = l_extension_id
           AND letter_no = c_reference
           AND subject_text = 'SAMPLE - Extension of Confirmation Due Date';
        IF SQL%ROWCOUNT <> 1 THEN
            RAISE_APPLICATION_ERROR(-20810, 'Sample letter did not match; cleanup was rolled back.');
        END IF;
        DELETE FROM hrms.hr_contract_extension
         WHERE extension_id = l_extension_id AND emp_id = c_emp_id
           AND extension_no = c_reference AND reason = c_marker;
        IF SQL%ROWCOUNT <> 1 THEN
            RAISE_APPLICATION_ERROR(-20810, 'Sample extension did not match; cleanup was rolled back.');
        END IF;
        DELETE FROM hrms.hr_employee_action
         WHERE action_id = l_action_id AND emp_id = c_emp_id
           AND action_type = 'CONTRACT_EXTENSION' AND reason = c_marker;
        IF SQL%ROWCOUNT <> 1 THEN
            RAISE_APPLICATION_ERROR(-20810, 'Sample action did not match; cleanup was rolled back.');
        END IF;
        DBMS_OUTPUT.PUT_LINE('Removed temporary print sample ' || c_reference || '.');
        COMMIT;
    ELSE
        DBMS_OUTPUT.PUT_LINE('No matching temporary print sample exists. Nothing was deleted.');
    END IF;
EXCEPTION WHEN OTHERS THEN
    ROLLBACK TO BEFORE_REMOVE_PRINT_SAMPLE;
    RAISE;
END;
/
