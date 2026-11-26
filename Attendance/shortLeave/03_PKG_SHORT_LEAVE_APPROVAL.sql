-- ============================================================================
-- SHORT LEAVE & SHORT TOUR MODULE
-- 03_PKG_SHORT_LEAVE_APPROVAL.sql
-- Package for Short Leave & Short Tour Lifecycle and Approval Routing
-- ============================================================================

CREATE OR REPLACE PACKAGE HRMS.pkg_short_leave_approval
IS
    -- Save Draft / Insert or Update Request
    PROCEDURE save_draft
    (
        p_id                IN OUT NUMBER,
        p_company_id        IN     NUMBER,
        p_actor_id          IN     NUMBER, -- Logged-in user numeric EMPLOYEES.ID
        p_empid             IN     NUMBER,
        p_req_category      IN     VARCHAR2, -- 'SHORT_LEAVE' or 'SHORT_TOUR'
        p_purpose_type      IN     VARCHAR2, -- 'PERSONAL' or 'OFFICIAL'
        p_req_date          IN     DATE,
        p_out_time          IN     DATE,
        p_in_time           IN     DATE,
        p_reason            IN     VARCHAR2,
        p_destination       IN     VARCHAR2 DEFAULT NULL,
        p_contact           IN     VARCHAR2 DEFAULT NULL,
        p_transport_mode    IN     VARCHAR2 DEFAULT NULL,
        p_is_expense_claim  IN     VARCHAR2 DEFAULT 'N',
        p_estimated_expense IN     NUMBER   DEFAULT 0,
        p_comments          IN     VARCHAR2 DEFAULT NULL
    );

    -- Submit / Forward to Approval Workflow
    PROCEDURE submit_request
    (
        p_id         IN NUMBER,
        p_company_id IN NUMBER,
        p_actor_id   IN NUMBER
    );

    -- Approver Action (APPROVE / REJECT / FORWARD)
    PROCEDURE process_approval
    (
        p_history_id IN NUMBER,
        p_action     IN VARCHAR2, -- 'APPROVED' or 'REJECTED'
        p_actor_id   IN NUMBER,
        p_comments   IN VARCHAR2
    );

    -- Cancel Request by Applicant
    PROCEDURE cancel_request
    (
        p_id       IN NUMBER,
        p_actor_id IN NUMBER,
        p_reason   IN VARCHAR2
    );

    -- Delete Draft Request
    PROCEDURE delete_draft
    (
        p_id       IN NUMBER,
        p_actor_id IN NUMBER
    );
END pkg_short_leave_approval;
/

CREATE OR REPLACE PACKAGE BODY HRMS.pkg_short_leave_approval
IS
    -- Private helper: Get employee code
    FUNCTION get_emp_code(p_empid NUMBER) RETURN VARCHAR2 IS
        l_code VARCHAR2(30);
    BEGIN
        SELECT emp_id INTO l_code FROM HRMS.employees WHERE id = p_empid;
        RETURN l_code;
    EXCEPTION WHEN OTHERS THEN
        RETURN TO_CHAR(p_empid);
    END;

    -- Private helper: Resolve Reporting Person (RP)
    FUNCTION get_reporting_person(p_empid NUMBER) RETURN NUMBER IS
        l_rp NUMBER;
    BEGIN
        -- Query existing EMP_RP table using REP_PERSON_ID
        SELECT rep_person_id INTO l_rp 
          FROM HRMS.emp_rp 
         WHERE emp_id = p_empid 
           AND (status IS NULL OR status = 'ACTIVE')
           AND ROWNUM = 1;
        RETURN l_rp;
    EXCEPTION WHEN NO_DATA_FOUND THEN
        RETURN NULL;
    END;

    -- Private helper: Resolve HOD / Dept Head
    FUNCTION get_dept_head(p_empid NUMBER) RETURN NUMBER IS
        l_dept_id NUMBER;
        l_hod     NUMBER;
    BEGIN
        SELECT dept_id INTO l_dept_id FROM HRMS.employees WHERE id = p_empid;
        -- Lookup in HOD table if exists
        BEGIN
            EXECUTE IMMEDIATE 'SELECT emp_id FROM HRMS.hod WHERE dept_id = :1 AND ROWNUM = 1'
            INTO l_hod USING l_dept_id;
            RETURN l_hod;
        EXCEPTION WHEN OTHERS THEN
            RETURN NULL;
        END;
    EXCEPTION WHEN OTHERS THEN
        RETURN NULL;
    END;

    -- ========================================================================
    -- 1. SAVE DRAFT
    -- ========================================================================
    PROCEDURE save_draft
    (
        p_id                IN OUT NUMBER,
        p_company_id        IN     NUMBER,
        p_actor_id          IN     NUMBER,
        p_empid             IN     NUMBER,
        p_req_category      IN     VARCHAR2,
        p_purpose_type      IN     VARCHAR2,
        p_req_date          IN     DATE,
        p_out_time          IN     DATE,
        p_in_time           IN     DATE,
        p_reason            IN     VARCHAR2,
        p_destination       IN     VARCHAR2 DEFAULT NULL,
        p_contact           IN     VARCHAR2 DEFAULT NULL,
        p_transport_mode    IN     VARCHAR2 DEFAULT NULL,
        p_is_expense_claim  IN     VARCHAR2 DEFAULT 'N',
        p_estimated_expense IN     NUMBER   DEFAULT 0,
        p_comments          IN     VARCHAR2 DEFAULT NULL
    )
    IS
        l_emp_code VARCHAR2(30);
        l_minutes  NUMBER := 0;
        l_display  VARCHAR2(30);
    BEGIN
        -- Basic validations
        IF p_empid IS NULL THEN
            RAISE_APPLICATION_ERROR(-20851, 'Employee ID is required.');
        END IF;
        IF p_req_date IS NULL THEN
            RAISE_APPLICATION_ERROR(-20852, 'Leave / Tour Date is required.');
        END IF;
        IF p_out_time IS NULL OR p_in_time IS NULL THEN
            RAISE_APPLICATION_ERROR(-20853, 'From Time and To Time are required.');
        END IF;
        IF p_in_time <= p_out_time THEN
            RAISE_APPLICATION_ERROR(-20854, 'To Time must be greater than From Time.');
        END IF;
        IF TRIM(p_reason) IS NULL THEN
            RAISE_APPLICATION_ERROR(-20855, 'Reason / Purpose is required.');
        END IF;

        -- Strict Monthly Quota Check: Max 3 allowed short leaves per month
        HRMS.pr_validate_sl_quota(
            p_empid        => p_empid,
            p_req_date     => p_req_date,
            p_req_category => p_req_category,
            p_purpose_type => p_purpose_type,
            p_exclude_id   => p_id,
            p_max_allowed  => 3
        );

        -- Duration calculation
        l_minutes := ROUND((p_in_time - p_out_time) * 24 * 60);
        l_display := TRUNC(l_minutes / 60) || ' hr ' || MOD(l_minutes, 60) || ' min';
        l_emp_code := get_emp_code(p_empid);

        IF p_id IS NULL THEN
            -- INSERT NEW DRAFT
            INSERT INTO HRMS.short_leave_tour_req
            (
                empid, empcode, com_id, req_category, purpose_type,
                req_date, out_time, in_time, duration_minutes, duration_display,
                reason_purpose, destination_place, contact_during_abs,
                transport_mode, is_expense_claim, estimated_expense,
                status, request_status, current_stage,
                ent_date, ent_by, comments
            )
            VALUES
            (
                p_empid, l_emp_code, p_company_id, p_req_category, p_purpose_type,
                TRUNC(p_req_date), p_out_time, p_in_time, l_minutes, l_display,
                p_reason, p_destination, p_contact,
                p_transport_mode, NVL(p_is_expense_claim, 'N'), NVL(p_estimated_expense, 0),
                'D', 'D', 'DRAFT',
                SYSDATE, p_actor_id, p_comments
            )
            RETURNING id INTO p_id;
        ELSE
            -- UPDATE EXISTING DRAFT (Only if in Draft status)
            UPDATE HRMS.short_leave_tour_req
               SET req_category       = p_req_category,
                   purpose_type       = p_purpose_type,
                   req_date           = TRUNC(p_req_date),
                   out_time           = p_out_time,
                   in_time            = p_in_time,
                   duration_minutes   = l_minutes,
                   duration_display   = l_display,
                   reason_purpose     = p_reason,
                   destination_place  = p_destination,
                   contact_during_abs = p_contact,
                   transport_mode     = p_transport_mode,
                   is_expense_claim   = NVL(p_is_expense_claim, 'N'),
                   estimated_expense  = NVL(p_estimated_expense, 0),
                   comments           = p_comments,
                   upd_date           = SYSDATE,
                   upd_by             = p_actor_id
             WHERE id = p_id
               AND request_status = 'D';

            IF SQL%ROWCOUNT = 0 THEN
                RAISE_APPLICATION_ERROR(-20856, 'Only Draft requests can be edited.');
            END IF;
        END IF;
    END save_draft;

    -- ========================================================================
    -- 2. SUBMIT / FORWARD REQUEST
    -- ========================================================================
    PROCEDURE submit_request
    (
        p_id         IN NUMBER,
        p_company_id IN NUMBER,
        p_actor_id   IN NUMBER
    )
    IS
        l_rec        HRMS.short_leave_tour_req%ROWTYPE;
        l_rp_id      NUMBER;
        l_hod_id     NUMBER;
        l_step       NUMBER := 10;
    BEGIN
        SELECT * INTO l_rec 
          FROM HRMS.short_leave_tour_req 
         WHERE id = p_id;

        IF l_rec.request_status NOT IN ('D') THEN
            RAISE_APPLICATION_ERROR(-20857, 'Request has already been submitted.');
        END IF;

        -- Re-verify monthly quota before final submission
        HRMS.pr_validate_sl_quota(
            p_empid        => l_rec.empid,
            p_req_date     => l_rec.req_date,
            p_req_category => l_rec.req_category,
            p_purpose_type => l_rec.purpose_type,
            p_exclude_id   => l_rec.id,
            p_max_allowed  => 3
        );

        -- Delete any pre-existing orphan history
        DELETE FROM HRMS.short_leave_app_history WHERE req_id = p_id;

        l_rp_id := get_reporting_person(l_rec.empid);
        l_hod_id := get_dept_head(l_rec.empid);

        -- Build workflow steps
        IF l_rp_id IS NOT NULL AND l_rp_id <> l_rec.empid THEN
            -- Step 1: RP is PENDING
            INSERT INTO HRMS.short_leave_app_history
            (
                req_id, step_no, approver_level, approver_id,
                approval_status, com_id, ent_date, ent_by
            )
            VALUES
            (
                p_id, 10, 'RP', l_rp_id,
                'PENDING', p_company_id, SYSDATE, p_actor_id
            );

            -- Step 2: HOD is WAITING
            IF l_hod_id IS NOT NULL AND l_hod_id <> l_rp_id THEN
                INSERT INTO HRMS.short_leave_app_history
                (
                    req_id, step_no, approver_level, approver_id,
                    approval_status, com_id, ent_date, ent_by
                )
                VALUES
                (
                    p_id, 20, 'HOD', l_hod_id,
                    'WAITING', p_company_id, SYSDATE, p_actor_id
                );
            END IF;

            UPDATE HRMS.short_leave_tour_req
               SET status         = 'P',
                   request_status = 'F',
                   current_stage  = 'PENDING_RP',
                   upd_date       = SYSDATE,
                   upd_by         = p_actor_id
             WHERE id = p_id;

        ELSIF l_hod_id IS NOT NULL AND l_hod_id <> l_rec.empid THEN
            -- Step 1: HOD is directly PENDING
            INSERT INTO HRMS.short_leave_app_history
            (
                req_id, step_no, approver_level, approver_id,
                approval_status, com_id, ent_date, ent_by
            )
            VALUES
            (
                p_id, 20, 'HOD', l_hod_id,
                'PENDING', p_company_id, SYSDATE, p_actor_id
            );

            UPDATE HRMS.short_leave_tour_req
               SET status         = 'P',
                   request_status = 'F',
                   current_stage  = 'PENDING_HOD',
                   upd_date       = SYSDATE,
                   upd_by         = p_actor_id
             WHERE id = p_id;
        ELSE
            -- No supervisor found, auto-approve or route to HR
            UPDATE HRMS.short_leave_tour_req
               SET status         = 'A',
                   request_status = 'A',
                   current_stage  = 'APPROVED',
                   upd_date       = SYSDATE,
                   upd_by         = p_actor_id
             WHERE id = p_id;
        END IF;

    EXCEPTION WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20858, 'Short leave request not found.');
    END submit_request;

    -- ========================================================================
    -- 3. PROCESS APPROVAL
    -- ========================================================================
    PROCEDURE process_approval
    (
        p_history_id IN NUMBER,
        p_action     IN VARCHAR2, -- 'APPROVED' or 'REJECTED'
        p_actor_id   IN NUMBER,
        p_comments   IN VARCHAR2
    )
    IS
        l_req_id     NUMBER;
        l_step_no    NUMBER;
        l_level      VARCHAR2(50);
        l_next_count NUMBER;
    BEGIN
        SELECT req_id, step_no, approver_level
          INTO l_req_id, l_step_no, l_level
          FROM HRMS.short_leave_app_history
         WHERE id = p_history_id
           AND approval_status = 'PENDING';

        IF p_action = 'REJECTED' THEN
            -- Update current step to REJECTED
            UPDATE HRMS.short_leave_app_history
               SET approval_status = 'REJECTED',
                   approval_date   = SYSDATE,
                   comments        = p_comments,
                   upd_date        = SYSDATE,
                   upd_by          = p_actor_id
             WHERE id = p_history_id;

            -- Cancel any remaining waiting steps
            UPDATE HRMS.short_leave_app_history
               SET approval_status = 'CANCELLED',
                   upd_date        = SYSDATE,
                   upd_by          = p_actor_id
             WHERE req_id = l_req_id
               AND approval_status = 'WAITING';

            -- Update main request to Rejected
            UPDATE HRMS.short_leave_tour_req
               SET status         = 'R',
                   request_status = 'R',
                   current_stage  = 'REJECTED',
                   upd_date       = SYSDATE,
                   upd_by         = p_actor_id
             WHERE id = l_req_id;

        ELSIF p_action = 'APPROVED' THEN
            -- Mark current step as APPROVED
            UPDATE HRMS.short_leave_app_history
               SET approval_status = 'APPROVED',
                   approval_date   = SYSDATE,
                   comments        = p_comments,
                   upd_date        = SYSDATE,
                   upd_by          = p_actor_id
             WHERE id = p_history_id;

            -- Check if there is a next WAITING step
            SELECT COUNT(*) INTO l_next_count
              FROM HRMS.short_leave_app_history
             WHERE req_id = l_req_id
               AND approval_status = 'WAITING';

            IF l_next_count > 0 THEN
                -- Promote lowest WAITING step to PENDING
                UPDATE HRMS.short_leave_app_history
                   SET approval_status = 'PENDING',
                       upd_date        = SYSDATE,
                       upd_by          = p_actor_id
                 WHERE req_id = l_req_id
                   AND step_no = (
                       SELECT MIN(step_no)
                         FROM HRMS.short_leave_app_history
                        WHERE req_id = l_req_id
                          AND approval_status = 'WAITING'
                   );

                UPDATE HRMS.short_leave_tour_req
                   SET current_stage = 'PENDING_NEXT',
                       upd_date      = SYSDATE,
                       upd_by        = p_actor_id
                 WHERE id = l_req_id;
            ELSE
                -- All steps completed -> FINAL APPROVAL!
                UPDATE HRMS.short_leave_tour_req
                   SET status         = 'A',
                       request_status = 'A',
                       current_stage  = 'APPROVED',
                       upd_date       = SYSDATE,
                       upd_by         = p_actor_id
                 WHERE id = l_req_id;
            END IF;
        ELSE
            RAISE_APPLICATION_ERROR(-20859, 'Invalid approval action: ' || p_action);
        END IF;

    EXCEPTION WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20860, 'Pending approval task not found or already processed.');
    END process_approval;

    -- ========================================================================
    -- 4. CANCEL REQUEST
    -- ========================================================================
    PROCEDURE cancel_request
    (
        p_id       IN NUMBER,
        p_actor_id IN NUMBER,
        p_reason   IN VARCHAR2
    )
    IS
    BEGIN
        UPDATE HRMS.short_leave_tour_req
           SET status         = 'C',
               request_status = 'C',
               current_stage  = 'CANCELLED',
               comments       = NVL(comments, '') || ' [Cancelled: ' || p_reason || ']',
               upd_date       = SYSDATE,
               upd_by         = p_actor_id
         WHERE id = p_id
           AND status IN ('D', 'P');

        IF SQL%ROWCOUNT = 0 THEN
            RAISE_APPLICATION_ERROR(-20861, 'Only Draft or Pending requests can be cancelled.');
        END IF;

        UPDATE HRMS.short_leave_app_history
           SET approval_status = 'CANCELLED',
               upd_date        = SYSDATE,
               upd_by          = p_actor_id
         WHERE req_id = p_id
           AND approval_status IN ('PENDING', 'WAITING');
    END cancel_request;

    -- ========================================================================
    -- 5. DELETE DRAFT
    -- ========================================================================
    PROCEDURE delete_draft
    (
        p_id       IN NUMBER,
        p_actor_id IN NUMBER
    )
    IS
    BEGIN
        DELETE FROM HRMS.short_leave_tour_req
         WHERE id = p_id
           AND request_status = 'D';

        IF SQL%ROWCOUNT = 0 THEN
            RAISE_APPLICATION_ERROR(-20862, 'Only Draft applications can be deleted.');
        END IF;
    END delete_draft;

END pkg_short_leave_approval;
/
