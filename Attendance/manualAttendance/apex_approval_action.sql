-- After Submit for approval SUBMIT only. No automatic history/form DML.
BEGIN
    HRMS.pkg_m_att_approval.take_action(
        p_att_id => :P418_ID, p_company_id => :G_COM_ID, p_actor_id => :USER_ID,
        p_action => :P418_ACTION, p_comments => :P418_ACTION_COMMENTS);
END;
