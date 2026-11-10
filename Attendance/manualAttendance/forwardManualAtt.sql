CREATE OR REPLACE PROCEDURE HRMS.forward_attendance_approval (
    p_att_id            IN NUMBER,
    p_approver_id       IN NUMBER,
    p_approval_status   IN VARCHAR2,
    p_approver_level    IN VARCHAR2,
    p_action            IN VARCHAR2)
IS
    v_next_approver_id      NUMBER;
    v_next_approver_level   VARCHAR2 (50);
    v_hr_id                 NUMBER := 200007478;
    v_all_approved          NUMBER := 0;
BEGIN
    -- Step 1: Update the manual_att status based on the approval status
    IF p_approval_status = 'F'
    THEN
        UPDATE manual_att
           SET status = 'F', upd_date = SYSDATE, upd_by = p_approver_id
         WHERE id = p_att_id;
    ELSIF p_approval_status = 'R'
    THEN
        UPDATE manual_att
           SET status = 'R', upd_date = SYSDATE, upd_by = p_approver_id
         WHERE id = p_att_id;

        -- If any approver rejects, set status to REJECTED immediately and exit procedure
        COMMIT;
        RETURN;
    END IF;

    -- Step 2: Handle Forward action to the next level (RP -> HOD -> MD -> HR)
    IF p_action = 'F'
    THEN
        IF p_approver_level = 'RP'
        THEN
            -- Get HOD ID from the hod table
            BEGIN
                SELECT hod_id
                  INTO v_next_approver_id
                  FROM hod
                 WHERE dept_id = (SELECT dept_id
                                    FROM employees
                                   WHERE id = p_approver_id);
            EXCEPTION
                WHEN NO_DATA_FOUND
                THEN
                    v_next_approver_id := NULL;
            END;

            -- Set next approver level to HOD
            v_next_approver_level := 'HOD';
        ELSIF p_approver_level = 'HOD'
        THEN
            -- Hardcoded MD ID
            v_next_approver_id := 200007478;
            v_next_approver_level := 'HR';
        ELSIF p_approver_level = 'HR'
        THEN
            -- Set the approval status to 'A' for MD
            UPDATE m_att_app_history
               SET approval_status = 'A', approval_date = SYSDATE
             WHERE     m_att_id = p_att_id
                   AND approver_level = 'HR'
                   AND approver_id = p_approver_id;

            UPDATE manual_att
               SET status = 'A', upd_date = SYSDATE, upd_by = p_approver_id
             WHERE id = p_att_id;


            COMMIT;
            RETURN;
        END IF;

        -- Step 3: Update m_att_app_history for current approver level with APPROVED status
        UPDATE m_att_app_history
           SET approval_status = 'A', approval_date = SYSDATE
         WHERE     m_att_id = p_att_id
               AND approver_level = p_approver_level
               AND approver_id = p_approver_id;



        -- Step 4: Insert the next approver into m_att_app_history with PENDING status
        INSERT INTO m_att_app_history (m_att_id,
                                       approver_level,
                                       approver_id,
                                       approval_status,
                                       approval_date,
                                       comments,
                                       ent_date,
                                       ent_by)
             VALUES (p_att_id,
                     v_next_approver_level,
                     v_next_approver_id,
                     'P',
                     SYSDATE,
                     'Awaiting ' || v_next_approver_level || ' approval',
                     SYSDATE,
                     p_approver_id);

        -- Step 5: Update manual_att status to PENDING for the next level approver
        UPDATE manual_att
           SET status = 'F', upd_date = SYSDATE, upd_by = p_approver_id
         WHERE id = p_att_id;



        -- Check if all levels have approved
        SELECT COUNT (*)
          INTO v_all_approved
          FROM m_att_app_history
         WHERE m_att_id = p_att_id AND approval_status != 'A';

        IF v_all_approved = 0
        THEN
            -- If all approval levels have approved, set the manual_att status to APPROVED
            UPDATE manual_att
               SET status = 'A', upd_date = SYSDATE, upd_by = p_approver_id
             WHERE id = p_att_id;
        END IF;
    END IF;

    -- Commit the transaction
    COMMIT;
EXCEPTION
    WHEN OTHERS
    THEN
        ROLLBACK;
        RAISE;
END forward_attendance_approval;
/
