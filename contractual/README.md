# Contract Renewal - Oracle APEX Pages 520, 521 and 522

This folder is the implementation guide for the contractual-employee renewal
module. The user workflow is intentionally limited to three APEX pages.

| Page | Name | Purpose |
|---:|---|---|
| 520 | Contract Renewal List | Due list, workflow register, search and navigation |
| 521 | Contract Renewal Entry and Approval | Create, edit salary proposal, submit, approve and finally post |
| 522 | Contract Renewal Letter | Bengali A4 preview/print page based on `contract_renewal.pdf` |

The central rule is:

```text
DRAFT -> SUBMITTED -> APPROVED -> POSTED
                         |           |
                         |           +-- current salary and contract updated
                         +-- renewal letter generated; salary unchanged
```

`CANCELLED` is terminal. `SUBMITTED` or `APPROVED` may return to `DRAFT` with a
mandatory reason. `POSTED` cannot be reopened by this module.

## 1. What was taken from the supplied letter

The supplied scan is a one-page Bengali contract-renewal letter. Page 522 keeps
its material structure:

- Human Resources heading, reference number and letter date;
- employee name, staff number, designation, department/company and location;
- underlined subject `চুক্তি নবায়ন`;
- renewed period and effective date;
- numbered renewal conditions;
- grade and pay-scale text;
- salary-head/amount list, total and amount in words;
- authorized signature and distribution/copy list.

The employee, grade, scale, term, salary amounts, signatory and recipients are
data-driven. The example employee, dates, grade and amounts in the scan are not
hardcoded.

## 2. Files and installation

| File | Purpose |
|---|---|
| `00_install.sql` | SQLcl/SQL*Plus install wrapper |
| `01_contract_renewal_tables.sql` | Contract master, workflow, salary snapshot and audit tables |
| `02_contract_renewal_letter_config.sql` | Signatory/recipient masters, renewal recipient mapping and Bengali template |
| `03_pkg_hr_contract_renewal.sql` | All workflow and final-post business logic |
| `page_520_contract_renewal_list.sql` | Page 520 report/card sources |
| `page_521_contract_renewal_entry.sql` | Page 521 LOV, grid and process sources |
| `page_522_contract_renewal_letter.sql` | Page 522 printable dynamic-content region |
| `99_contract_renewal_checks.sql` | Post-install queries and UAT checklist |

Run from the `contractual` directory as the HRMS owner:

```sql
@00_install.sql
```

If the deployment tool does not support `@@`, run the first three numbered SQL
files in order. Then run `99_contract_renewal_checks.sql`. Stop if
`PKG_HR_CONTRACT_RENEWAL` has any `USER_ERRORS`.

The letter configuration reuses `HR_LETTER_SIGNATORY` and
`HR_LETTER_RECIPIENT` from the promotion module. Its DDL is guarded, so it also
works when the promotion configuration was already installed. Verify all seeded
names, titles and recipient labels with HR before production deployment.

## 3. Data model

### `HR_EMPLOYEE_CONTRACT`

One live row per contractual employee. This is the source for the Page 520 due
list. It records the current contract start/end date and current grade, scale and
step. A first renewal can initialize this row from Page 521 when legacy data has
not yet been migrated. After final submit, the row moves to the renewed term.

For a bulk legacy migration, load this table before opening the module. Do not
derive the current end date from `EMPLOYEES.JOIN_DATE`; employment start and the
current contract term are different facts.

### `HR_CONTRACT_RENEWAL`

The immutable workflow header and letter snapshots. Employee display data is
copied into snapshot columns so an old letter does not change later when a name,
designation, department or location master is edited.

### `HR_CONTRACT_RENEWAL_SALARY`

Every active live salary row is copied when the draft is created. `OLD_AMOUNT`
is the concurrency/audit snapshot and `NEW_AMOUNT` is the proposal. Basic salary
is always derived from the selected active pay scale and step. Other salary
heads are explicit payroll decisions in the Page 521 grid.

The package deliberately does not guess company-specific allowance formulas.
Columns such as `PAY_SCALE_MASTER.HR`, `CONV`, `MEDICAL`, `ALLOWANCE`, `CPF` and
`PFCONT` do not prove whether a value is a percentage, fixed amount or payroll
base at every installation. If those rules are formally defined, add a separate
calculation routine and call it before `SAVE_DRAFT`; do not embed assumptions in
APEX dynamic actions.

### Audit and letter tables

- `HR_CONTRACT_RENEWAL_AUDIT` records every workflow transition.
- `HR_EMPLOYEE_LETTER.CONTRACT_RENEWAL_ID` links the approved letter before an
  employee action exists.
- `HR_CONTRACT_RENEW_RECIPIENT` holds the Page 521 TO/COPY choices.
- `HR_EMPLOYEE_ACTION` is inserted only at final submit, when the business event
  truly updates live salary.

## 4. Business rules

1. An employee may have only one unfinished renewal (`DRAFT`, `SUBMITTED` or
   `APPROVED`). A function-based unique index enforces this.
2. The new term must start exactly one day after the current term ends.
3. The new end date must produce a whole number of calendar months.
4. Grade, active scale, step and scale effective dates must agree.
5. Basic salary comes from `PAY_SCALE_DETAIL.BASIC_AMOUNT` for the selected
   scale/step. It is not freely editable.
6. Approval generates the letter and locks business fields. Approval does not
   update salary.
7. Final submit is allowed only when `NEW_FROM_DATE <= SYSDATE`. This prevents a
   future renewal from changing current payroll early.
8. Final submit locks the employee contract and all active salary rows. If the
   current contract or any salary amount differs from the draft snapshot, the
   full request is rejected.
9. Final submit is atomic: action, salary, current contract, employee grade,
   detail-post flags, letter status and renewal status either all succeed or all
   roll back.
10. A posted renewal is final. Corrections require a separately authorized
    salary-adjustment/reversal process outside these three pages.

`EMPLOYEES.EMP_TYPE` is installation-specific in this repository. The design
does not assume that a particular number means contractual. The live
`HR_EMPLOYEE_CONTRACT` row is the eligibility source. If your employee-type
master has a confirmed contractual code, add it to the Page 521 employee LOV as
an additional filter.

## 5. Page 520 - Contract Renewal List

Create a normal page named **Contract Renewal List**.

### Page items

| Item | Type | Default / use |
|---|---|---|
| `P520_COM_ID` | Required Select List | Authorized company; session company by default |
| `P520_VIEW_MODE` | Radio Group | `ALL`, `DUE`; default `ALL` |
| `P520_DUE_TO` | Date Picker | `TRUNC(SYSDATE)+90` |
| `P520_STATUS` | Select List | Workflow status; default `ALL` |
| `P520_FROM_DATE` | Date Picker | Optional renewed-from filter |
| `P520_TO_DATE` | Date Picker | Optional renewed-from filter |

Items must submit on change and refresh the affected regions. Apply company
authorization in the SQL and in APEX; a hidden company item is not a security
boundary. Set every date picker in Pages 520 and 521 to the explicit format mask
`DD-MON-YYYY`, matching the supplied process SQL.

### Region order

1. Breadcrumb/title.
2. Filter region.
3. KPI Cards.
4. **Contracts Due for Renewal** Interactive Report.
5. **Renewal Register** Interactive Report.

Use the three sources in `page_520_contract_renewal_list.sql`. Set the due-list
`CREATE_URL` and register `ENTRY_URL`/`LETTER_URL` columns as Link columns and do
not expose their raw URLs. The letter link exists only for `APPROVED` or
`POSTED` rows.

### Buttons

| Button | Authorization | Action |
|---|---|---|
| New Renewal | `CONTRACT_RENEW_CREATE` | Open Page 521 with cache 521 cleared and pass protected `P521_COM_ID` |
| Reset Filters | `CONTRACT_VIEW` | Clear Page 520 filter items |

Use status badge colors consistently: gray DRAFT, amber SUBMITTED, blue
APPROVED, green POSTED, red CANCELLED.

## 6. Page 521 - Contract Renewal Entry and Approval

Create a normal Form page named **Contract Renewal Entry and Approval**. The
page is both the entry screen and workflow screen; no fourth page is needed.

### Page items

| Item | Type | Notes |
|---|---|---|
| `P521_RENEWAL_ID` | Hidden, Protected | Primary key passed with session checksum |
| `P521_ALLOW_BASELINE` | Hidden, Protected | Set server-side from `CONTRACT_BASELINE_ADMIN` |
| `P521_COM_ID` | Hidden, Protected | Authorized company passed from Page 520 |
| `P521_RENEWAL_NO` | Display Only | Generated `CRN-YYYY-NNNNNN` |
| `P521_EMP_ID` | Popup LOV | Required on create; read-only after draft creation |
| `P521_EMP_CODE_SNAPSHOT` | Display Only | Letter snapshot |
| `P521_EMP_NAME_SNAPSHOT` | Display Only | Letter snapshot |
| `P521_DESIGNATION_SNAPSHOT` | Display Only | Letter snapshot |
| `P521_DEPARTMENT_SNAPSHOT` | Display Only | Letter snapshot |
| `P521_LOCATION_SNAPSHOT` | Display Only | Letter snapshot |
| `P521_CURRENT_FROM_DATE` | Date Picker/Display | Editable only for first legacy baseline |
| `P521_CURRENT_TO_DATE` | Date Picker/Display | Editable only for first legacy baseline |
| `P521_OLD_GRADE_ID` | Select/Display | First baseline input; otherwise master value |
| `P521_OLD_SCALE_ID` | Select/Display | First baseline input; otherwise master value |
| `P521_OLD_STEP_NO` | Select/Display | First baseline input; otherwise master value |
| `P521_NEW_FROM_DATE` | Date Picker | Required; default current end + 1 |
| `P521_NEW_TO_DATE` | Date Picker | Required; default `ADD_MONTHS(new_from,12)-1` |
| `P521_NEW_GRADE_ID` | Select List | Required |
| `P521_NEW_SCALE_ID` | Cascading Select | Required; parent new grade/from date |
| `P521_NEW_STEP_NO` | Cascading Select | Required; parent new scale |
| `P521_OLD_BASIC` | Display Only | Snapshot total |
| `P521_NEW_BASIC` | Display Only | Scale/step Basic |
| `P521_OLD_GROSS` | Display Only | Snapshot earning total |
| `P521_NEW_GROSS` | Display Only | Proposed earning total |
| `P521_REASON` | Textarea | Business reason |
| `P521_REMARKS` | Textarea | Internal remarks |
| `P521_SPECIAL_TERMS` | Rich Text/Textarea | Optional extra text printed in letter |
| `P521_SIGNATORY_ID` | Select List | Required before submit |
| `P521_TEMPLATE_ID` | Select List | Default `CONTRACT_RENEWAL_BN` |
| `P521_APPROVAL_STATUS` | Display + Hidden | Never trust a client-posted status for logic |
| `P521_VERSION_NO` | Hidden | Display/audit support; package locks database row |
| `P521_LETTER_ID` | Hidden, Protected | Set by approval |
| `P521_ACTION_ID` | Hidden, Protected | Set by final submit |
| `P521_ACTION_REMARKS` | Textarea | Required for return/cancel |
| `P521_FINAL_CONFIRM` | Text | Must exactly match renewal number |

### Region order

1. Workflow status bar.
2. Employee and Current Contract.
3. Proposed Renewal.
4. Proposed Salary Structure Interactive Grid.
5. Letter Setup and Recipients Interactive Grid.
6. Audit Timeline report.
7. Action buttons.

The source and LOV SQL are in `page_521_contract_renewal_entry.sql`.

### Current-contract behavior

When `P521_EMP_ID` changes in create mode, fetch
`HR_EMPLOYEE_CONTRACT`. If a row exists, populate current fields and make them
read-only. If no row exists, show a warning and require HR to enter the verified
current term/grade/scale/step. `CREATE_DRAFT` creates that baseline and the first
renewal draft in the same transaction.

Suggested dynamic defaults:

```text
P521_NEW_FROM_DATE := P521_CURRENT_TO_DATE + 1
P521_NEW_TO_DATE   := ADD_MONTHS(P521_NEW_FROM_DATE, 12) - 1
P521_NEW_GRADE_ID  := P521_OLD_GRADE_ID
P521_NEW_SCALE_ID  := P521_OLD_SCALE_ID
P521_NEW_STEP_NO   := P521_OLD_STEP_NO
```

These are UI conveniences only. The package validates every value again.

### Salary grid

Use `RENEWAL_SALARY_ID` as the primary key and `P521_RENEWAL_ID` as the parent.
Show head name, old amount, new amount, difference and letter inclusion.

- Edit only in `DRAFT`.
- Basic is read-only and comes from the selected scale/step.
- `OLD_AMOUNT` is always read-only.
- Default `INCLUDE_IN_LETTER=Y` only for earning heads.
- Deductions remain in the salary snapshot for stale-data validation but do not
  print unless HR explicitly enables them and Page 522 policy is changed.
- Do not permit deletion of captured live rows.
- If authorized payroll users may add a head, use an Allowance Head LOV and
  populate its code/name/type/order from `ALLOWANCE_HEAD` server-side.

The package never deactivates a salary head that is absent from the proposal.
Instead, missing captured heads block final submit. This avoids accidental pay
loss through an incomplete grid.

### Recipient grid

The default copy list is seeded from the supplied letter. HR may reorder, add,
disable or replace recipients while the renewal is `DRAFT`. Use either a master
recipient or custom `LINE_TEXT`, never both. `TO` rows replace the default
employee address block; normal renewal letters should usually keep all rows as
`COPY`.

### Buttons and conditions

| Button | Status | Authorization | Result |
|---|---|---|---|
| Create Draft | New | `CONTRACT_RENEW_CREATE` | Snapshot employee, current term and salary |
| Save Draft | DRAFT | `CONTRACT_RENEW_EDIT` | Save header/grid and recalculate totals |
| Refresh Salary | DRAFT | `CONTRACT_RENEW_EDIT` | Discard proposal amounts and re-copy live salary |
| Submit for Approval | DRAFT | `CONTRACT_RENEW_SUBMIT` | Lock entry as SUBMITTED |
| Return to Draft | SUBMITTED/APPROVED | `CONTRACT_RENEW_RETURN` | Require reason; cancel generated letter if needed |
| Approve | SUBMITTED | `CONTRACT_RENEW_APPROVE` | Generate approved letter; do not change salary |
| View Letter | APPROVED/POSTED | `CONTRACT_VIEW` | Open Page 522 in a new window |
| Final Submit | APPROVED | `CONTRACT_RENEW_POST` | Apply salary/current term and issue letter |
| Cancel | DRAFT/SUBMITTED/APPROVED | `CONTRACT_RENEW_CANCEL` | Terminal CANCELLED status |
| Back to List | Any | `CONTRACT_VIEW` | Page 520 |

For submit, process in this exact order:

1. Salary Interactive Grid Automatic Row Processing.
2. Recipient Interactive Grid Automatic Row Processing.
3. `SAVE_DRAFT` package call.
4. `SUBMIT_FOR_APPROVAL` package call.
5. Commit performed by APEX only after all processes succeed.

For Save, run steps 1-3. For Approve and Final Submit, no grid DML is allowed.
Use the package calls supplied in `page_521_contract_renewal_entry.sql`.

Final Submit must use a confirmation dialog showing old/new Basic, old/new gross
and effective date, plus the typed `P521_FINAL_CONFIRM` value. Hide the button
when the effective date is in the future and keep the database validation as the
authoritative check.

### Audit Timeline report

```sql
SELECT event_type,
       from_status,
       to_status,
       event_remarks,
       event_by,
       event_date
  FROM hr_contract_renewal_audit
 WHERE renewal_id = :P521_RENEWAL_ID
 ORDER BY audit_id DESC
```

## 7. Page 522 - Contract Renewal Letter

Create a minimal normal page named **Contract Renewal Letter**.

1. Add hidden items `P522_RENEWAL_ID` and `P522_COM_ID`.
2. Set both to **Value Protected = Yes** and require a session checksum on every link.
3. Add one PL/SQL Dynamic Content region using
   `page_522_contract_renewal_letter.sql`.
4. Add the `printContractLetter()` page JavaScript shown at the top of that
   file.
5. Use authorization `CONTRACT_VIEW` and an additional page-level Exists check:

```sql
SELECT 1
  FROM hr_contract_renewal r
  JOIN employees e ON e.id = r.emp_id
 WHERE r.renewal_id = TO_NUMBER(:P522_RENEWAL_ID)
   AND e.com_id = :P522_COM_ID
   AND r.approval_status IN ('APPROVED', 'POSTED')
```

The page reads only the protected renewal and company IDs. It resolves all
letter content server-side.
An approved-but-not-posted letter displays a clear pending-final watermark.
After final submit the letter status becomes `ISSUED` and the watermark is gone.

Use Bengali web fonts available to client browsers. If the application must
print identically on machines without those fonts, host a licensed WOFF2 font
inside APEX Static Application Files and declare it with `@font-face`.

## 8. Security and separation of duties

Create these APEX authorizations:

- `CONTRACT_VIEW`
- `CONTRACT_BASELINE_ADMIN` (may initialize a verified legacy contract)
- `CONTRACT_RENEW_CREATE`
- `CONTRACT_RENEW_EDIT`
- `CONTRACT_RENEW_SUBMIT`
- `CONTRACT_RENEW_APPROVE`
- `CONTRACT_RENEW_RETURN`
- `CONTRACT_RENEW_POST`
- `CONTRACT_RENEW_CANCEL`

Grant application users no direct table DML. Grant the APEX parsing schema
execute on `PKG_HR_CONTRACT_RENEWAL` and only the minimum query/DML needed by the
two draft Interactive Grids. Button visibility is convenience, not security;
the package rechecks status, locks rows and validates all sensitive values.

Production policy should assign submit and approve/post privileges to different
users. If strict maker-checker separation is required in the database, add a
package check that `SUBMITTED_BY <> P_USER_ID` in `APPROVE_RENEWAL` after user
IDs and emergency-override policy are formally defined.

## 9. Transaction and concurrency behavior

- No package procedure commits. APEX owns the transaction.
- `FOR UPDATE NOWAIT` protects renewal, contract and salary rows.
- Double-clicks and competing users receive a controlled error.
- Final submit begins a savepoint and rolls the full post back on any error.
- A stale salary or current-contract snapshot cannot overwrite newer payroll
  work.
- Approved future-effective renewals remain `APPROVED` until their effective
  date; Page 520 shows them as final-pending.

## 10. Deployment and UAT checklist

1. Back up the HRMS schema and deploy to a test environment.
2. Run `00_install.sql`; confirm no `USER_ERRORS`.
3. Verify signatory names/titles and default recipients.
4. Load current contract baselines or test the first-renewal baseline path.
5. Create APEX authorizations and Pages 520-522.
6. Run every scenario in `99_contract_renewal_checks.sql`.
7. Compare Page 522 print preview with the supplied PDF at A4 portrait, including
   a long employee address, seven conditions and five copy recipients.
8. Test Bengali rendering in every supported browser and PDF print driver.
9. Test maker-checker access with real application roles.
10. Only then grant `CONTRACT_RENEW_POST` in production.

## 11. Recommended acceptance criteria

- A due employee can be opened from Page 520 and drafted on Page 521.
- Exactly one open renewal per employee is possible.
- Grade/scale/step always produces the Basic shown on the letter.
- Approval creates one approved letter and never changes live salary.
- Page 522 reproduces the reference letter structure and copy list.
- Final submit before the effective date is rejected.
- Any live salary change after draft creation blocks posting.
- Successful final submit updates salary, current contract, employee grade,
  action, letter and audit trail together.
- A posted row has no edit, return, cancel or repost path in these pages.
