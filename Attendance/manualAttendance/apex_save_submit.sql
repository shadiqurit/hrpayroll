-- After Submit. Requests CREATE/APPLY/SAVE/FORWARD submit like leave.
-- Page 411 entry. SAVE_DRAFT alone saves without routing.
-- Date item masks: YYYY-MM-DD; punch masks: YYYY-MM-DD HH24:MI.
DECLARE
    l_original_id NUMBER := :P411_ID;
    l_id NUMBER := :P411_ID;
BEGIN
    SAVEPOINT manual_apex_save;
    HRMS.pkg_m_att_approval.save_draft(
        p_att_id => l_id, p_company_id => :G_COM_ID, p_actor_id => :USER_ID,
        p_att_date => TO_DATE(:P411_ATT_DATE, 'YYYY-MM-DD'),
        p_intime => TO_DATE(:P411_M_INTIME, 'YYYY-MM-DD HH24:MI'),
        p_outtime => TO_DATE(:P411_M_OUTTIME, 'YYYY-MM-DD HH24:MI'),
        p_reason => :P411_REASON, p_comments => :P411_COMMENTS);
    IF :REQUEST IN ('CREATE', 'APPLY', 'SAVE', 'FORWARD') THEN
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
