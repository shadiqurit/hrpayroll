-- After Submit. Requests CREATE/APPLY/SAVE/FORWARD submit like leave.
-- Page 411 entry. SAVE_DRAFT alone saves without routing.
-- Date item masks: YYYY-MM-DD; punch masks: YYYY-MM-DD HH24:MI.
DECLARE
    l_original_id NUMBER := :P411_ID;
    l_id NUMBER := :P411_ID;

    FUNCTION to_dt(p_str VARCHAR2, p_is_time BOOLEAN DEFAULT FALSE) RETURN DATE IS
    BEGIN
        IF TRIM(p_str) IS NULL THEN RETURN NULL; END IF;
        IF p_is_time THEN
            BEGIN RETURN TO_DATE(p_str, 'DD-MON-YYYY HH12:MI AM'); EXCEPTION WHEN OTHERS THEN NULL; END;
            BEGIN RETURN TO_DATE(p_str, 'DD-MON-YYYY HH24:MI'); EXCEPTION WHEN OTHERS THEN NULL; END;
            BEGIN RETURN TO_DATE(p_str, 'DD-MON-RRRR HH12:MI AM'); EXCEPTION WHEN OTHERS THEN NULL; END;
            BEGIN RETURN TO_DATE(p_str, 'DD-MON-RRRR HH24:MI'); EXCEPTION WHEN OTHERS THEN NULL; END;
            BEGIN RETURN TO_DATE(p_str, 'YYYY-MM-DD HH24:MI'); EXCEPTION WHEN OTHERS THEN NULL; END;
        ELSE
            BEGIN RETURN TO_DATE(p_str, 'DD-MON-YYYY'); EXCEPTION WHEN OTHERS THEN NULL; END;
            BEGIN RETURN TO_DATE(p_str, 'DD-MON-RRRR'); EXCEPTION WHEN OTHERS THEN NULL; END;
            BEGIN RETURN TO_DATE(p_str, 'YYYY-MM-DD'); EXCEPTION WHEN OTHERS THEN NULL; END;
        END IF;
        RETURN TO_DATE(p_str);
    END;
BEGIN
    SAVEPOINT manual_apex_save;
    HRMS.pkg_m_att_approval.save_draft(
        p_att_id    => l_id, 
        p_company_id=> :G_COM_ID, 
        p_actor_id  => :USER_ID,
        p_att_date  => to_dt(:P411_ATT_DATE, FALSE),
        p_intime    => to_dt(:P411_M_INTIME, TRUE),
        p_outtime   => to_dt(:P411_M_OUTTIME, TRUE),
        p_reason    => :P411_REASON, 
        p_comments  => :P411_COMMENTS);
    IF :REQUEST IN ('CREATE', 'APPLY', 'SAVE', 'FORWARD', 'SUBMIT') THEN
        HRMS.pkg_m_att_approval.submit_request(l_id, :G_COM_ID, :USER_ID);
    ELSIF :REQUEST <> 'SAVE_DRAFT' OR :REQUEST IS NULL THEN
        RAISE_APPLICATION_ERROR(-20810, 'Unsupported manual attendance form request.');
    END IF;
    :P411_ID := l_id;
EXCEPTION WHEN OTHERS THEN
    ROLLBACK TO manual_apex_save;
    :P411_ID := l_original_id;
    RAISE;
END;
