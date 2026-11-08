# Attendance procedure review (original input)

Subsequent machine-data changes and remaining integration work are documented in
`README.md`. The findings below describe the procedures before those changes.

Reviewed on 2026-11-04: all three procedures in this folder, the supplied
`ATTENDANCE_DETAILS` / `ATT_MCDATA` definitions, the repository's leave request
and approval implementation, and the `V_ATT_GEN`, `V_ATT_GEN1`, `V_ATT_GEN2`
definitions supplied in chat. This is a source review; no procedure has been
changed or executed against Oracle.

## Findings

1. **Historical office schedules are missing at the source.** The supplied
   `V_ATT_GEN1` seeds its date series with `TRUNC(SYSDATE, 'MM')` and stops at
   today. `V_ATT_GEN` uses this view for companies other than 3. Consequently,
   passing last month's dates to `P_ATT_SCHEDULE` still produces no source
   schedule rows for those office employees. Its schedule MERGE and punch
   rebuild therefore leave existing history untouched. Company 3 instead uses
   roster dates from `V_ATT_GEN2`; the supplied definition does not impose the
   same current-month restriction.

2. **All three default to yesterday through today.** See the date declarations
   in `P_ATT_SCHEDULE.sql:13`, `P_ATT_UPDATE_DETAILS.sql:13`, and
   `P_ATT_CONT_SHIFT_FAST.sql:18`. None of these procedures detects changes to
   old machine punches, approvals, or manual records. Calling them without
   dates cannot repair older changes. `ATT_MCDATA` has no modification timestamp
   in the supplied DDL, so a timestamp-based incremental refresh cannot detect
   all edits or deletions using that table alone.

3. **Leave and short leave have no explicit calculation stage.**
   `P_ATT_UPDATE_DETAILS.sql:331` calculates status using holidays and punch
   presence only, returning H/W/G/P/A. It does not read approved leave, short
   leave, or manual-attendance sources. It can replace an existing leave status
   with absence/presence, and it has no short-leave adjustment to lateness or
   early departure. The supplied schedule views do not supply these adjustments
   either. The repository's current leave workflow uses both
   `LEAVE_STATUS = 'A'` and `REQUEST_STATUS = 'A'` for final-approved requests;
   attendance priority relative to punches still needs confirmation.

4. **Manual punch changes have no protection or source replay.**
   `P_ATT_SCHEDULE.sql:430` replaces stored IN/OUT values with selected machine
   punches, including NULL when no punch qualifies. `ATTENDANCE_DETAILS` has no
   supplied manual-override flag or separate original/adjusted punch columns.
   Preserving remarks does not preserve manual punch values. A repeatable
   rebuild must read authoritative manual-attendance records and reapply their
   approved values after machine assignment. Keeping old IN/OUT values with
   `NVL` would instead preserve stale machine and previously derived values.

5. **Changing a working roster day to a holiday leaves stale punches.**
   `V_ATT_GEN2` returns NULL scheduled times for shift IDs 0 and 9.
   `P_ATT_SCHEDULE.sql:164` excludes schedules with NULL boundaries, and its
   punch rebuild uses an inner join to those schedules at line 404. The first
   MERGE can clear the scheduled times, while the second never clears the old
   actual punches on that same row. Rows that disappear from the schedule view
   entirely are also left untouched; their intended retention/reset policy
   needs to be explicit.

6. **The missing-middle-punch bridge runs after its matching conditions have
   been removed.** In `P_ATT_UPDATE_DETAILS.sql`, the first MERGE fills a missing
   IN from OUT and a missing OUT from IN (lines 416-417). The subsequent bridge
   requires the previous OUT to be NULL and the next IN to be NULL (lines 566
   and 572). For the intended single-punch pair, that bridge cannot match after
   the first MERGE. Bridge continuous shifts before single-punch normalization
   and final calculations.

7. **Continuous-shift changes can leave calculated fields stale.**
   `P_ATT_CONT_SHIFT_FAST.sql:300` updates only IN/OUT. It does not recalculate
   duty hours, lateness, early departure, or status. Both attendance rows must
   also lie inside the requested range (lines 128-132), so rebuilding a single
   day misses a continuous pair crossing either edge. The procedure consumes
   stored punches, not `ATT_MCDATA`; it cannot independently remove a derived
   boundary when a supporting raw punch is edited/deleted. Rebuild machine
   values before deriving continuous boundaries, then calculate the metrics.

8. **Independent commits prevent one atomic rebuild.** Each procedure commits
   on success and rolls back the session transaction on failure. A later stage
   can fail after an earlier stage has committed. Calling these from an
   attendance/leave save operation would also commit or roll back the caller's
   other pending work. A coordinating entry point should own transaction
   completion, with internal stages participating in that transaction.

## Required correction

Use a single rebuild operation with an explicit affected date range and,
preferably, employee ID. Generate office schedules for that requested range
instead of relying on the current-month date series. Include neighbouring
shift dates needed for overnight and continuous pairs. Rebuild machine punches
from `ATT_MCDATA`, replay approved manual adjustments, derive continuous-shift
boundaries using the agreed manual-override priority, then calculate final
leave/short-leave/holiday/presence status and duty/late/early values. Commit the
complete operation together.

Machine reconstruction must include existing rows that lost valid schedule
boundaries so that obsolete machine/derived values can be reset. The existing
filter `ATT_MCDATA.STATUS = 1` should be retained until the meaning of its other
status values is confirmed; the procedure already rereads qualifying punches
without filtering `FLAG`.

For old edits, invoke the rebuild with the affected historical dates after the
source change. For date moves, employee moves, or deletes, refresh both the old
and new employee/date ranges as applicable. A daily two-day job alone cannot
discover arbitrary historical changes. Automatic tracking needs save-process
integration or a durable queue of affected employee/dates, including deletions;
it must cover both sides of a moved record and cancelled/deleted approvals.

## Information still needed before implementation

- Manual-attendance table/view DDL, employee/date keys, IN/OUT columns, approval
  values, and whether either boundary can be overridden independently.
- Short-leave table/view DDL, effective start/end times, approval/cancellation
  values, and its effect on lateness, early departure, and duty hours.
- Confirmation of full-day approved leave priority when machine punches exist,
  and the required attendance status/remarks for each leave type.
- Current scheduler job action and any APEX save/approval processes that invoke
  these procedures, to wire historical changes into the rebuild.

## Verification after correction

In a test HRMS schema, exercise a date in a previous month; add, edit, delete,
and deactivate a raw punch; approve, move, cancel, and delete leave and short
leave; add, edit, and cancel a manual boundary override; change a working roster
to holiday; and rebuild a night/continuous shift across a date-range edge.
Verify final IN/OUT, status, remarks, duty hours, late minutes, and early minutes.
Run the same rebuild twice and confirm identical results. Force a failure in a
later stage and verify earlier stages and unrelated caller changes were not
committed. No Oracle compilation or runtime checks were performed in this review.
