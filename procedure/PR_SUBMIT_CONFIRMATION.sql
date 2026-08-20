CREATE OR REPLACE PROCEDURE HRMS.PR_SUBMIT_CONFIRMATION
(
    p_confirm_id   IN NUMBER,
    p_user_id      IN NUMBER
)
IS
    v_status          VARCHAR2(20);
    v_basic           NUMBER := 0;
    v_gross           NUMBER := 0;
    v_active_count    NUMBER := 0;
BEGIN
    SELECT status
      INTO v_status
      FROM hr_confirmation
     WHERE confirm_id = p_confirm_id
       FOR UPDATE;

    IF v_status <> 'DRAFT' THEN
        RAISE_APPLICATION_ERROR(
            -20110,
            'Only DRAFT confirmation can be submitted.'
        );
    END IF;


    SELECT COUNT(*)
      INTO v_active_count
      FROM hr_confirmation_salary_dtl
     WHERE confirm_id = p_confirm_id
       AND NVL(is_active,'Y') = 'Y';

    IF v_active_count = 0 THEN
        RAISE_APPLICATION_ERROR(
            -20111,
            'No salary structure found.'
        );
    END IF;


    SELECT NVL(MAX(
               CASE
                   WHEN slno = 1
                   THEN proposed_amount
               END
           ),0),

           NVL(SUM(
               CASE
                   /*
                      Earnings are added.
                   */
                   WHEN head_type = 'EARNING'
                   THEN NVL(proposed_amount,0)

                   /*
                      Only PF contribution 057 is deducted
                      for your protected/gross package.
                   */
                   WHEN slno = 57
                   THEN -NVL(proposed_amount,0)

                   ELSE 0
               END
           ),0)

      INTO v_basic,
           v_gross

      FROM hr_confirmation_salary_dtl
     WHERE confirm_id = p_confirm_id
       AND NVL(is_active,'Y') = 'Y';


    IF v_basic <= 0 THEN
        RAISE_APPLICATION_ERROR(
            -20112,
            'Basic salary cannot be zero.'
        );
    END IF;


    UPDATE hr_confirmation
       SET proposed_basic = v_basic,
           proposed_gross = ROUND(v_gross,0),

           status         = 'PENDING',

           submitted_by   = p_user_id,
           submitted_date = SYSDATE

     WHERE confirm_id = p_confirm_id;


    COMMIT;

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END PR_SUBMIT_CONFIRMATION;
/
