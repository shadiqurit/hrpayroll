DROP PROCEDURE HRMS.GENERATE_MONTHLY_SALARY;

CREATE OR REPLACE PROCEDURE HRMS.generate_monthly_salary (
    p_salary_month   IN NUMBER,
    p_employee_id    IN NUMBER DEFAULT NULL,
    p_created_by     IN NUMBER DEFAULT NULL)
IS
    v_ms_id            NUMBER;
    v_total_earn       NUMBER := 0;
    v_total_ded        NUMBER := 0;
    v_exists           NUMBER;
    v_adv_amount       NUMBER := 0;
    v_installment_no   NUMBER;
    v_due_date         DATE;

    -- Cursor for advances that need processing
    CURSOR cur_advances (cp_employee_id NUMBER, cp_salary_month NUMBER)
    IS
        SELECT adv.adv_id,
               adv.emp_id,
               adv.adv_head_id,
               ah.head_code,
               ah.head_name,
               nvl(adv.installment_amount,0) installment_amount,
               adv.approved_amount,
               adv.no_of_installment,
               adv.ref_no,
               adv.issue_date,
               NVL (
                   (SELECT SUM (d.amount)
                      FROM monthly_salary_details  d
                           JOIN monthly_salary m ON d.ms_id = m.ms_id
                     WHERE     m.employee_id = adv.emp_id
                           AND d.source = 'ADVANCE'
                           AND d.headcode = '0' || TO_CHAR (adv.adv_head_id)
                           AND m.salary_month < cp_salary_month),
                   0)    AS total_paid
          FROM hr_adv_requests  adv
               JOIN allowance_head ah ON adv.adv_head_id = ah.head_id
         WHERE     adv.emp_id = cp_employee_id
               AND adv.status = 'ISSUED'
               AND adv.adv_status = 'Open'
               AND adv.hold_yn = 'N'
               AND adv.issue_date <=
                   LAST_DAY (TO_DATE (cp_salary_month, 'YYYYMM'));
BEGIN
    FOR emp IN (SELECT DISTINCT employee_id
                  FROM emp_salary_structure
                 WHERE employee_id = NVL (p_employee_id, employee_id))
    LOOP
        SELECT COUNT (1)
          INTO v_exists
          FROM monthly_salary
         WHERE     employee_id = emp.employee_id
               AND salary_month = p_salary_month;

        IF v_exists > 0
        THEN
            CONTINUE;
        END IF;

        -- Insert master
        INSERT INTO monthly_salary (employee_id,
                                    salary_month,
                                    created_by,
                                    created_date)
             VALUES (emp.employee_id,
                     p_salary_month,
                     p_created_by,
                     SYSDATE)
          RETURNING ms_id
               INTO v_ms_id;

        -- Insert from salary structure
        INSERT INTO monthly_salary_details (ms_id,
                                            employee_id,
                                            salary_month,
                                            slno,
                                            headcode,
                                            head_name,
                                            head_type,
                                            amount,
                                            source,
                                            created_by,
                                            created_date)
            SELECT v_ms_id,
                   sl.employee_id,
                   p_salary_month,
                   sl.slno,
                   sl.headcode,
                   ah.head_name,
                   ah.head_type,
                   sl.amount,
                   'STRUCTURE',
                   p_created_by,
                   SYSDATE
              FROM emp_salary_structure  sl
                   JOIN allowance_head ah ON sl.slno = ah.head_id
             WHERE sl.employee_id = emp.employee_id;

        -- Insert from adjustments (additional earnings/deductions)
        INSERT INTO monthly_salary_details (ms_id,
                                            employee_id,
                                            salary_month,
                                            slno,
                                            headcode,
                                            head_name,
                                            head_type,
                                            amount,
                                            source,
                                            remarks,
                                            created_by,
                                            created_date)
            SELECT v_ms_id,
                   adj.employee_id,
                   p_salary_month,
                   NULL,
                   adj.headcode,
                   adj.head_name,
                   adj.head_type,
                   adj.amount,
                   'ADDITIONAL',
                   adj.remarks,
                   p_created_by,
                   SYSDATE
              FROM monthly_salary_adjustment adj
             WHERE     adj.employee_id = emp.employee_id
                   AND adj.salary_month = p_salary_month;

        -- Process advances and insert deductions + installments
        FOR adv_rec IN cur_advances (emp.employee_id, p_salary_month)
        LOOP
            -- Check if advance is not fully recovered
            IF adv_rec.total_paid < adv_rec.approved_amount
            THEN
                -- Get next installment number
                SELECT NVL (MAX (installment_no), 0) + 1
                  INTO v_installment_no
                  FROM hr_adv_installments
                 WHERE adv_id = adv_rec.adv_id;

                -- Calculate due date (based on salary month)
                v_due_date := LAST_DAY (TO_DATE (p_salary_month, 'YYYYMM'));

                -- Insert into monthly_salary_details (deduction)
                INSERT INTO monthly_salary_details (ms_id,
                                                    employee_id,
                                                    salary_month,
                                                    slno,
                                                    headcode,
                                                    head_name,
                                                    head_type,
                                                    amount,
                                                    source,
                                                    remarks,
                                                    created_by,
                                                    created_date)
                         VALUES (        v_ms_id,
                                    adv_rec.emp_id,
                                    p_salary_month,
                                    adv_rec.adv_head_id,
                                    adv_rec.head_code,
                                    adv_rec.head_name,
                                    'DEDUCTION',
                                    LEAST (
                                        adv_rec.installment_amount,
                                          adv_rec.approved_amount
                                        - adv_rec.total_paid),
                                    'ADVANCE',
                                       'Ref: '
                                    || adv_rec.ref_no
                                    || ' | Installment: '
                                    || v_installment_no
                                    || '/'
                                    || adv_rec.no_of_installment,
                                    p_created_by,
                                    SYSDATE);

                -- Insert into hr_adv_installments
                INSERT INTO hr_adv_installments (yearmn,
                                                 adv_id,
                                                 installment_no,
                                                 due_date,
                                                 installment_amount,
                                                 paid_amount,
                                                 status,
                                                 paid_date,
                                                 remarks)
                         VALUES (
                                    p_salary_month,
                                    adv_rec.adv_id,
                                    v_installment_no,
                                    v_due_date,
                                    adv_rec.installment_amount,
                                    LEAST (
                                        adv_rec.installment_amount,
                                          adv_rec.approved_amount
                                        - adv_rec.total_paid),
                                    'PAID',
                                    SYSDATE,
                                       'Auto-deducted from salary: '
                                    || p_salary_month);

                -- Update advance status if fully paid
                IF (adv_rec.total_paid + adv_rec.installment_amount) >=
                   adv_rec.approved_amount
                THEN
                    UPDATE hr_adv_requests
                       SET adv_status = 'Completed',
                           remarks =
                               CASE
                                   WHEN remarks IS NULL
                                   THEN
                                       'Fully recovered'
                                   ELSE
                                       remarks || ' | Fully recovered'
                               END
                     WHERE adv_id = adv_rec.adv_id;
                END IF;
            END IF;
        END LOOP;

        -- Calculate totals
        SELECT NVL (
                   SUM (
                       CASE WHEN head_type = 'EARNING' THEN amount ELSE 0 END),
                   0),
               NVL (
                   SUM (
                       CASE
                           WHEN head_type = 'DEDUCTION' THEN amount
                           ELSE 0
                       END),
                   0)
          INTO v_total_earn, v_total_ded
          FROM monthly_salary_details
         WHERE ms_id = v_ms_id;

        -- Update master
        UPDATE monthly_salary
           SET total_earning = v_total_earn,
               total_deduction = v_total_ded,
               net_salary = v_total_earn - v_total_ded
         WHERE ms_id = v_ms_id;
    END LOOP;

    COMMIT;
END;
/
