# EL history reconciliation from LEAVE_DATA

`HRMS.LEAVE_DATA` is read-only legacy reference data. Installation, import and
tests do not alter its structure or rows. Source copies and import keys live in
`HR_EL_LEGACY_REF`; balance adjustments and debits live in `HR_EL_LEGACY_EVENT`.

`Opening` is a carried balance at the start of `DATE_FROM`, before transactions
on that day. It is not an annual EL credit. `Leave` and `Encashment` each reduce
EL by `DURATION`. The supplied YEAR assigns the transaction to its start year;
cross-year durations are not split or replaced with date arithmetic.

`PKG_EL_HISTORY.RECONCILE` generates yearly earned EL from each employee's
JOIN_DATE through the reconciliation date, using the existing monthly EL
milestones, numeric employee types, CONF_DATE and age rules. It then processes
ERP snapshots and debits chronologically. A snapshot produces a signed
adjustment so the balance immediately before that day's transactions equals
the recorded Opening. Later snapshots can correct earlier missing history.
Both positive and negative adjustments are retained for audit.
An Opening snapshot may itself be negative; Leave/Encashment durations must
be nonnegative.

## Installation and preview

The repository does not contain LEAVE_DATA's DDL or a live connection. The
installer expects the existing HRMS.LEAVE_DATA table and its supplied columns:
EMPCODE, LEAVE_TYPE, DATE_FROM, DATE_TO, DURATION, YEAR, LEAVEADTYPE, EMPID.
Do not insert the example records again if they already exist.

1. Install the existing `UPGRADE_MONTHLY_ALLOCATION.sql` prerequisites.
2. Run `INSTALL_EL_HISTORY.sql` as a SQL*Plus/SQLcl script connected as HRMS.
   DDL commits. It creates separate reference, ledger and reporting objects.
   It does not change LEAVE_DATA or perform reconciliation automatically.
3. Run `BEGIN HRMS.pkg_el_history.stage_reference; END;` followed by `/`
   on its own line to copy EL rows from LEAVE_DATA into HR_EL_LEGACY_REF.
   Run `DIAGNOSE_EL_HISTORY.sql` and resolve unmatched employees, invalid dates,
   duplicate Opening snapshots, and overlapping native consumption.
4. Run reconciliation, inspect its results, then commit or roll back.

```sql
BEGIN
    -- Refreshes the reference copy, then processes all employees.
    -- Inactive employees need SEP_DATE.
    HRMS.pkg_el_history.reconcile(p_as_of_date => TRUNC(SYSDATE));
END;
/

SELECT * FROM HRMS.v_el_year_balance ORDER BY empcode, leave_year;
SELECT * FROM HRMS.v_el_balance ORDER BY empcode;
SELECT * FROM HRMS.hr_el_legacy_event
 WHERE active_flag = 'Y' ORDER BY empid, event_date, source_id;

-- COMMIT;   -- Save the reviewed allocation/history reconciliation.
-- ROLLBACK; -- Undo its business changes.
```

For one employee, pass `p_empid => :current_employee_primary_key`. This is
EMPLOYEES.ID, not necessarily the old ERP EMPID. A failed call rolls back all
of its changes to an internal savepoint, retaining unrelated caller work.
Reconciliation locks reference copy, allocation, import ledger and consumption tables
until caller commit/rollback; use a maintenance window for large histories.
It reads LEAVE_DATA with a single consistent SELECT during reference refresh.
Use `p_refresh_reference => 0` only to reconcile a previously staged reference
copy, including test fixtures. Neither staging nor reconciliation commits.

## Employee mapping and records

An ERP row may match EMPLOYEES.EMP_ID through EMPCODE, EMPLOYEES.ID through
EMPID, or the separate EMPLOYEES.EMPID legacy identifier through EMPID. All
matching identifiers must resolve to one unique current primary-key ID.
Conflicting or missing matches stop the import; no ERP numeric ID is blindly
inserted into a foreign-key column.

Employees need JOIN_DATE and a valid numeric T_EMP_TYP reference. Inactive
employees need SEP_DATE; no EL is generated after that date. Historical rate
calculations use the current type and recorded CONF_DATE, as the existing
entitlement function does. Contract/type changes beyond those records cannot
be reconstructed from LEAVE_DATA. Missing DOB leaves the age rule unverifiable;
complete employee data before relying on that exclusion.

The eight raw source fields form a SHA-256 fingerprint in HR_EL_LEGACY_REF.
An occurrence number preserves repeated identical source rows. Re-reading
identical data reuses the same reference IDs even if legacy rows were reloaded;
no added source column or physical ROWID is needed. Changed rows get new keys,
and superseded or removed copies and ledger entries become inactive audit
records. Reruns recalculate the employee's entire history and subsequent
snapshot adjustments. If an ERP row moves between
employees, run reconciliation for all employees so both balances refresh.
Reconcile forward in time: a cutoff before existing earned allocations is
rejected instead of mixing future allocations with older snapshots.

`LEAVE_ALLOCATION.ALLOCATED_DAYS` continues to store only gross EL earned in
that year. Opening corrections, legacy Leave and legacy Encashment remain in
HR_EL_LEGACY_EVENT. Existing LEAVE_CONSUMPTION rows with EL or EC (EL encashment) are preserved and deducted
separately. The import does not create approval requests, payroll encashment
payments, or duplicate native consumption rows.

Exact native consumption matches to ERP dates/duration stop the import.
Previously imported records with different dates or yearly aggregation cannot
be recognized automatically; review the native consumption overlap report.
Do not count the same leave in both sources. Duplicate ERP business rows are
reported for review rather than silently collapsed.

## Carry-forward balances and APEX

V_EL_YEAR_BALANCE shows prior-year opening balance, earned days, signed Opening
adjustment, legacy leave, legacy encashment, native leave/encashment and closing
balance for each service year. Closing EL carries forward to the next year.
Negative balances remain visible, exposing missing/corrected history.
V_EL_BALANCE gives each employee's latest reconciled balance and its cutoff.

Use this view for the APEX EL balance item/report instead of summing only
LEAVE_ALLOCATION minus LEAVE_CONSUMPTION:

```sql
SELECT el_balance
  FROM HRMS.v_el_balance
 WHERE empid = :PXX_EMPLOYEE_ID;
```

Replace the item name with the page's actual EMPLOYEES.ID item. The repository
does not contain that page export, so the query must be wired in the live page.
After migration, the normal P_EL_LEAVE_ALLOCATION monthly/daily run updates
earned EL and preserves imported snapshots/debits. Reconcile again after
editing source data, JOIN_DATE, CONF_DATE, DOB, type or employment end date.
Age 60 clears the year's earned allocation per the established policy; a
carried balance from earlier years remains represented by the balance ledger.

## Examples and testing

For the 95-day Opening and 42-day Leave on April 8, the balance immediately
after the Leave is 53. EL earned after the snapshot is then added. A full-year
confirmed employee's February balance grows by the established day milestones.

For IPI-000808, assuming confirmed status throughout 2010-2015 and full-year
service, the supplied snapshots yield these year-end balances:

| Year | Carried snapshot at January 1 | Earned | Leave/encashment | Closing |
| ---: | ---: | ---: | ---: | ---: |
| 2010 | 30 | 30 | 0 | 60 |
| 2011 | 30 | 30 | 60 | 0 |
| 2012 | 30 | 30 | 0 | 60 |
| 2013 | 30 | 30 | 53 | 7 |
| 2014 | 30 | 30 | 1 | 59 |
| 2015 | 30 | 30 | 60 | 0 |

Each January snapshot resets the carried balance to its recorded value. The
six Opening values must not be summed as six additional annual entitlements.
Actual outputs also depend on employee dates, status, age and native consumption.

Run `TEST_EL_REFERENCE.sql` manually in a test HRMS schema to check source
fingerprints, copied occurrence counts and stable IDs across repeated reads.
It reads LEAVE_DATA without changing it and rolls back reference-copy changes.

Run `TEST_EL_HISTORY.sql` manually in a test HRMS schema. It checks the supplied
transaction pattern, all-year allocation, repeated imports, changed/removed
reference copies, later snapshot resets, overlap rejection and rollback on error.
It inserts fixtures only into HR_EL_LEGACY_REF and target tables, then rolls
back its temporary employee and business rows. Oracle identity sequences may
have gaps after test rollback. No database execution has been verified while
the local Oracle service is stopped.
