# Short Leave & Short Tour Module for HRMS / Oracle APEX

## Overview
This module handles **Short Leave** (gate pass / hourly leave) and **Short Tour** (short official or personal field visits) with a strict policy rule:
> **Maximum 3 Short Leaves allowed per calendar month** per employee.

## Components Included in this Folder (`Attendance/shortLeave/`):

1. **`01_SHORT_LEAVE_TABLES.sql`**
   - `SHORT_LEAVE_TOUR_REQ`: Master table storing applications for Short Leave and Short Tour (Personal and Official).
   - `SHORT_LEAVE_APP_HISTORY`: Multi-level approval history table (RP -> HOD -> HR).
   - Sequences & Triggers (`SEQ_SHORT_LEAVE_TOUR_REQ`, `TRG_SHORT_LEAVE_TOUR_PK`, `TRG_SHORT_LEAVE_APP_HIST_PK`) generating clean reference IDs (e.g. `SL-202611-0001` or `ST-202611-0001`) and auto-calculating duration in minutes.

2. **`02_FN_CHECK_SHORT_LEAVE_QUOTA.sql`**
   - `fn_get_monthly_sl_count`: Accurately counts an employee's short leaves for the given month.
   - `fn_check_short_leave_quota`: Returns 'Y' or 'N' if quota is within limit (3).
   - `pr_validate_sl_quota`: Raises application error `-20850` with friendly month & count info if exceeded.

3. **`03_PKG_SHORT_LEAVE_APPROVAL.sql`**
   - Package `pkg_short_leave_approval` for full lifecycle:
     - `save_draft`: Validates inputs & monthly quota, saves/updates draft.
     - `submit_request`: Re-verifies monthly quota, builds RP/HOD approval workflow.
     - `process_approval`: Handles APPROVE (moves to next step or final approves) and REJECT.
     - `cancel_request`: Allows applicant to cancel pending/draft request.
     - `delete_draft`: Cleans up unsubmitted drafts.

4. **`04_V_SHORT_LEAVE_VIEWS.sql`**
   - `v_short_leave_my_report`: For applicant register showing status and current approver name.
   - `v_short_leave_pending_inbox`: For approvers showing pending tasks and employee monthly usage stats.

5. **`05_INSTALL_SHORT_LEAVE.sql`**
   - Master installation script. Run in SQL*Plus / SQLcl / APEX SQL Workshop as `HRMS`.

6. **`APEX_PAGE_DESIGN_GUIDE.md`**
   - Step-by-step Oracle APEX Page Designer guide:
     - **Register Page** (Report + monthly quota cards)
     - **Apply Form Page** (Items, Dynamic Actions, Tour field toggle, Month limit validation)
     - **Approval Inbox Page** (Approver actions)

## Installation Instructions
Run in Oracle SQL Workshop or SQL*Plus connected as `HRMS`:
```sql
@05_INSTALL_SHORT_LEAVE.sql
```
