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
4. Copies every changed salary head to salary history.
5. Updates/inserts the generated heads in `EMP_SALARY_STRUCTURE` with revision
   type `P`; salary heads not supplied by the promotion remain unchanged.
6. Updates the employee's promoted job/designation/department/type.
7. Marks the promotion and salary detail rows posted.
8. Generates one promotion letter containing old, increment, and new salary.

The package contains no `COMMIT`; APEX commits only when the complete page
request succeeds.

## Install

Run these scripts in this order after the existing promotion tables and letter
tables are installed:

1. `Table/hr_employee_action_promotion_columns.sql`
2. `Table/hr_action_type_promotion.sql`
3. `Table/hr_letter_template.sql` (or update the existing promotion template)
4. `promotion/pkg_hr_promotion.sql`

The supplied table scripts exist in two forms in this repository. Confirm that
the deployed `HR_EMPLOYEE_PROMOTION` includes `NEW_JOB_ID`; the package supports
it being nullable but expects the column to exist.

## APEX final-submit process

Keep the normal Form/Interactive Grid DML processes first so all draft edits
are saved before this process. Add hidden page items for the returned action
and letter IDs, then add an **After Submit** PL/SQL process:

```plsql
HRMS.pkg_hr_promotion.submit_and_post(
    p_promotion_id => :PXX_PROMOTION_ID,
    p_user_id      => :G_USER_ID,
    p_template_id  => :PXX_TEMPLATE_ID,
    p_action_id    => :PXX_ACTION_ID,
    p_letter_id    => :PXX_LETTER_ID
);
```

Use the numeric authenticated user/employee ID session item for `G_USER_ID`.
Do not pass a text username into the numeric audit columns.

Configure the button and process as follows:

- Button name/request: `SUBMIT_PROMOTION`; action: **Submit Page**.
- Confirmation: `Submit and post this promotion to the employee salary?`
- Server-side process condition: Request = `SUBMIT_PROMOTION`.
- Show the button only for `PXX_APPROVAL_STATUS = DRAFT`.
- Make the header and detail grid read-only for `POSTED` rows.
- Success message: `Promotion posted and letter generated.`
- Branch to the promotion-letter page and pass its hidden letter item from
  `PXX_LETTER_ID`.

The button performs a final post, so the resulting status is `POSTED`, not
`SUBMITTED`. This is intentional because the live salary and employee record
have already changed. If the business needs checker/approver stages, call this
package only from the final **Post** button; an earlier Submit button should
only change `DRAFT` to `SUBMITTED` and must not touch live salary.

## Letter page

Create a Blank APEX page with a protected hidden item such as
`P510_LETTER_ID`. Add a **PL/SQL Dynamic Content** region and paste
`page_promotion_letter_dynamic_content.sql`, replacing `PXXX_LETTER_ID` with
the actual item. The region renders the generated `BODY_HTML` and includes a
print button.

The default template supports these replacement tokens:

- `#EMP_NAME#`, `#EMP_CODE#`, `#PROMOTION_TYPE#`
- `#OLD_DESIGNATION#`, `#NEW_DESIGNATION#`, `#DEPARTMENT#`
- `#EFFECTIVE_DATE#`, `#LETTER_DATE#`
- `#OLD_BASIC#`, `#INCREMENT_AMOUNT#`, `#INCREMENT_PERCENT#`, `#NEW_BASIC#`
- `#OLD_GROSS#`, `#NEW_GROSS#`, `#SALARY_DETAILS#`

If the installed template does not contain `#SALARY_DETAILS#`, the package
automatically appends the salary table, so existing installations still show
the old/increment/new salary breakdown.

## Required tests

- Submit the same promotion from two browser sessions: only one may post.
- Change salary after generating a draft: final submit must require regeneration.
- Try a future effective date: it must be rejected because the live salary table
  has no effective-from/effective-to columns.
- Verify one history row per promoted salary head and revision type `P`.
- Verify the generated letter totals match the promotion and live salary.
- Force a template error and confirm no employee, salary, action, or promotion
  changes remain after the failed request.
