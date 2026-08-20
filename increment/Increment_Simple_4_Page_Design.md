# Simple Annual Increment Module — Four Oracle APEX Pages

This is the single authoritative design guide for the increment module. The complete user workflow uses Pages 500–503.

## 1. Final page map

| Page | Name | Purpose |
|---:|---|---|
| 500 | Monthly Increment Workbench | Generate monthly list, decide ready/temporary hold/punishment, release holds, and perform final processing |
| 501 | Increment Register | Search all ready, held, punishment, processed, forfeited, failed, and reversed increments |
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
3. A processed occurrence never appears again in the operational worklist.
4. A temporary hold remains the same occurrence and appears in every following monthly list as carry-forward until released and processed.
5. Temporary hold never changes consideration or effective date.
6. Normal effective date is the confirmation anniversary after completion of the configured cycle, normally 12 months.
7. Only an approved punishment delay may set a revised payable effective date. The original effective date is never overwritten.
8. After processing, the next consideration date advances from the original consideration anchor—not from processing date.
9. Step 25 is final. After posting step 25, `NEXT_INCREMENT_DATE` is cleared.

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
| `DRAFT` | Generated but not reviewed |
| `READY` | Reviewed and ready for final posting |
| `HOLD` | Temporary hold |
| `PUNISHMENT` | Punishment delay awaiting payable date/release |
| `FORFEITED` | Punishment forfeiture completed without salary update |
| `POSTED` | Increment processed successfully |
| `ERROR` | Final processing failed and rolled back |
| `REVERSED` | Posted increment later reversed |

---

## 4. Page 500 — Monthly Increment Workbench

### 4.1 Purpose

This is the only operational page. HR generates the list, reviews employees, assigns holds or punishment decisions, releases completed holds, and runs final processing here.

### 4.2 Page items

| Item | Type | Rule |
|---|---|---|
| `P500_COM_ID` | Select List | Required; authorized companies only |
| `P500_LIST_DATE` | Date Picker | Required; first day of month; default current month first day |
| `P500_PERIOD_FROM` | Display Only | `ADD_MONTHS(TRUNC(P500_LIST_DATE,'MM'),-1)` |
| `P500_PERIOD_TO` | Display Only | `TRUNC(P500_LIST_DATE,'MM')-1` |
| `P500_SALARY_MONTH` | Display Only | `YYYYMM` from list date |
| `P500_VIEW_MODE` | Radio | `ALL`, `NEW_DUE`, `CARRY_FORWARD`, `READY`, `HOLD`, `PUNISHMENT`, `ERROR` |
| `P500_SELECTED_COUNT` | Display Only | Selected grid rows |

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

### 4.4 Main Interactive Grid

The grid is read-only except for the selection checkbox. Status and salary amounts are never edited directly.

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
SELECT i.increment_id,
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
   AND i.current_list_date = :P500_LIST_DATE
   AND i.status NOT IN ('POSTED','FORFEITED','CANCELLED','REVERSED',
                        'CLOSED_NO_INCREMENT')
```

Apply `P500_VIEW_MODE` as a server-side filter or through saved Interactive Grid reports. Never concatenate item values into dynamic SQL.

### 4.5 Toolbar buttons

| Button | Selected rows | Package call |
|---|---:|---|
| Generate/Refresh List | No | `PKG_HR_INCREMENT_SIMPLE.PREPARE_MONTHLY_LIST` |
| Mark Ready | Yes | `SET_DECISION(..., 'READY')` |
| Temporary Hold | Yes | `SET_DECISION(..., 'TEMP_HOLD')` |
| Punishment Delay | Yes | `SET_DECISION(..., 'PUNISHMENT_DELAY')` |
| Punishment Forfeit | Yes | `SET_DECISION(..., 'PUNISHMENT_FORFEIT')` |
| Release Hold | Yes | `RELEASE_HOLD` |
| Recalculate | Yes | `RECALCULATE_CASE` |
| Final Process | No; processes all READY rows in the current list | `FINALIZE_MONTHLY_LIST` |

### 4.6 Inline decision dialog region

Use an Inline Dialog region on Page 500, so no extra decision page is needed.

Items:

- selected increment ID(s), protected;
- decision type;
- reason code;
- reason/remarks;
- temporary-hold review date;
- punishment reference/order number;
- revised effective date for `PUNISHMENT_DELAY` only;
- confirmation checkbox for `PUNISHMENT_FORFEIT`.

Dynamic behavior:

- `TEMP_HOLD`: show review date; hide revised effective date.
- `PUNISHMENT_DELAY`: require punishment reference, reason and revised effective date.
- `PUNISHMENT_FORFEIT`: require punishment reference, reason and confirmation.
- `READY`: no exceptional fields; retain original effective date.

### 4.7 Generate/Refresh process

The package performs two actions:

1. Inserts new employee occurrences whose next consideration date is inside the previous-month window.
2. Moves unresolved temporary holds into the displayed monthly list as carry-forward without duplicating the occurrence.

Existing `READY`, `HOLD`, `PUNISHMENT`, `POSTED`, or `FORFEITED` decisions are never overwritten by refresh.

### 4.8 Final Process dialog

Before posting, show:

- ready employee count;
- total old basic/new basic/increase;
- list date and salary month;
- employees skipped because of temporary/punishment hold;
- EB/max/configuration blockers;
- payroll months requiring adjustment;
- typed confirmation using salary month, e.g. `202608`.

Final processing rules:

1. Only `READY` cases are posted.
2. Holds remain visible for a future monthly list.
3. Forfeited cases are finalized without updating salary.
4. All ready cases are processed in one strict transaction.
5. Any failure rolls back salary, action, history and case updates for the whole posting request.
6. On success, the grid refresh removes posted employees from the operational view.

### 4.9 Page security

- `INC_VIEW`: view page/grid.
- `INC_PREPARE`: generate, recalculate, decide.
- `INC_PROCESS`: final posting.
- The package checks company access and status again; hidden buttons are not the security boundary.
- Preparer and final processor should be different users in production.

### 4.10 APEX page-process calls

Generate/Refresh button process:

```sql
BEGIN
    hrms.pkg_hr_increment_simple.prepare_monthly_list(
        p_com_id      => :P500_COM_ID,
        p_list_date   => :P500_LIST_DATE,
        p_user_id     => :G_USER_ID,
        p_new_count   => :P500_NEW_COUNT,
        p_carry_count => :P500_CARRY_COUNT
    );
END;
```

Decision dialog process for selected IDs:

```sql
DECLARE
    l_ids apex_t_varchar2 := apex_string.split(:P500_SELECTED_IDS, ':');
BEGIN
    FOR i IN 1 .. l_ids.COUNT LOOP
        hrms.pkg_hr_increment_simple.set_decision(
            p_increment_id      => TO_NUMBER(l_ids(i)),
            p_decision_code     => :P500_DECISION_CODE,
            p_reason            => :P500_DECISION_REASON,
            p_review_date       => :P500_REVIEW_DATE,
            p_revised_effective => :P500_REVISED_EFFECTIVE_DATE,
            p_punishment_ref_no => :P500_PUNISHMENT_REF_NO,
            p_user_id           => :G_USER_ID
        );
    END LOOP;
END;
```

Final Process button process:

```sql
BEGIN
    hrms.pkg_hr_increment_simple.finalize_monthly_list(
        p_com_id          => :P500_COM_ID,
        p_list_date       => :P500_LIST_DATE,
        p_user_id         => :G_USER_ID,
        p_processed_count => :P500_PROCESSED_COUNT
    );
END;
```

After each successful process, refresh the KPI cards and Interactive Grid. On error, use the application error handler to display the package message and preserve the user’s filters.

---

## 5. Page 501 — Increment Register

### Purpose

Read-only history and search page for every increment occurrence.

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
- action ID and letter link.

Row actions:

- View status timeline;
- Open salary comparison drawer/region;
- Open Page 502 for letter;

No editable columns are allowed.

---

## 6. Page 502 — Increment Letter Center

### Purpose

List processed increments and generate/approve/issue their letters.

### Items and regions

- Company, salary month, employee, letter status filters.
- Report of `POSTED` increments only.
- Columns: employee, designation, department, grade, effective date, old/new basic/gross, increment amount, letter number/status/date.
- Letter template select list using `HR_LETTER_TEMPLATE.ACTION_TYPE='INCREMENT'`.

Buttons:

- Generate Letter;
- Preview;
- Approve;
- Issue;
- Print/PDF, opening Page 503.

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

---

## 7. Page 503 — Print Increment Letter

### Purpose

Printable letter page with no navigation or editing controls.

Page mode:

- normal printable APEX page for browser print;
- optional PDF output through the configured APEX print server.

Protected item: `P503_LETTER_ID`.

Regions:

- company letterhead;
- letter number/date;
- employee identity and job details;
- old/new salary component comparison;
- increment amount/percentage;
- consideration and effective date;
- authorized signature area.

Security:

- letter ID is checksum protected;
- user must have company access;
- only approved/issued letters may be printed externally;
- print action is audited.

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

FINALIZE_MONTHLY_LIST
    Strict atomic posting of all READY cases for the displayed list/company.

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
| `-20510` | Final processing rolled back |
| `-20511` | Letter allowed only for posted increment |

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
Mark Ready / Temporary Hold / Punishment
    ↓
Release completed holds when applicable
    ↓
Final Process all READY employees
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
- action, processing and letter references;
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
8. `PR_HOLD_INCREMENT`, `PR_RELEASE_INCREMENT_HOLD`, `PR_APPLY_INCREMENT`.
9. `PKG_HR_INCREMENT_SIMPLE`.
10. Run the EB/25-step validation script, then create APEX Pages 500–503.

For an existing production schema, do **not** execute the supplied `DROP TABLE` scripts. Produce reviewed `ALTER TABLE` migrations, migrate/backfill existing increment data, validate constraints, compile objects, and run UAT in a copy of production first.
