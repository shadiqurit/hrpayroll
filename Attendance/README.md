# Historical attendance rebuild

The machine-data foundation is prepared here. The manual attendance approval,
pending/status reports, posting and machine-plus-manual rebuild are now in
[manualAttendance/README.md](manualAttendance/README.md). Full leave and short-leave
attendance integration still needs source definitions and priority rules.
**Do not use a machine-only rebuild to repair records containing manual
overrides or leave adjustments:** it reconstructs IN/OUT from machine data and
calculates H/W/G/P/A using the existing rules.

## Prepared changes

- `V_ATT_GEN1.sql` generates office dates from the earliest configured office
  schedule through tomorrow, instead of the current month only. It also carries
  overnight office OUT times into the next date. `V_ATT_GEN` and `V_ATT_GEN2`
  already in your database remain prerequisites.
- `P_ATT_SCHEDULE.sql` refreshes punches for NULL-boundary holiday schedules, so
  changing a working roster day to holiday clears old machine punches. Successful
  raw punches still mean `ATT_MCDATA.STATUS = 1`; `FLAG` does not restrict rereads.
- `P_ATT_UPDATE_DETAILS.sql` bridges missing boundaries before normalizing single
  punches and calculating final metrics. Office weekends now match the employee's
  branch as well as company. The missing-boundary rule is capped at a 24-hour span,
  consistently with the separate continuous-shift procedure.
- All three existing procedures accept a trailing `p_commit` parameter. Its
  default is 1 for existing callers; pass 0 to leave transaction completion to the
  caller. Failures roll back only work after the procedure's savepoint.
- `P_ATT_REBUILD_MACHINE.sql` coordinates schedule/raw-punch reconstruction,
  continuous shifts, and final calculations in that order. It includes one day
  before and after the requested inclusive range, so those neighbouring attendance
  rows are also refreshed. All internal calls use `p_commit => 0`.

## Installation and machine-only historical use

First install and validate in a test HRMS schema using SQL*Plus/SQLcl:

```sql
@Attendance/00_install_machine.sql
```

Oracle DDL commits. The installer replaces the view and procedures but does not
run a rebuild or change any scheduler job. `OFFICE_SCHEDULE`, `EMPLOYEES`,
`ATTENDANCE_DETAILS`, `ATT_MCDATA`, `T_HOLIDAY`, `S_ATTDATA`, and the supplied
`V_ATT_GEN` / `V_ATT_GEN2` must already exist. Do not run the table export scripts
as part of this installation.

Example for a machine-only historical interval:

```sql
BEGIN
    HRMS.p_att_rebuild_machine(
        p_from_date => DATE '2026-10-01',
        p_to_date   => DATE '2026-10-31',
        p_commit    => 0
    );
END;
/

-- Review the affected rows, including 30-Sep and 1-Nov.
-- Then issue COMMIT or ROLLBACK in the same session.
```

The wrapper refreshes all employees in that interval. It deliberately requires
dates; it does not silently scan all history. Passing `p_commit => 1` commits the
session's pending transaction, including any earlier work. Use 0 inside an APEX
save/approval operation and let that operation own its commit.

## Complete solution for leave, short leave and manual attendance

The final attendance refresh must reconstruct every output from its current
authoritative sources, in this order, with manual/leave priority agreed first:

1. Refresh schedules and qualifying raw punches from `ATT_MCDATA`.
2. Replay approved manual boundary corrections from their source records.
3. Apply continuous-shift rules subject to the agreed manual-override priority.
4. Apply approved full-day leave and short-leave intervals and calculate final
   status, duty, lateness and early departure. Single-punch fallback belongs in
   this final stage, after actual and approved boundaries are established.
5. Commit together with the initiating save/approval, or let a background worker
   commit an independent complete rebuild.

These manual/leave stages are **not implemented** by the machine-only wrapper.
For machine plus approved manual corrections, use `P_ATT_REBUILD_MANUAL` after
installing the manual approval module. Its explicit approved boundaries take
priority over machine/continuous derivation; omitted boundaries retain machine
values. Leave/short-leave replay remains separate. Please supply short-leave DDL,
approval/cancellation values, and the rule for full-day approved leave when machine punches exist.
The repository has `LEAVE_REQUEST` already, but the required attendance status
for each leave type and its priority still need confirmation.

After a historical source edit, refresh its actual affected dates, even if they
are outside the current month. For moved employee/date records, refresh both old
and new ranges. Deletion and cancellation must refresh the original range too.
The existing two-day daily calls cannot discover these changes automatically.
Wire the final combined refresh into the relevant save/approval/delete processes
or enqueue the affected employee/date keys in the same source transaction and
have a worker process that queue. Do not run a rebuild from a row trigger on a
table the rebuild queries. Scheduler/process definitions are needed to wire this
into the actual application.

## Validation and remaining limits

If a raw punch exists but the employee remains absent, run the read-only diagnostic
with the employee's numeric `EMPLOYEES.ID` and attendance date, for example:

```sql
@Attendance/DIAGNOSE_ATTENDANCE_DAY.sql 123 2026-09-02
```

Replace 123 with the actual employee database ID. The output shows current and
stored machine mappings, source schedule counts, deployed objects/parameters,
stored attendance, and each raw punch's status filter, assigned shift date,
boundary window and selection. Punches with NULL or non-1 `STATUS` are excluded
by the existing rule even if they exist in `ATT_MCDATA`. Their meaning must be
confirmed before changing that filter. Source schedule count zero can explain
why an old attendance row is left untouched. This diagnostic changes no data.

Run `node Attendance/tests/machine_rebuild.cjs` for local SQL regression checks.
These execute the actual view/source/update SQL using SQLite with Oracle date
helpers; they do not compile PL/SQL or establish Oracle transaction behaviour.
Run the installer and runtime tests in a test Oracle database before deployment.

Employee company, branch and machine mapping come from the current employee row,
as in the supplied views. Historical transfers need effective-dated assignments
to reconstruct earlier mappings correctly. The existing model selects one
schedule per employee/day; multiple separate shifts on the same day need a
different key. A schedule row removed entirely from the source view is retained
in attendance and needs an agreed reset/retention rule. Continuous derivation
still requires the two outer punches for each qualifying adjacent pair.

Generating the full historical office calendar can cost more than the old
current-month view. Measure on the real data; a later optimization can generate
only the requested date interval inside the schedule procedure.

`REVIEW.md` records findings against the original input, before these changes.
