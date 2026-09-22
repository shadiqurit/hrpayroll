# Easy Contract Renewal - Oracle APEX Pages 520, 521 and 522

This design has no approval workflow. The user works in one short flow:

```text
Page 520 Due Employees
    -> Prepare Renewal
    -> master and salary details generated automatically
    -> Page 521 review/adjust
    -> Final Submit
    -> Page 522 letter
```

Page 520 is the starting point. Page 521 does not create an empty renewal and
does not ask the user to select the employee again.

## 1. Pages

| Page | Name | Purpose |
|---:|---|---|
| 520 | Contract Renewal List | Shows due employees and generates the renewal master/detail |
| 521 | Renewal Master/Detail | Reviews or adjusts the generated contract and salary |
| 522 | Contract Renewal Letter | Shows and prints the final Bengali letter |

Only two statuses are used:

| Status | Meaning |
|---|---|
| `DRAFT` | Generated and editable; live salary has not changed |
| `POSTED` | Final; salary/contract updated and letter issued |

## 2. Master/detail generation

Clicking **Prepare Renewal** on Page 520 calls:

```plsql
HRMS.PKG_HR_CONTRACT_RENEWAL.CREATE_DUE_RENEWAL
```

The call generates both levels in one database transaction:

- one `HR_CONTRACT_RENEWAL` master row;
- one `HR_CONTRACT_RENEWAL_SALARY` detail row for every active employee salary
  component;
- employee, designation, department, location and company snapshots;
- current contract dates, grade, scale and step;
- new start date as current contract end date plus one day;
- new end date from the selected renewal term, normally 12 months;
- default letter template, signatory and copy recipients; and
- old/new Basic and gross totals.

For older `HR_EMPLOYEE_CONTRACT` rows with missing position data, preparation
derives and stores the values automatically:

- Grade: `HR_EMPLOYEE_CONTRACT.GRADE_ID`, otherwise `DESIGNATIONS.GRADE`,
  otherwise `EMPLOYEES.JOB_ID`.
- Scale: the active pay-scale revision for that grade and renewal date.
- Step: the configured scale position at or immediately below the employee's
  current Basic salary.

Preparation stops only when the employee has no usable grade, no active scale,
or no Basic salary row from which a step can be derived.

Only one draft is allowed for an employee. The Due Employees report hides an
employee after a draft has been generated.

## 3. Automatic and manual salary methods

Page 520 has one simple `P520_SALARY_MODE` radio group.

### Automatic increase

`AUTO` performs the following:

1. Keeps the employee's current grade and pay scale.
2. Finds the next configured step in `PAY_SCALE_DETAIL`.
3. Reads the new Basic from that step.
4. Copies all current salary rows into the renewal detail.
5. Recalculates salary heads configured in `PAY_SCALE_MASTER`.
6. Keeps every unconfigured salary head unchanged.

Configured automatic mapping:

| Head code | New amount |
|---|---|
| `001` | Basic from `PAY_SCALE_DETAIL` |
| `005` | Basic × `PAY_SCALE_MASTER.HR` percent |
| `013` | Basic × `PAY_SCALE_MASTER.PFCONT` percent |
| `057` | Basic × `PAY_SCALE_MASTER.CPF` percent |
| `007` | Configured `CONV` fixed amount |
| `010` | Configured `MEDICAL` fixed amount |
| `037` | Configured `ALLOWANCE` fixed amount |
| `075` | Configured `SAF` fixed amount |

If one of these pay-scale configuration values is null, the employee's current
amount is retained. If the employee is already at the highest step, Page 520
shows **Maximum step reached - use Manual adjustment**.

### Manual adjustment

`MANUAL` copies the current grade, scale, step and complete salary structure.
Page 521 then allows HR to:

- select another grade, scale or step;
- let the package calculate Basic from the selected step; and
- edit the proposed amount for every other salary head.

Old salary amounts are never editable.

The selected method is saved in `HR_CONTRACT_RENEWAL.SALARY_MODE` so Page 521
and the package use the same calculation rule.

## 4. Installation

For a new installation, run as the HRMS schema:

```sql
@00_install.sql
@99_contract_renewal_checks.sql
```

For an existing installation created from the earlier version, run:

```sql
@upgrade_easy_page_520.sql
@99_contract_renewal_checks.sql
```

The upgrade adds `SALARY_MODE` and recompiles the package. Do not continue if
`USER_ERRORS` contains package or trigger errors.

## 5. Page 520 - Due Employees

Create a normal page named **Contract Renewal List**.

### Page items

| Item | Type | Default |
|---|---|---|
| `P520_COM_ID` | Required company Select List | Authorized company |
| `P520_DUE_TO` | Date Picker | `TRUNC(SYSDATE)+90` |
| `P520_SALARY_MODE` | Radio Group | `AUTO` |
| `P520_TERM_MONTHS` | Select List | `12` |
| `P520_STATUS` | Select List | `ALL` |
| `P520_EMP_ID` | Hidden, not protected | — |
| `P520_RENEWAL_ID` | Hidden, Protected | — |

Use the two report queries and the `PREPARE_RENEWAL` process in
`page_520_contract_renewal_list.sql`.

The report button puts the numeric employee ID into `P520_EMP_ID` and submits
the page with request `PREPARE_RENEWAL`. The Page 520 process validates that the
employee belongs to the selected company and is still in the due list. After
generation, branch directly to Page 521 and pass `P521_RENEWAL_ID` and
`P521_COM_ID`.

All package calls use the application's numeric authenticated-user session item
`:USER_ID`. Ensure it is populated at login. Do not use `:G_USER_ID` unless that
item actually exists and is populated in your application.

There is no **New Renewal** button. The user clicks **Prepare** on a due employee.

## 6. Page 521 - Generated master/detail

Create a normal page named **Renewal Master/Detail**. It must be opened with an
existing `P521_RENEWAL_ID` generated by Page 520.

Show these generated master values as read-only:

- employee identity and organization;
- current contract dates, grade, scale and step;
- old Basic and gross;
- salary method and status.

Allow these values to be edited only while status is `DRAFT`:

- new contract end date;
- new grade, scale and step;
- reason, remarks and special terms;
- signatory and letter template; and
- allowed proposed salary amounts.

The new start date is display-only because it must always be the day after the
current contract ends.

Use an editable Interactive Grid for `HR_CONTRACT_RENEWAL_SALARY`:

- update only; no row insert or delete;
- `OLD_AMOUNT` is always read-only;
- Basic is always package calculated;
- known formula/fixed heads are also read-only in `AUTO` mode;
- non-Basic amounts are editable in `MANUAL` mode.

Use the item, LOV, grid and process definitions in
`page_521_contract_renewal_entry.sql`.

Page 521 needs only these buttons:

| Button | Result |
|---|---|
| Save Draft | Saves the grid/header and recalculates totals |
| Refresh Salary | Discards the proposal and copies live salary again |
| Final Submit | Updates live records and generates the letter |
| Delete Draft | Removes an unwanted generated draft |
| View Letter | Opens Page 522 after posting |
| Back | Returns to Page 520 |

For Save Draft and Final Submit, process in this order:

1. Salary Interactive Grid Automatic Row Processing.
2. `PKG_HR_CONTRACT_RENEWAL.SAVE_DRAFT`.
3. `PKG_HR_CONTRACT_RENEWAL.FINAL_SUBMIT` for Final Submit only.

## 7. Final Submit

Final Submit runs in one transaction and:

- creates the employee action;
- updates `EMP_SALARY_STRUCTURE` from the proposed detail rows;
- updates the current contract dates, grade, scale and step;
- updates the employee grade;
- generates an issued letter;
- marks detail rows posted; and
- changes the master status to `POSTED`.

If any operation fails, everything rolls back. A posted renewal cannot be
edited, deleted, or posted again.

## 8. Page 522

Page 522 remains a simple printable letter page. Use the PL/SQL Dynamic Content,
CSS and JavaScript in `page_522_contract_renewal_letter.sql`.

It only displays a renewal when:

```sql
r.status = 'POSTED'
```

## 9. Required APEX authorizations

- `CONTRACT_VIEW`
- `CONTRACT_RENEW_EDIT`
- `CONTRACT_RENEW_POST`

`CONTRACT_BASELINE_ADMIN` is no longer part of the normal Page 520 flow because
the due list only shows employees with an active `HR_EMPLOYEE_CONTRACT` row.

## 10. Minimum tests

1. Choose `AUTO` and prepare a due employee; confirm one master and all salary
   detail rows are created.
2. Confirm the step advances and Basic matches `PAY_SCALE_DETAIL`.
3. Confirm configured salary heads recalculate and other heads remain unchanged.
4. Choose `MANUAL`; confirm current values are copied and non-Basic amounts can
   be edited on Page 521.
5. Final Submit and confirm salary, contract, action and letter are updated.
6. Confirm an employee at maximum step cannot use `AUTO` but can use `MANUAL`.
7. Confirm a second draft cannot be generated for the same employee.
8. Confirm a posted renewal is read-only and Page 522 prints correctly.
