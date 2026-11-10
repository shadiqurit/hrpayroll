-- After Submit, DELETE_MANUAL only. Disable required-field validations.
BEGIN
    HRMS.pkg_m_att_approval.delete_draft(:P411_ID, :G_COM_ID, :USER_ID);
END;
