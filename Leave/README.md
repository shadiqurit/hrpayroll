# Leave allocation, request stages and deletion

## Monthly leave allocation

Install `UPGRADE_MONTHLY_ALLOCATION.sql` as a SQL*Plus/SQLcl script connected
as HRMS. It adds the employee/type/year unique constraint, supplies missing
global SL/CL/EL/RL leave codes, installs `FN_LEAVE_ENTITLEMENT.sql` and
`P_LEAVE_ALLOCATION.sql`, checks compilation, and runs the entitlement tests.
It does not recalculate existing employee allocations. Existing duplicate
allocation rows must be reviewed first; the installer stops without deleting
them. Oracle DDL commits, so finish unrelated transactions before installing.

| Employee category | EL per full year | EL per completed month |
| --- | ---: | ---: |
| Confirmed, under 60 | 30 | 2.5 |
| Contractual, probation, other employees under 60 | 24 | 2 |
| Any employee aged 60+ | 0 | 0 |

All active employees receive SL 14 and CL 10 per full year. RL has a full-year
quota of 15. The procedure supports either RL for contractual/60+ employees
(`p_rl_all_employees => 0`, the default) or RL for everyone
(`p_rl_all_employees => 1`). Employee types reference numeric `T_EMP_TYP.ID`
values from the supplied `Leave/emp_type_Data.sql`:

| ID | ETYPE in the supplied data | EL per full year under 60 | RL by default |
| ---: | --- | ---: | --- |
| 0 | Reguler | 24 | Age 60+ only |
| 1 | Probation | 24 | Age 60+ only |
| 2 | Confirmed | 30 | Age 60+ only |
| 3 | Contractual | 24 | Yes |
| 4 | Casual | 24 | Age 60+ only |

`P_LEAVE_ALLOCATION` joins `EMPLOYEES.EMP_TYPE` to `T_EMP_TYP.ID` and passes
the numeric ID to `FN_LEAVE_ENTITLEMENT`. The supplied EMPLOYEES DDL uses
VARCHAR2 for EMP_TYPE, so numeric IDs stored as text are supported without
changing the employee column. Text labels such as `CONTRACTUAL` are not valid
references. Missing/invalid types for active employees stop allocation before
any merge instead of silently skipping employees. Other valid IDs in T_EMP_TYP
use EL 24/year and RL only at age 60+, unless RL for all is enabled.

T_EMP_TYP must already exist and contain the reference data before installing
the allocation objects. The supplied data file also contains CREATE TABLE
statements; do not run it against an existing T_EMP_TYP table.

Allocation is cumulative through the inclusive `p_as_of_date`, defaulting to
SYSDATE. It counts completed service months from the later of JOIN_DATE and
January 1 of `p_year`, capped at the selected year's December 31. Partial
months earn nothing. Month ends use Oracle ADD_MONTHS anniversaries. SL, CL
and RL are prorated using the same completed months and stored to two decimal
places. Six completed months give SL 7, CL 5, confirmed EL 15, other eligible
EL 12, and eligible RL 7.5. Carry-forward between years is not included.

`T_EMP_TYP.ID = 2` earns 2.5 EL per month from the confirmation
date. Months ending before confirmation earn 2. For a confirmation partway
through a month, the month uses the status on its final service day. A confirmed
employee with no CONF_DATE uses 2.5 for all completed months. Historical runs
use the current employee type and recorded CONF_DATE; employee type history is
not reconstructed. A missing JOIN_DATE gives zero allocation. A missing DOB
does not exclude EL; complete DOB records before relying on the age rule.

On or after the 60th birthday, the selected year's EL allocation becomes zero,
including EL earned earlier in that year, as requested. SL and CL continue.
Historical years are evaluated at their own year end rather than today's age.

Example using the default RL policy (contractual and age 60+):

```sql
BEGIN
    HRMS.p_leave_allocation(
        p_year => 2026,
        p_as_of_date => DATE '2026-06-30'
    );
END;
/

SELECT e.emp_id, lt.short_code, la.allocated_days, la.allocation_year
  FROM HRMS.leave_allocation la
  JOIN HRMS.employees e ON e.id = la.empid
  JOIN HRMS.leave_types lt ON lt.lt_id = la.leave_type_id
 WHERE la.allocation_year = 2026
 ORDER BY e.emp_id, lt.short_code;

-- COMMIT after reviewing, or ROLLBACK to undo.
```

For RL for everyone, pass `p_rl_all_employees => 1`. Default restricted RL
automatically identifies contractual employees using ID 3; no contractual
type parameter is needed. Use the same RL policy argument for every run.

Run allocation at each month end, or daily if the age-60 reset should happen
on birthdays. Rerunning replaces the yearly cumulative amount rather than
adding another installment. Calling with an earlier date deliberately
recalculates a smaller entitlement; it is not a posting history.
`P_LEAVE_ALLOCATION` no longer commits internally: APEX/the calling job must
commit successful work. Only `STATUS = 1` employees and active leave codes
participate. Existing consumption and requests are not changed. Allocated
days are gross entitlement, so subtract consumption separately for balances.
If clearing EL leaves consumed EL greater than allocation, retain the
consumption record and show the resulting balance for review.

Company-specific active codes take precedence over global (`COM_ID IS NULL`)
codes. Duplicate effective codes cause an error before the merge. Allocation
uses short codes rather than fixed LT_ID values. The policy function controls
quotas; the existing LEAVE_TYPES.ANNUAL_QUOTA values are not used for these four
codes. If changing an existing leave code's company scope, review its existing
allocations first; historical rows under another LT_ID are not migrated.

Run `TEST_LEAVE_ENTITLEMENT.sql` again for calculation checks; it changes no
business rows. For a database check, rerun the same allocation call in a
transaction and verify the employee/type/year row count and allocated amounts
do not increase. Roll back after verification if this is only a test.

## Leave request stages

`LEAVE_REQUEST.REQUEST_STATUS` is the new stage column:

| Action | REQUEST_STATUS | Meaning |
| --- | --- | --- |
| Save a new request | `D` | Draft |
| Forward | `F` | Forwarded |
| Final approval | `A` | Final |

`LEAVE_STATUS` keeps its existing approval codes. The new column defaults to
`D`. `TRG_LEAVE_REQUEST_STATUS.sql` synchronizes the stage on insert and whenever
`LEAVE_STATUS` changes: `P`/`D` sets draft, `F` sets forwarded, and `A` sets
final. Saving an unchanged status preserves the current stage. Rejected requests
(`R`) keep the forwarded stage and retain their rejection in `LEAVE_STATUS`.

## Installation

For an existing HRMS database, run `UPGRADE_REQUEST_STATUS.sql` as a SQL*Plus or
SQLcl script. It adds the column, populates existing rows, installs the stage
and delete triggers, reinstalls the delete procedure, and refreshes both leave views. Run
this upgrade once. Oracle DDL commits; finish unrelated transactions first.
Existing pending/draft rows become `D`, approved rows become `A`, and all other
rows become `F` so they are outside the draft stage.

For a new database, the table definitions in `Leave/LEAVE_REQUEST.sql` and
`Table/leave_request.sql` already include the column and check constraint.
After creating the tables, install `TRG_LEAVE_REQUEST_STATUS.sql`,
`TRG_LEAVE_REQUEST_DELETE.sql`,
`DELETE_LEAVE_REQUEST.sql`, and the two leave views. Do not run the upgrade
against a table that already has the new column.

Both `V_LEAVE_REPORT` and `V_LEAVE_APPROVAL` expose `REQUEST_STATUS` and
`REQUEST_STATUS_TEXT` (`Draft`, `Forwarded`, `Final`).

## APEX save, forward, and final approval

For a new request, omit `REQUEST_STATUS` from the insert to use its default
`D`. Do not reset it to `D` every time an existing request is saved. Display it
as a read-only item if needed.

In the existing authorized Forward process, set `LEAVE_STATUS = 'F'` for the
selected `LEAVE_ID`. In the final approval process, set `LEAVE_STATUS = 'A'`.
The database trigger automatically sets `REQUEST_STATUS` to `F` or `A` in the
same transaction. Keep the existing approver checks and history writes in
those processes. The repository contains no APEX save/approval page export;
these processes must be wired in the actual page.

## Delete a leave request

Run `DELETE_LEAVE_REQUEST.sql` in the HRMS schema to install the procedure.
It deletes a single request by `LEAVE_ID` only when `LEAVE_REQUEST.LEAVE_STATUS`
is pending (`P`) or draft (`D`) **and** `REQUEST_STATUS = 'D'`. Forwarded, final,
rejected, and null statuses are rejected.

The procedure locks the request, deletes every related `LEAVE_APP_HISTORY` row,
then deletes the `LEAVE_REQUEST` row. Approval history status does not determine
eligibility; the request status does. If deletion fails, both deletes are rolled
back. The caller controls the transaction; the procedure does not commit.

## Oracle APEX delete button

Use a Submit button named `DELETE_LEAVE`. Turn off Execute Validations for this
button so required entry fields do not prevent deletion. Create an After Submit
PL/SQL process with **When Button Pressed = DELETE_LEAVE**:

```sql
BEGIN
    HRMS.delete_leave_request(p_leave_id => :PXX_LEAVE_ID);
END;
```

Replace `PXX_LEAVE_ID` with the actual page item holding the request ID. Keep
the page's authorization rules on the button and process. Exclude this button
from the normal form DML process so the procedure handles both tables. Branch
to the leave list only on success and clear the form page cache.

Optional button server-side condition (SQL query returning rows):

```sql
SELECT 1
  FROM HRMS.leave_request
 WHERE leave_id = :PXX_LEAVE_ID
   AND UPPER(TRIM(leave_status)) IN ('P', 'D')
   AND request_status = 'D'
```

The procedure validates both stored statuses again on submit. Use the raw table
codes for the condition, since `V_LEAVE_REPORT.LEAVE_STATUS` returns labels.

For a manual call, use a specific leave ID and commit only after checking the
result:

```sql
BEGIN
    HRMS.delete_leave_request(p_leave_id => :leave_id);
END;
/

SELECT * FROM HRMS.leave_app_history WHERE leave_id = :leave_id;
SELECT * FROM HRMS.leave_request WHERE leave_id = :leave_id;

-- COMMIT;   -- Save the deletion.
-- ROLLBACK; -- Undo the deletion instead.
```

## ORA-02292: child record found

This error means a parent row still has child rows when it is deleted. The
supplied schema defines `LEAVE_APP_HISTORY.LEAVE_ID` as a foreign key to
`LEAVE_REQUEST.LEAVE_ID`. System-generated constraint names vary by database;
run `DIAGNOSE_LEAVE_DELETE.sql` to identify `HRMS.SYS_C0020159` in your database
and list any other tables referencing the request.

If `REQUEST_STATUS` is already installed, run `FIX_LEAVE_DELETE.sql` as a
SQL*Plus or SQLcl script. Do not rerun the column upgrade. The fix installs a
`BEFORE DELETE` trigger on `LEAVE_REQUEST`: it rejects non-draft requests and
deletes related approval history before the parent row is deleted. This also
covers APEX Automatic Row Processing and direct SQL deletes. The existing
delete procedure remains valid; its prior history delete makes the trigger's
history delete a harmless no-op. All work remains in the caller's transaction,
and a failed parent delete rolls back the trigger's history deletion.

The fix installer creates objects only; it does not delete existing requests.
Keep the foreign key enabled. If the diagnostic query identifies a different
child table, that dependency needs to be handled explicitly before deletion;
this fix removes only `LEAVE_APP_HISTORY` rows.
