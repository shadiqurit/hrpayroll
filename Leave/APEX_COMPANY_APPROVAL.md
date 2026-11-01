# Leave application, sequential approvals, and HRD records

The approval order is **RP → HOD → PLANT_HEAD → MANAGING_DIRECTOR →
LEAVE_RECORD**. RP and HOD are optional; Plant Head and MD are company-wise
approvers. HRD records the approved leave and does not approve it again.

| Applicant/setup | Route |
| --- | --- |
| Employee with RP and HOD | RP → HOD → Plant Head → MD → HRD record |
| Employee without RP | HOD → Plant Head → MD → HRD record |
| Employee without HOD | RP → Plant Head → MD → HRD record |
| Employee without RP or HOD | Plant Head → MD → HRD record |
| HOD applying for own leave | Plant Head → MD → HRD record |
| Plant Head applying for own leave | MD → HRD record |

The confirmed sequence includes HOD after RP when both are assigned.
Missing RP/HOD assignments are omitted. Applicants never
approve their own leave; heads start above their own role. If one employee
holds multiple approval roles, retain their highest role so they approve
once. The HRD recording action remains separate even if that employee also
holds an approval role. MD's own leave is refused because a higher approver
has not been specified; it is never automatically approved.

Shared-role examples (`A` and `B` are different employees):

| Assignments | Approval sequence before HRD recording |
| --- | --- |
| RP=A, HOD=A, Plant Head=B | A once as HOD → B as Plant Head → MD |
| RP=A, HOD=B, Plant Head=B | A as RP → B once as Plant Head → MD |
| RP=A, HOD=B, Plant Head=A | B as HOD → A once as Plant Head → MD |
| RP=A, HOD=A, Plant Head=A | A once as Plant Head → MD |

One approval completes all shared approval roles for that employee. It then
moves to the next different approver; the request stays forwarded until MD
approval. Shared roles are combined when Apply/Forward builds a new route. Existing
routes with repeated assignments require review and are not silently rewritten.

## Sources and existing tables

No new columns are needed in the supplied `LEAVE_REQUEST` and
`LEAVE_APP_HISTORY` tables. `V_LEAVE_APPROVAL_STEPS` derives order from
`APPROVER_LEVEL`: RP=10, HOD=20, Plant Head=30, MD=40, HRD=50.

- RP: `EMP_RP.EMP_ID`, `REP_PERSON_ID`; active STATUS accepts `ACTIVE`, `1`,
  or `Y`. The table export defaults to `ACTIVE`, while old leave code used `1`.
- HOD: existing `HOD.DEPT_ID` and `HOD.HOD_ID`, matched to the applicant's
  `EMPLOYEES.DEPT_ID` and the head's `EMPLOYEES.COM_ID`, with
  `UPPER(TRIM(HOD.STATUS)) = 'ACTIVE'`.
- Plant Head, MD, HRD: existing `V_LEAVE_ROLES`, using active company roles
  `PLANT_HEAD`, `MANAGING_DIRECTOR`, `LEAVE_RECORD`.

The supplied HOD table definition is saved in `Table/hod.sql` as a reference;
the approval installer does not recreate or modify it. Inactive and null-status
HOD rows are ignored. No active HOD means that stage is omitted for new
requests. Multiple active assignments in the same department/company stop
submission for review. An active assignment to an inactive employee is an
error, rather than a reason to bypass that approval. If HOD becomes inactive
after submission, its saved pending step requires administrator review and
cannot be approved by the former assignee.

Every numeric person ID above is `EMPLOYEES.ID`, not the displayed employee
code `EMPLOYEES.EMP_ID`. RP and HOD must be active in the applicant's company.
Company roles must resolve to one active employee each; explicit assignments
allow a shared MD/HRD employee to serve multiple companies. Missing required
roles, duplicate assignments, inactive people, and invalid RP company mappings
stop submission instead of bypassing approvals.

The route is saved when the default form's Create/Save (`CREATE`/`SAVE`),
Apply (`APPLY`), or Forward (`FORWARD`) is pressed. Save submits an existing
draft too; it is not a draft-only button in this integration. A pending assignment is checked
again against its current source when acting. If roles or the applicant's
company change mid-route, administrator review/reassignment is required.

## Install on the existing HRMS database

Pause leave-page writes while installing and wiring the page. Run as HRMS in
SQL*Plus/SQLcl, with no unrelated uncommitted work:

```sql
@D:\HRPAYROLL\Leave\INSTALL_COMPANY_APPROVAL.sql
@D:\HRPAYROLL\Leave\CHECK_COMPANY_APPROVAL.sql
```

The supplied `REQUEST_STATUS` column already exists, so **do not rerun
`UPGRADE_REQUEST_STATUS.sql`** on these tables. The approval installer:

1. Checks required source columns and duplicate history IDs.
2. Installs sequence-backed ID triggers for both request and history.
3. Adds a primary key on history ID if absent, reinstalls stage synchronization,
   and installs the ordered workflow package and views.
4. Refreshes `V_EMP_LEAVE_TOTAL` to sum all approved requests in a start month.
5. Removes the old insert trigger that created RP/HOD history on draft saves.

Oracle DDL commits. Existing applications and audit history are preserved;
old pending routes are not silently converted. Review them using the diagnostic
script before any controlled migration. Completed history remains readable.
Existing sequences are retained, never reset. Do not manually allocate positive
IDs beyond their sequence values without a DBA resynchronizing the sequence.

For new databases, the Leave and Table DDL now refer to the same sequence
trigger scripts. Install the approval package after creating the base tables
and source views. Do not run base table DROP/CREATE exports against existing
business data. HRMS needs direct source grants if RP/HOD/role views are owned
by another schema; synonyms alone do not supply PL/SQL compilation privileges.

## APEX application items

Use the application's existing global items with these meanings:

| Item | Meaning | Use in this workflow |
| --- | --- | --- |
| `G_EMP_ID` | Character employee code / IPI code | Display or code lookup only |
| `USER_ID` | Numeric `EMPLOYEES.ID` of the authenticated employee | Applicant ownership, approval actor, inbox filter |
| `G_COM_ID` | Selected authorized company ID | Company scope |

Populate these server-side through the existing login-to-employee mapping.
Do not convert `G_EMP_ID` to a number or compare it with employee/approver IDs.
Never derive the actor from `P420_EMPID` or `P422_APPROVER_ID`. Protect the
application items against browser assignment and authorize company switching
server-side. Retain page/process authorization.

`LEAVE_REQUEST.EMPID`, `LEAVE_APP_HISTORY.APPROVER_ID`, and `p_actor_id` use
numeric `EMPLOYEES.ID`. For a new own-leave request, default `P420_EMPID` to
`:USER_ID` server-side; if it has an LOV, its return value must be
`EMPLOYEES.ID`. The label can display the character employee/IPI code.

The package is intended for trusted APEX server processes. Do not grant its
actor-parameter API to untrusted database users. The APEX snippets recheck the
stored request and assignment, so hidden approver/page item values do not
authorize an action.

## Page 420: default LEAVE_REQUEST form and report

For a step-by-step Bengali Page Designer guide, see
[PAGE_420_SETUP_BN.md](PAGE_420_SETUP_BN.md). The default table form saves only
`LEAVE_REQUEST`; it needs a separate Execute Code process after form DML to
create the route in `LEAVE_APP_HISTORY`.

1. Replace the old approval-history insert process. Create and Save both save
   and submit the complete route in the same APEX submit. Forward can also
   submit an existing draft.
2. Keep form DML for `CREATE`, `APPLY`, `SAVE`, `FORWARD`. Return the generated primary
   key to `P420_LEAVE_ID`. New rows use the existing defaults `P`/`D`.
   Make both status items query-only and omit them from form DML; the package
   controls workflow status. Make the applicant display-only after loading.
3. Keep the default Submit buttons `CREATE` (Database Action = SQL INSERT
   action, visible when the key is null) and `SAVE` (SQL UPDATE action,
   visible when the key is not null), with normal validations enabled.
   The labels may say Apply/Submit. No button rename is required. A custom
   `APPLY`/`FORWARD` button must also have the correct INSERT or UPDATE
   Database Action when it needs to save form changes. Button **Name**
   determines the request; changing the label does not change the request.
   On form DML set **Return Primary Key(s) after Insert = Yes**. Map the
   form's primary key `LEAVE_ID` to `P420_LEAVE_ID`; do not use MAX(LEAVE_ID).
4. Add `P_420 validate draft.sql` **before form DML**, only for `CREATE`, `APPLY`,
   `SAVE`, `FORWARD`. The file contains this guard:

```sql
DECLARE
    l_count NUMBER;
    l_empid NUMBER;
    l_stage VARCHAR2(1);
    l_status VARCHAR2(10);
BEGIN
    SELECT COUNT(*) INTO l_count FROM employees
     WHERE id = :USER_ID AND status = 1 AND com_id = :G_COM_ID
       AND id = :P420_EMPID;
    IF l_count <> 1 THEN
        RAISE_APPLICATION_ERROR(-20827, 'Applicant must be the logged-in employee in this company.');
    END IF;
    IF :P420_LEAVE_ID IS NOT NULL THEN
        SELECT empid, request_status, leave_status
          INTO l_empid, l_stage, l_status FROM leave_request
         WHERE leave_id = :P420_LEAVE_ID FOR UPDATE;
        IF l_empid <> TO_NUMBER(:USER_ID) OR NVL(l_stage, '#') <> 'D'
           OR NVL(l_status, '#') NOT IN ('P', 'D') THEN
            RAISE_APPLICATION_ERROR(-20828, 'Only your own draft request can be edited.');
        END IF;
    END IF;
END;
```

5. After form DML and before any success branch, run `P_420 insert data.sql`.
   Clear **When Button Pressed** (do not leave it set to FORWARD). Set its
   server-side condition type to **PL/SQL Expression** with:
   `apex_application.g_request IN ('CREATE', 'SAVE', 'APPLY', 'FORWARD')`.
   It validates the saved applicant/company, builds the route,
   marks the first included step `PENDING` and all later steps `WAITING`,
   then changes the request to `F`/`F`. Do not swallow errors or commit between
   form DML and this process. A missing role must fail the submit visibly.

### Application saved but missing from the approval inbox

The previous Page 420 process ran only for `FORWARD`. Pressing Apply/CREATE or
SAVE therefore left `P`/`D` with no history, which the approval inbox correctly
excluded. Install the Page 420 process settings above; replacing only the
PL/SQL body while keeping **When Button Pressed = FORWARD** will not fix it.
No database package change is needed for this page integration fix.

For an already saved draft, reopen it as its applicant and press Save, Apply, or
Forward once. Do not update its statuses directly: that does not build a route.
Existing forwarded/approved applications must not be resubmitted.

Verify a specific application after Apply, using its actual ID:

```sql
SELECT lr.leave_id, lr.empid, lr.leave_status, lr.request_status,
       h.approver_level, h.approver_id, h.approval_status, h.com_id
  FROM leave_request lr
  LEFT JOIN v_leave_approval_steps h ON h.leave_id = lr.leave_id
 WHERE lr.leave_id = :leave_id
 ORDER BY h.step_no;
```

Expected: request `F`/`F`, one first approver `PENDING`, and later steps
`WAITING`. Sign in as that first approver with the same authorized company;
the Page 422 inbox below should show the request. Saving an existing draft
must produce the same route. Reapplying a forwarded request must fail.

This employee form handles the logged-in employee's own applications. HR entry
on behalf of another employee needs its own explicitly authorized server process.

## Page 422: approvals and HRD recording

Use `P422_LEAVE_ID` as a protected selected request ID. Add optional
`P422_COMMENTS` with a 300-byte limit. Approver ID/level/history ID are
display-only. `P422_APPROVAL_STATUS` is an editable action select list with
return values `APPROVE` and `REJECT`; Source = Null, no database column mapping
or stored-status default. Stored history statuses remain `PENDING`, `APPROVED`,
`REJECTED`, etc., and are updated only by the package. Keep report escaping
enabled for names and remarks. For exact settings, see
[PAGE_422_SETUP_BN.md](PAGE_422_SETUP_BN.md).

Create a Submit button named `SUBMIT_ACTION` for the selected approval action,
and a separate `RECORD` button for HRD. Database Action = None for both. Replace the old
"Update the next" process with `P_422 Update the next.sql`. Run it After Submit
with a PL/SQL Expression server-side condition:
`apex_application.g_request IN ('SUBMIT_ACTION', 'RECORD')`. Exclude both
from normal form DML, and remove other direct status/history update processes.
Use one action process so each submit acts once. Let errors reach APEX; do not
use `WHEN OTHERS THEN NULL` or commit before an action succeeds.

Approval inbox query (RP, HOD, Plant Head, MD):

```sql
SELECT a.* FROM v_leave_approval a
 WHERE a.com_id = :G_COM_ID AND a.approver_id = :USER_ID
   AND a.approval_status = 'PENDING'
   AND a.approver_level IN ('RP', 'HOD', 'PLANT_HEAD', 'MANAGING_DIRECTOR')
   AND a.leave_status = 'F' AND a.request_status = 'F'
   AND EXISTS (SELECT 1 FROM employees e WHERE e.id = a.empid AND e.com_id = :G_COM_ID)
 ORDER BY a.leave_id, a.step_no;
```

Use this query for the SUBMIT_ACTION button and action select list server-side row condition too,
with `a.leave_id = :P422_LEAVE_ID` and no ORDER BY. The package locks the request,
checks the actor/current assignment and step order again, and allows only
the single current step to act. Intermediate approval stays `F`/`F`. MD's
approval changes it to `A`/`A` and activates HRD. Rejection at any approval
step sets `R`/`F` and cancels every later step.

HRD inbox and RECORD button condition:

```sql
SELECT a.* FROM v_leave_approval a
 WHERE a.com_id = :G_COM_ID AND a.approver_id = :USER_ID
   AND a.approver_level = 'LEAVE_RECORD' AND a.approval_status = 'PENDING'
   AND a.leave_status = 'A' AND a.request_status = 'A'
   AND EXISTS (SELECT 1 FROM employees e WHERE e.id = a.empid AND e.com_id = :G_COM_ID)
 ORDER BY a.leave_id;
```

For the button condition add the selected leave ID and omit ORDER BY. Only
show RECORD in this inbox. Recording changes HRD history to `RECORDED` with
date, employee, and remarks; the request remains approved. For HRD's completed
register use the same query with `approval_status = 'RECORDED'`.

`LEAVE_RECORD` is a role/history step, not a new table. This workflow does not
post `LEAVE_CONSUMPTION` or deduct leave balances. Keep the existing authorized
posting process; do not count approved requests and posted consumption twice.
`V_EMP_LEAVE_TOTAL` is a request report, attributes each request to its start
month, and preserves the existing SL+CL+EL total and separate EC columns.
Use the allocation/consumption views and `V_EL_BALANCE` for actual balances.

## Verification

Run `CHECK_COMPANY_APPROVAL.sql` for read-only source, role, compilation, and
pending-route checks. Run `TEST_COMPANY_APPROVAL.sql` only in a test HRMS database.
Supply existing employees for the four RP/HOD combinations; use distinct
RP/HOD/Plant Head/MD people to exercise each stage. The script also tests the
Plant Head's and a HOD's own applications. Enter 0 only for unavailable
fixtures; skipped cases are explicitly reported as unverified.

Tests create temporary leave applications, verify ordered activation, missing
RP/HOD routes, intermediate/final states, actor/company restrictions, repeat
submits, recording after MD only, and rejection at each approval stage. All
request/history changes and temporary RP/HOD assignment changes roll back; sequence
values are consumed. The HOD tests verify that inactive assignments are omitted
from new routes and that deactivating an assignment prevents its saved pending
approval from advancing. Shared-role tests reuse the FULL fixture with temporary
RP/HOD mappings for RP=HOD, HOD=Plant Head, RP=Plant Head, and all three equal.
They check the exact combined route, one completed approval per employee,
activation of the next different approver, final MD approval, HRD recording,
and rejection of manually duplicated approval assignments. No live
Oracle compilation or execution has been performed from this workspace.
Offline query checks executed the summary and role-order view SELECTs in
SQLite with a `TO_CHAR` compatibility function. Those checks passed aggregation,
status exclusion, employee/month isolation, and role order; they do not verify
Oracle syntax or the PL/SQL package. All 29 local SQL include references and
changed-file whitespace checks passed.
The HOD selection query was also checked offline against active, inactive,
null-status, duplicate active, and other-company/department assignments.
Offline checks of the actual history-validation SELECT accept all four shared
RP/HOD/Plant Head combinations, permit a separate HRD recording role, and
detect a repeated approver under different approval role names.
