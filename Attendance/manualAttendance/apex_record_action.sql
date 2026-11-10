-- After Submit, When Button Pressed = RECORD. HRD is not another approver.
BEGIN
    HRMS.pkg_m_att_approval.take_action(
        p_att_id => :P418_ID, p_company_id => :G_COM_ID, p_actor_id => :USER_ID,
        p_action => 'RECORD', p_comments => :P418_ACTION_COMMENTS);
END;
