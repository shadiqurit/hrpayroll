-- ============================================================================
-- SHORT LEAVE & SHORT TOUR MODULE
-- 05_INSTALL_SHORT_LEAVE.sql
-- Master Installation Script
-- Run as schema HRMS in SQL*Plus, SQLcl, or APEX SQL Workshop
-- ============================================================================

PROMPT ====================================================================
PROMPT 1. Creating SHORT_LEAVE_TOUR_REQ and SHORT_LEAVE_APP_HISTORY tables...
PROMPT ====================================================================
@@01_SHORT_LEAVE_TABLES.sql

PROMPT ====================================================================
PROMPT 2. Creating Monthly Quota Validation Functions...
PROMPT ====================================================================
@@02_FN_CHECK_SHORT_LEAVE_QUOTA.sql

PROMPT ====================================================================
PROMPT 3. Creating Approval Workflow Package...
PROMPT ====================================================================
@@03_PKG_SHORT_LEAVE_APPROVAL.sql

PROMPT ====================================================================
PROMPT 4. Creating APEX Views for Report & Approval Inbox...
PROMPT ====================================================================
@@04_V_SHORT_LEAVE_VIEWS.sql

PROMPT ====================================================================
PROMPT Installation Complete! 
PROMPT Test queries:
PROMPT   SELECT COUNT(*) FROM HRMS.short_leave_tour_req;
PROMPT   SELECT HRMS.fn_get_monthly_sl_count(1, SYSDATE, 'SHORT_LEAVE', 'PERSONAL') FROM DUAL;
PROMPT ====================================================================
