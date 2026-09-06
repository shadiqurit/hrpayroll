# Promotion final submit in Oracle APEX

The implementation uses the tables already present in this project:
`HR_EMPLOYEE_PROMOTION`, `HR_PROMOTION_SALARY_DTL`,
`EMP_SALARY_STRUCTURE`, `EMP_SALARY_STRUCTURE_HIST`,
`HR_EMPLOYEE_ACTION`, `HR_EMPLOYEE_CAREER_HIST`, and
`HR_EMPLOYEE_LETTER`.

`PKG_HR_PROMOTION.SUBMIT_AND_POST` performs the whole final action in one APEX
transaction:

1. Locks and validates the DRAFT promotion, employee, and current salary.
2. Rejects stale or future-dated data.
3. Creates the employee action and career history.
4. Sets the promotion reference for `TRG_EMP_SAL_STRUCT_HIST`; that trigger
   automatically records every promoted salary head in history with type `P`
   and remarks beginning `[PROMOTION:<promotion_no>]`.
5. Makes `EMP_SALARY_STRUCTURE` match the complete generated promotion detail:
   supplied heads are updated/inserted and omitted active heads are archived
   and deactivated, all with revision type `P`.
6. Updates the employee's promoted job/designation/department/type.
7. Marks the promotion and salary detail rows posted.
8. Generates one issued promotion letter containing the subject and narrative.
   Page 483 inserts the headwise comparison from promotion detail and history.

The package contains no `COMMIT`; APEX commits only when the complete page
request succeeds.

## Install

Run these scripts in this order after the existing promotion tables and letter
tables are installed:

1. `Table/hr_employee_action_promotion_columns.sql`
2. `Table/hr_action_type_promotion.sql`
3. `Table/hr_letter_template.sql` for a new installation, or
   `promotion/update_promotion_letter_template.sql` to insert/update the
   template in an existing database
4. `Table/trg_emp_salary_structure.sql`
5. `promotion/pkg_hr_promotion.sql`

The supplied table scripts exist in two forms in this repository. Confirm that
the deployed `HR_EMPLOYEE_PROMOTION` includes `NEW_JOB_ID`; the package supports
it being nullable but expects the column to exist.

## APEX final-submit process

Keep the normal Form/Interactive Grid DML processes first so all draft edits
are saved before this process. On page 477, add this **After Submit** PL/SQL
process:

```plsql
HRMS.pkg_hr_promotion.submit_and_post(
    p_promotion_id => :P477_PROMOTION_ID,
    p_user_id      => :G_USER_ID
);
```

Use the numeric authenticated user/employee ID session item for `G_USER_ID`.
This is an application-level item, not another page-477 item. Do not pass a
text username into the numeric audit columns.

The shorter package overload automatically selects the active
`PROMOTION_DEFAULT` template. The five-parameter overload is available only
when another page needs to choose a template or receive the generated action
and letter IDs immediately.

Configure the button and process as follows:

- Button name/request: `SUBMIT_PROMOTION`; action: **Submit Page**.
- Confirmation: `Submit and post this promotion to the employee salary?`
- Server-side process condition: Request = `SUBMIT_PROMOTION`.
- Show the button only when this **Rows returned** condition succeeds:

```sql
select 1
  from hr_employee_promotion
 where promotion_id = :P477_PROMOTION_ID
   and approval_status = 'DRAFT'
```

- Make the header and detail grid read-only for `POSTED` rows.
- Success message: `Promotion posted and letter generated.`
- Add a success branch to page 483, clear page 483 cache, and pass
  `P483_PROMOTION_ID = &P477_PROMOTION_ID.`.

The button performs a final post, so the resulting status is `POSTED`, not
`SUBMITTED`. This is intentional because the live salary and employee record
have already changed. If the business needs checker/approver stages, call this
package only from the final **Post** button; an earlier Submit button should
only change `DRAFT` to `SUBMITTED` and must not touch live salary.

## Page 483: Promotion Letter

Create a Blank Page numbered 483 with the title **Promotion Letter**.

1. Create hidden item `P483_PROMOTION_ID` with Value Protected = Yes.
2. Create a PL/SQL Dynamic Content region named **Promotion Letter**.
3. Paste `promotion/page_483_promotion_letter.sql` into its source.
4. Use no page template printer mode; the region already contains A4 print CSS
   and a Print Promotion Letter button.
5. Apply the normal HR letter authorization scheme to the page.

Set the region server-side condition to **Rows returned**:

```sql
select 1
  from hr_employee_promotion p
       join hr_employee_letter l on l.promotion_id = p.promotion_id
 where p.promotion_id = :P483_PROMOTION_ID
   and p.approval_status = 'POSTED'
   and l.status <> 'CANCELLED'
```

Page 483 needs no action ID, letter ID, template ID, employee ID, or salary page
items. `P483_PROMOTION_ID` resolves the submitted promotion, its issued letter,
company header, subject, and narrative body. New salary comes from
`HR_PROMOTION_SALARY_DTL`; old salary comes from the trigger-created
`EMP_SALARY_STRUCTURE_HIST` rows referenced by promotion number.

The default template supports these replacement tokens:

- `#EMP_NAME#`, `#EMP_CODE#`, `#PROMOTION_TYPE#`
- `#OLD_DESIGNATION#`, `#NEW_DESIGNATION#`, `#DEPARTMENT#`
- `#EFFECTIVE_DATE#`, `#LETTER_DATE#`
- `#SALARY_DETAILS#`, which page 483 replaces with the database comparison

The default narrative stores no salary amounts in `BODY_HTML`. Salary values
are read when page 483 renders: after-promotion values come from promotion
detail and before-promotion values come from referenced salary history.

If the installed template does not contain `#SALARY_DETAILS#`, the package
automatically appends that marker. No salary rows or amounts are stored in
`BODY_HTML`; page 483 replaces the marker with the current referenced detail
and history comparison when rendering.

Salary heads `025` and `026` are displayed with their codes and are included
in the before-promotion, promotion-change, after-promotion, and gross-total
calculations.

## Required tests

- Submit the same promotion from two browser sessions: only one may post.
- Change Basic Salary after generating a draft: final submit must require
  regeneration. A draft `OLD_GROSS` difference alone does not block posting;
  gross is recalculated from the locked live structure.
- Try a future effective date: it must be rejected because the live salary table
  has no effective-from/effective-to columns.
- Verify the trigger creates one referenced history row per promoted salary
  head with revision type `P` and remarks starting with the promotion number.
- Verify the generated letter totals match the promotion and live salary.
- Force a template error and confirm no employee, salary, action, or promotion
  changes remain after the failed request.

`OLD_GROSS` on the draft header is not used as a posting gate. At final submit,
the package calculates old gross from locked live salary rows, applies the
complete promotion detail, lets `TRG_EMP_SAL_STRUCT_HIST` capture old/new
amounts, recalculates new gross, and stores both header totals. The package does
not insert `EMP_SALARY_STRUCTURE_HIST` directly.
