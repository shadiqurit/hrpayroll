# Simple Annual Increment Module — Four Oracle APEX Pages

This is the single authoritative design guide for the increment module. The complete user workflow uses Pages 500–503.

## 1. Final page map

| Page | Name | Purpose |
|---:|---|---|
| 500 | Monthly Increment Workbench | Generate, record exceptions, apply READY increments to salary, optionally undo before final, then finalize |
| 501 | Increment Register | Read-only permanent register; final POSTED increments cannot be reverted |
| 502 | Increment Letter Center | Generate and manage letters for processed increments |
| 503 | Print Increment Letter | Clean printable/PDF letter page |

Page 500 contains the complete operational process; Pages 501–503 provide the register and letter output.

---

## 2. Monthly business rule

For a list date of `01-Aug-2026`:

```text
New consideration period : 01-Jul-2026 through 31-Jul-2026
Salary month             : 202608 / August 2026
```

For a list date of `01-Sep-2026`:

```text
New consideration period : 01-Aug-2026 through 31-Aug-2026
Salary month             : 202609 / September 2026
Carry forward            : unresolved temporary holds from earlier lists
```

Rules:

1. `LIST_DATE` must be the first day of a month.
2. New employees are selected only when `EMPLOYEES.NEXT_INCREMENT_DATE` falls in the full previous calendar month.
3. `READY` does not yet change salary. `Apply READY to Salary Structure` changes live salary and marks the occurrence `APPLIED`.
4. A temporary hold remains the same occurrence and appears in every following monthly list as carry-forward until released and processed.
5. Temporary hold never changes consideration or effective date.
6. Normal effective date is the confirmation anniversary after completion of the configured cycle, normally 12 months.
7. Only an approved punishment delay may set a revised payable effective date. The original effective date is never overwritten.
8. An `APPLIED` increment may be undone before final submit. A `POSTED` increment is final and cannot be reverted by this module.
9. After processing, the next consideration date advances from the original consideration anchor—not from processing date.
10. Step 25 is final. After posting step 25, `NEXT_INCREMENT_DATE` is cleared.

---

## 3. Simple decision model

### Decisions

| Decision | Meaning | Appears next month? | Effective date |
|---|---|---:|---|
| `READY` | Employee will receive increment | No after posting | Original confirmation-anchored date |
| `TEMP_HOLD` | Administrative/temporary hold | Yes, as carry-forward | Never changed |
| `PUNISHMENT_DELAY` | Increment payable later because of punishment | Yes until revised date/release | Original retained; revised date separately approved |
| `PUNISHMENT_FORFEIT` | Current occurrence stopped/forfeited | No after final decision | No salary update |

### Work statuses

| Status | Meaning |
|---|---|
| `DRAFT` | Reopened for correction or awaiting recalculation |
| `READY` | Eligible by default and ready for final posting unless HR records an exception |
| `APPLIED` | Live salary structure updated; may be undone only before final submit |
| `HOLD` | Temporary hold |
| `PUNISHMENT` | Punishment delay awaiting payable date/release |
| `FORFEITED` | Punishment forfeiture completed without salary update |
| `POSTED` | Final increment; locked and not reversible |
| `ERROR` | Apply/final validation error |
| `REVERSED` | Applied increment permanently withdrawn before final submit |

---

## 4. Page 500 — Monthly Increment Workbench

### 4.1 Purpose

This is the only operational page. HR generates the list, records exceptions, applies remaining READY increments to live salary, optionally undoes an APPLIED row before final submit, and then permanently finalizes the applied rows.

### 4.2 Page items

| Item | Type | Rule |
|---|---|---|
| `P500_COM_ID` | Select List | Required; authorized companies only |
| `P500_LIST_DATE` | Date Picker | Required; first day of month; default current month first day |
| `P500_PERIOD_FROM` | Display Only | `ADD_MONTHS(TRUNC(P500_LIST_DATE,'MM'),-1)` |
| `P500_PERIOD_TO` | Display Only | `TRUNC(P500_LIST_DATE,'MM')-1` |
| `P500_SALARY_MONTH` | Display Only | `YYYYMM` from list date |
| `P500_VIEW_MODE` | Radio | `ALL`, `NEW_DUE`, `CARRY_FORWARD`, `READY`, `APPLIED`, `HOLD`, `PUNISHMENT`, `ERROR` |
| `P500_ACTION_CODE` | Select List | Default `READY`; action for checked report rows |
| `P500_ACTION_REMARKS` | Textarea | Reason/audit remarks for the selected action |
| `P500_REVIEW_DATE` | Date Picker | Used for temporary hold |
| `P500_REVISED_EFFECTIVE_DATE` | Date Picker | Required for punishment delay |
| `P500_PUNISHMENT_REF_NO` | Text Field | Required for punishment actions |
| `P500_FORFEIT_CONFIRM` | Checkbox | Required for punishment forfeit |
| `P500_APPLIED_COUNT` | Hidden | Number applied to salary structure |
| `P500_PROCESSED_COUNT` | Hidden | Number permanently finalized |

Header text example:

```text
August 2026 Increment List
New due period: 01-Jul-2026 to 31-Jul-2026
Carry forward: unresolved holds from earlier lists
Salary month: August 2026
```

### 4.3 KPI cards

- Newly Due
- Carry Forward
- Ready
- Temporary Hold
- Punishment Delay
- Punishment Forfeit
- At EB Hold
- At Step 25
- Processing Errors

Cards refresh after every action and act as worklist filters.

### 4.4 Main Interactive Report

Use an Interactive Report, not an editable grid. The first report column is an
`APEX_ITEM.CHECKBOX2` selector. Salary, step, status and date columns remain
read-only; all changes go through the package process.

Columns:

- Select checkbox
- Source: `NEW` or `CARRY`
- Employee code and name
- Department and designation
- Grade and pay scale
- Confirmation date
- Consideration date
- Original effective date
- Revised punishment effective date
- Current list date and salary month
- Current basic and proposed basic
- Increment amount
- Current step → proposed step, such as `9 → 10 of 25`
- Phase: `PRE_EB`, `EB`, `POST_EB`, `MAX`
- EB crossing/EB hold indicator
- Decision
- Work status
- Hold/punishment reason
- Review/release date
- Processing message

Default order:

1. carry-forward temporary holds;
2. punishment cases;
3. newly due cases;
4. employee code.

Recommended Page 500 report source:

```sql
SELECT APEX_ITEM.CHECKBOX2(
           p_idx        => 1,
           p_value      => i.increment_id,
           p_attributes => 'class="inc-select"'
       ) AS select_row,
       i.increment_id,
       CASE
         WHEN i.original_list_date = i.current_list_date THEN 'NEW'
         ELSE 'CARRY'
       END AS source_type,
       e.emp_id AS employee_code,
       TRIM(e.f_name || ' ' || e.l_name) AS employee_name,
       dp.dept_name,
       d.designation,
       i.original_list_date,
       i.current_list_date,
       i.salary_month,
       i.due_date AS consideration_date,
       i.effective_date AS original_effective_date,
       i.revised_effective_date,
       i.old_basic,
       i.proposed_basic,
       i.increment_amount,
       i.from_step_no,
       i.to_step_no,
       i.total_steps,
       i.decision_code,
       i.hold_type,
       i.status,
       i.hold_reason,
       i.hold_review_date,
       i.punishment_ref_no
  FROM hr_employee_increment i
       JOIN employees e ON e.id = i.emp_id
       LEFT JOIN departments dp ON dp.id = e.dept_id
       LEFT JOIN designations d ON d.id = e.desig_id
 WHERE i.com_id = :P500_COM_ID
   AND i.current_list_date =
       TRUNC(TO_DATE(:P500_LIST_DATE, 'DD-MON-YYYY'))
   AND i.status NOT IN ('POSTED','FORFEITED','CANCELLED','REVERSED',
                        'CLOSED_NO_INCREMENT')
```

Set `SELECT_ROW` to **Escape Special Characters = No**, and disable sorting,
filtering and hiding for that column. Hide `INCREMENT_ID`. `APEX_APPLICATION.G_F01`
contains the checked increment IDs after submit. Checkbox selections apply only
to rows rendered on the current report page.

Apply `P500_VIEW_MODE` as a server-side filter or through saved Interactive
Report filters. Never concatenate item values into dynamic SQL.

### 4.5 Toolbar buttons

| Button | Selected rows | Action |
|---|---:|---|
| Generate/Refresh List | No | `PKG_HR_INCREMENT_SIMPLE.PREPARE_MONTHLY_LIST` |
| Apply Selected Action | Yes | Uses `P500_ACTION_CODE` and remarks for every checked row |
| Apply READY to Salary Structure | No; applies all READY rows | `APPLY_READY_MONTHLY_LIST` |
| Final Submit | No; permanently finalizes all APPLIED rows | `FINALIZE_MONTHLY_LIST` |

### 4.6 Selected Action region

Place a compact Static Content region directly above the Interactive Report.
Use this select-list LOV for `P500_ACTION_CODE`:

```text
Apply for Increment;READY
Temporary Hold;TEMP_HOLD
Punishment Delay;PUNISHMENT_DELAY
Punishment Forfeit;PUNISHMENT_FORFEIT
Release Completed Hold;RELEASE_HOLD
Undo Applied Increment;UNDO_APPLIED
Recalculate;RECALCULATE
```

Default return value: `READY`.

Items:

- action type;
- reason/remarks explaining why the action is taken;
- temporary-hold review date;
- punishment reference/order number;
- revised effective date for `PUNISHMENT_DELAY` only;
- confirmation checkbox for `PUNISHMENT_FORFEIT`.

Dynamic behavior:

- `TEMP_HOLD`: show review date; hide revised effective date.
- `PUNISHMENT_DELAY`: require punishment reference, reason and revised effective date.
- `PUNISHMENT_FORFEIT`: require punishment reference, reason and confirmation.
- `READY`: no exceptional fields; retain original effective date.
- `RELEASE_HOLD`: require release remarks.
- `UNDO_APPLIED`: require undo reason; allowed only when status is `APPLIED`.
- `RECALCULATE`: hide all exceptional items.

The same action and remarks are applied to all checked employees. If employees
need different reasons, process them separately so each occurrence has an
accurate audit reason.

### 4.7 Generate/Refresh process

The package performs two actions:

1. Inserts new employee occurrences whose next consideration date is inside the previous-month window and marks every normal eligible occurrence `READY` by default.
2. Moves unresolved temporary holds into the displayed monthly list as carry-forward without duplicating the occurrence.

After generation, HR reviews the list and changes only exceptions to temporary hold, punishment delay or punishment forfeit. EB holds, step-25 maximum cases, configuration errors and existing carry-forward holds are never auto-readied. Existing `READY`, `APPLIED`, `HOLD`, `PUNISHMENT`, `POSTED`, or `FORFEITED` decisions are never overwritten by refresh.

### 4.8 Apply salary, undo, and final submit

`Apply READY to Salary Structure` performs the live financial change:

- updates only `EMP_SALARY_STRUCTURE` heads `001` Basic, `005` HR,
  `013` PF and `057` CPF;
- leaves every other existing component unchanged, including `25`/`025` and
  `26`/`026`; head codes are normalized only for comparison;
- writes old/new rows to `EMP_SALARY_STRUCTURE_HIST`;
- creates an `INCREMENT` action with `APPROVAL_STATUS = 'PENDING_FINAL'`;
- updates employee last/next increment dates;
- marks the occurrence `APPLIED`.

While status is `APPLIED`, HR may choose `Undo Applied Increment`. Undo restores
the previous salary components and employee increment dates, creates a
compensating action/history trail, and normally returns the occurrence to
`READY`. HR can correct the decision and apply it again.

`Final Submit` does not calculate or apply salary again. It validates that live
components still match the applied history, changes the pending increment action
to `APPROVED`, and marks the occurrence `POSTED`. Final submit is blocked while
any `READY` employee remains; apply those employees first or record a hold/
punishment exception.

After `POSTED`, the module provides no revert button and the database reversal
procedure rejects the occurrence. Any later correction must follow a separate,
formally authorized salary-adjustment process outside this increment workflow.

Before each button, show counts and salary totals. Require typed salary-month
confirmation, for example `202608`, for both apply and final submit. Apply and
final operations each use their own atomic transaction; a failed apply request
rolls back that request, while a failed final request leaves the previously
applied rows pending so they can be reviewed or undone.

APEX commits only after the package completes successfully. Any employee failure rolls the complete batch back to the package savepoint; therefore a partially posted monthly batch is not allowed.

### 4.9 Page security

- `INC_VIEW`: view page/report.
- `INC_PREPARE`: generate, recalculate, decide.
- `INC_PROCESS`: apply salary and final submit.
- `INC_REVERT`: undo `APPLIED` rows on Page 500 before final submit only.
- The package rechecks database status and locks the occurrence. Enforce `INC_*` authorizations in APEX and grant package execution only to the application schema; hidden buttons alone are not a security boundary.
- Preparer and final processor should be different users in production.

### 4.10 APEX page-process calls

Generate/Refresh button process:

```sql
BEGIN
    hrms.pkg_hr_increment_simple.prepare_monthly_list(
        p_com_id      => :P500_COM_ID,
        p_list_date   => TO_DATE(:P500_LIST_DATE, 'DD-MON-YYYY'),
        p_user_id     => :G_USER_ID,
        p_new_count   => :P500_NEW_COUNT,
        p_carry_count => :P500_CARRY_COUNT
    );
END;
```

Apply Selected Action process. Add a server-side condition for the
`APPLY_SELECTED_ACTION` button:

```sql
DECLARE
    l_increment_id NUMBER;
    l_allowed      NUMBER;
BEGIN
    IF APEX_APPLICATION.G_F01.COUNT = 0 THEN
        RAISE_APPLICATION_ERROR(-20001, 'Select at least one employee.');
    END IF;

    FOR i IN 1 .. APEX_APPLICATION.G_F01.COUNT LOOP
        l_increment_id := TO_NUMBER(APEX_APPLICATION.G_F01(i));

        /* Do not trust a posted checkbox value without checking its list. */
        SELECT COUNT(*)
          INTO l_allowed
          FROM hr_employee_increment x
         WHERE x.increment_id = l_increment_id
           AND x.com_id = :P500_COM_ID
           AND x.current_list_date =
               TRUNC(TO_DATE(:P500_LIST_DATE, 'DD-MON-YYYY'))
           AND x.status NOT IN (
               'POSTED', 'FORFEITED', 'CANCELLED', 'REVERSED',
               'CLOSED_NO_INCREMENT'
           );

        IF l_allowed = 0 THEN
            RAISE_APPLICATION_ERROR(
                -20001,
                'A selected employee is outside the displayed increment list.'
            );
        END IF;

        IF :P500_ACTION_CODE = 'UNDO_APPLIED' THEN
            hrms.pkg_hr_increment_simple.revert_increment(
                p_increment_id => l_increment_id,
                p_reason       => :P500_ACTION_REMARKS,
                p_user_id      => :G_USER_ID,
                p_reopen_yn    => 'Y'
            );
        ELSIF :P500_ACTION_CODE = 'RELEASE_HOLD' THEN
            hrms.pkg_hr_increment_simple.release_hold(
                p_increment_id => l_increment_id,
                p_remarks      => :P500_ACTION_REMARKS,
                p_user_id      => :G_USER_ID
            );
        ELSIF :P500_ACTION_CODE = 'RECALCULATE' THEN
            hrms.pkg_hr_increment_simple.recalculate_case(
                p_increment_id => l_increment_id,
                p_user_id      => :G_USER_ID
            );
        ELSE
            hrms.pkg_hr_increment_simple.set_decision(
                p_increment_id      => l_increment_id,
                p_decision_code     => :P500_ACTION_CODE,
                p_reason            => :P500_ACTION_REMARKS,
                p_review_date       =>
                    CASE
                        WHEN :P500_REVIEW_DATE IS NOT NULL
                        THEN TO_DATE(:P500_REVIEW_DATE, 'DD-MON-YYYY')
                    END,
                p_revised_effective =>
                    CASE
                        WHEN :P500_REVISED_EFFECTIVE_DATE IS NOT NULL
                        THEN TO_DATE(
                                 :P500_REVISED_EFFECTIVE_DATE,
                                 'DD-MON-YYYY'
                             )
                    END,
                p_punishment_ref_no => :P500_PUNISHMENT_REF_NO,
                p_user_id           => :G_USER_ID
            );
        END IF;
    END LOOP;
END;
```

Required APEX validations:

- remarks are required unless action is `RECALCULATE`;
- punishment delay requires remarks, punishment reference and revised date;
- punishment forfeit requires remarks, punishment reference and confirmation;
- temporary hold may use a review date but never changes the original effective date.

Apply READY to Salary Structure button process:

```sql
BEGIN
    hrms.pkg_hr_increment_simple.apply_ready_monthly_list(
        p_com_id        => :P500_COM_ID,
        p_list_date     => TO_DATE(:P500_LIST_DATE, 'DD-MON-YYYY'),
        p_user_id       => :G_USER_ID,
        p_applied_count => :P500_APPLIED_COUNT
    );
END;
```

Final Submit button process:

```sql
BEGIN
    hrms.pkg_hr_increment_simple.finalize_monthly_list(
        p_com_id          => :P500_COM_ID,
        p_list_date       => TO_DATE(:P500_LIST_DATE, 'DD-MON-YYYY'),
        p_user_id         => :G_USER_ID,
        p_processed_count => :P500_PROCESSED_COUNT
    );
END;
```

After each successful process, refresh the KPI cards and Interactive Report. On error, use the application error handler to display the package message and preserve the user’s filters.

---

## 5. Page 501 — Increment Register

### Purpose

Read-only history and search page for every increment occurrence. `POSTED` rows are final; Page 501 has no revert process.

### Regions

Faceted Search + Interactive Report.

Facets:

- company;
- list/salary month;
- consideration/effective/processing date;
- employee/department/grade;
- decision and work status;
- new versus carry-forward;
- pre-EB/EB/post-EB/max;
- temporary/punishment reason;
- letter status.

Report columns:

- employee and organization;
- original/current list dates and salary month;
- consideration, original effective, revised effective and processing dates;
- old/new basic and gross;
- from/to step;
- decision/status/reason;
- approved/processed by;
- action ID, pre-final undo action/reason/date, final approval and letter link.

Row actions:

- View status timeline;
- Open salary comparison drawer/region;
- Open Page 502 for letter;

No editable report columns are allowed.

---

## 6. Page 502 — Increment Letter Center

### Purpose

List `POSTED` increments and open one letter or all letters for the selected
company/salary month.

### Items and regions

- `P502_COM_ID`: required company Select List.
- `P502_SALARY_MONTH`: required `YYYYMM` Select List.
- Company, salary month, employee and letter-status filters.
- Report of `POSTED` increments only.
- Columns: employee, designation, department, grade, effective date, old/new basic/gross, increment amount, letter number/status/date.
- Letter template select list using `HR_LETTER_TEMPLATE.ACTION_TYPE='INCREMENT'`.

Buttons:

- Generate Letter;
- Preview;
- Approve;
- Issue;
- Print/PDF, opening Page 503.
- Print All Posted Letters, opening Page 503 without an increment ID.

The letter is generated from immutable action/salary history. Current salary master values must not replace historical old/new amounts.

Generate Letter button process:

```sql
BEGIN
    hrms.pkg_hr_increment_simple.generate_letter(
        p_increment_id => :P502_INCREMENT_ID,
        p_template_id  => :P502_TEMPLATE_ID,
        p_user_id      => :G_USER_ID,
        p_letter_id    => :P502_LETTER_ID
    );
END;
```

`PRINT_ALL_LETTERS` targets Page 503 and passes:

```text
P503_COM_ID       = &P502_COM_ID.
P503_SALARY_MONTH = &P502_SALARY_MONTH.
P503_INCREMENT_ID = null
```

The row-level Print link passes the same company/month plus that row's
`INCREMENT_ID`.

---

## 7. Page 503 — Print Increment Letter

### Purpose

Printable PL/SQL HTML Dynamic Content page. It prints one letter when an
increment ID is supplied, or every `POSTED` letter for the selected company and
salary month when the ID is null.

Page mode:

- normal printable APEX page for browser print;
- optional PDF output through the configured APEX print server.

Page items:

- `P503_COM_ID`: Hidden, required and checksum protected;
- `P503_SALARY_MONTH`: Hidden, required and checksum protected;
- `P503_INCREMENT_ID`: Hidden, optional and checksum protected.

Create one region:

```text
Name        : Posted Increment Letters
Type        : PL/SQL Dynamic Content
Static ID   : INCREMENT_LETTERS
Template    : Blank with Attributes (No Grid)
```

Paste the complete PL/SQL source from
`increment/page_503_increment_letter_dynamic_content.sql`. It renders:

- company letterhead and stable letter number;
- employee, designation and department;
- consideration/effective date and scale step;
- old/new/difference for `001` Basic, `005` HR, `013` PF and `057` CPF;
- old/new/difference for gross salary;
- one A4 section per employee with a print page break;
- a browser `Print All Letters` button.

The comparison comes from `EMP_SALARY_STRUCTURE_HIST` for the finalized action,
not from current salary structure, so later salary changes cannot alter an old
letter.

Security:

- all Page 503 arguments are checksum protected;
- user must have company access;
- the query itself requires `HR_EMPLOYEE_INCREMENT.STATUS = 'POSTED'`;
- if print-event auditing is required, add a separate explicit `Record Print`
  button/process; do not perform DML while the Dynamic Content region renders.

---

## 8. Database package behind the pages

Use one package: `PKG_HR_INCREMENT_SIMPLE`.

```text
PREPARE_MONTHLY_LIST
    Generate new previous-month cases and expose carry-forward holds.

RECALCULATE_CASE
    Revalidate grade, pay scale, current salary, step and proposed salary.

SET_DECISION
    Mark READY, TEMP_HOLD, PUNISHMENT_DELAY or PUNISHMENT_FORFEIT.

RELEASE_HOLD
    Release exactly one occurrence and retain its original effective date.

APPLY_READY_MONTHLY_LIST
    Atomically apply all READY cases to live salary and mark them APPLIED.

FINALIZE_MONTHLY_LIST
    Validate and permanently post all APPLIED cases; no salary recalculation.

REVERT_INCREMENT
    Before final submit only: restore an APPLIED salary from history and return
    it to READY (or permanently withdraw it). Reject every POSTED occurrence.

GENERATE_LETTER
    Create a stored historical letter for one POSTED increment.
```

Every public procedure receives `P_USER_ID`. The package obtains employee, company, salary, dates and status from the database rather than trusting APEX items.

### Required error codes

| Code | Meaning |
|---:|---|
| `-20501` | List date must be first day of month |
| `-20502` | Employee occurrence already exists |
| `-20503` | Case is not editable |
| `-20504` | Reason/reference/revised date is missing |
| `-20505` | Active temporary hold blocks posting |
| `-20506` | EB hold blocks increment |
| `-20507` | Step 25/maximum reached |
| `-20508` | Salary or scale changed; recalculate |
| `-20509` | Another user is processing this list |
| `-20510` | Final submit failed; applied rows remain pending |
| `-20511` | Letter allowed only for posted increment |
| `-20512` | Revert reason is required |
| `-20513` | Only an APPLIED pre-final occurrence can be undone; POSTED is final |
| `-20514` | A later approved salary/career action blocks revert |
| `-20515` | Salary-component history is missing; safe revert is impossible |
| `-20516` | Reopen option must be Y or N |
| `-20517` | Live salary no longer matches the applied component values |
| `-20518` | No READY employees available to apply |
| `-20519` | Applying salary failed and the apply request rolled back |
| `-20520` | READY employees remain and must be applied before final submit |

---

## 9. Simple end-to-end process

```text
Page 500
Choose company + 01-Aug-2026
    ↓
Generate list for 01-Jul–31-Jul
    ↓
Review employees
    ↓
Review list; record Temporary Hold / Punishment exceptions
    ↓
Release completed holds when applicable
    ↓
Apply all READY employees to Salary Structure → APPLIED
    ↓
Review; optionally Undo APPLIED rows before final
    ↓
Final Submit all APPLIED employees → POSTED (irreversible)
    ↓
Posted employees disappear from Page 500
    ↓
Page 501 shows permanent increment register
    ↓
Page 502 generates/manages letters
    ↓
Page 503 prints letter/PDF
```

On 01-Sep-2026, Page 500 generates new August consideration cases and also displays unresolved temporary holds from the August list as carry-forward for salary month September.

---

## 10. Required implementation prerequisite

The original repository did not contain the production DDL for `HR_EMPLOYEE_INCREMENT`, even though existing procedures referenced it. A complete new-install definition is now included at `Table/hr_employee_increment.sql`. Before compiling the package against an existing database, reconcile that definition with the real production table and add the minimum missing fields required by this design:

- original list date;
- current list date;
- salary month;
- consideration/due date;
- original and revised effective dates;
- decision code and work status;
- hold type, reason, review date and punishment reference;
- current/proposed salary and scale-step snapshots;
- action, applied, pre-final undo, final processing and letter references;
- version number and audit columns.

Do not create a second competing increment-detail table. Use `HR_EMPLOYEE_INCREMENT` as the single occurrence record.

## 11. Recommended database deployment order

For a new/test schema:

1. Base employee, company, designation, department and salary objects.
2. `PAY_SCALE_MASTER`, `PAY_SCALE_DETAIL`, allowance configuration and generated scale steps.
3. `HR_EMPLOYEE_INCREMENT`.
4. Updated `HR_EMPLOYEE_ACTION`.
5. Updated `HR_INCREMENT_HOLD`.
6. Salary history and letter tables/templates.
7. `FN_GET_NEXT_BASIC` and salary calculation functions.
8. `PR_HOLD_INCREMENT`, `PR_RELEASE_INCREMENT_HOLD`, `PR_APPLY_INCREMENT`, `PR_REVERSE_INCREMENT`.
9. `PKG_HR_INCREMENT_SIMPLE`.
10. Run the EB/25-step validation script, then create APEX Pages 500–503.

For an existing production schema, do **not** execute the supplied `DROP TABLE` scripts. Produce reviewed `ALTER TABLE` migrations, migrate/backfill existing increment data, validate constraints, compile objects, and run UAT in a copy of production first.

For the `READY -> APPLIED -> POSTED` lifecycle, the reviewed starting migration
is `increment/upgrade_apply_before_final.sql`. Run it before compiling
`PR_APPLY_INCREMENT`, `PR_REVERSE_INCREMENT`, and `PKG_HR_INCREMENT_SIMPLE`.
