# Leave request stages and deletion

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
