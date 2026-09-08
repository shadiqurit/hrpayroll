# Promotion final submit in Oracle APEX

The implementation uses the tables already present in this project:
`HR_EMPLOYEE_PROMOTION`, `HR_PROMOTION_SALARY_DTL`,
`EMP_SALARY_STRUCTURE`, `EMP_SALARY_STRUCTURE_HIST`,
`HR_EMPLOYEE_ACTION`, `HR_EMPLOYEE_CAREER_HIST`, and
`HR_EMPLOYEE_LETTER`. Promotion-letter configuration uses
`HR_LETTER_SIGNATORY`, `HR_LETTER_RECIPIENT`, and
`HR_PROMOTION_LETTER_RECIPIENT`.

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
8. Selects the letter language from the promoted grade order: English for
   grades 1-14 and Bengali for grades 15-20.
9. Generates one issued promotion letter containing the subject and narrative.
   Page 483 inserts a confirmation-letter-style promoted salary breakdown.

The package contains no `COMMIT`; APEX commits only when the complete page
request succeeds.

## Install

Run these scripts in this order after the existing promotion tables and letter
tables are installed:

1. `Table/hr_employee_action_promotion_columns.sql`
2. `Table/hr_action_type_promotion.sql`
3. `Table/hr_letter_template.sql` when the letter-template table is not yet
   installed
4. `promotion/update_promotion_letter_template.sql` in every environment; it
   upserts `PROMOTION_EN` and `PROMOTION_BN`
5. `functions/f_inword_tk.fnc`
6. `functions/f_inword_tk_bn.fnc`
7. `promotion/hr_promotion_letter_configuration.sql`; it creates the signatory
   and fixed-recipient masters, adds `SIGNATORY_ID`, and creates/upgrades the
   promotion-specific TO/COPY table
8. `Table/trg_emp_salary_structure.sql`
9. `promotion/pkg_hr_promotion.sql`

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
    p_user_id      => :USER_ID
);
```

Use the numeric authenticated user/employee ID session item for `USER_ID`.
This is an application-level item, not another page-477 item. Do not pass a
text username into the numeric audit columns.

The shorter package overload automatically selects active template
`PROMOTION_EN` for promoted grade order 1-14 or `PROMOTION_BN` for promoted
grade order 15-20. The five-parameter overload is available only when another
page needs to override that template or receive generated IDs immediately.

### Page 477 signatory and recipient LOV setup

Add `P477_SIGNATORY_ID` to the promotion form, mapped to database column
`HR_EMPLOYEE_PROMOTION.SIGNATORY_ID`. Use this Select List LOV:

```sql
select replace(signatory_code, '_', ' ') || ' - ' || name_en
       || ' (' || title_en || ')' d,
       signatory_id r
  from hr_letter_signatory
 where is_active = 'Y'
 order by display_order, signatory_id
```

Make the item required. For a new promotion, its SQL Query default can be:

```sql
select signatory_id
  from hr_letter_signatory
 where signatory_code = 'MD'
   and is_active = 'Y'
```

Maintain reusable fixed recipients on a separate administration page using an
editable Interactive Grid sourced from:

```sql
select letter_recipient_id,
       recipient_code,
       recipient_name_en,
       recipient_name_bn,
       display_order,
       is_active
  from hr_letter_recipient
 order by display_order, letter_recipient_id
```

`LETTER_RECIPIENT_ID` is the generated primary key. Make
`RECIPIENT_NAME_EN`, `DISPLAY_ORDER`, and `IS_ACTIVE` required. Bengali print
uses `RECIPIENT_NAME_BN` when present and otherwise falls back to the English
name. Deactivate a recipient that is no longer selectable; do not delete a
master row already referenced by a promotion.

The migration seeds these seven standard copy recipients from the approved
letter: Head of Sales; DGM, Operations (Sales); DGM, Monitoring (Sales);
Accounts Department (Pay-Roll Section); Officer Responsible for Software Data
Entry; Personal File; and Office Copy. The seed is insert-only, so later
administrator edits are not overwritten when the migration is rerun.

On Page 477, add an editable Interactive Grid named **Letter Recipients**. Only
the recipient LOV is editable; use this source:

```sql
select recipient_id,
       promotion_id,
       letter_recipient_id
  from hr_promotion_letter_recipient
 where promotion_id = :P477_PROMOTION_ID
   and section_type = 'COPY'
   and letter_recipient_id is not null
```

- `RECIPIENT_ID`: Primary Key, hidden.
- `PROMOTION_ID`: hidden; default `P477_PROMOTION_ID`.
- `LETTER_RECIPIENT_ID`: required Select List using the LOV below. This is the
  only visible/editable column.
- Do not add `SECTION_TYPE`, `LINE_TEXT`, `DISPLAY_ORDER`, or `IS_ACTIVE` to the
  Page 477 region. New rows receive `COPY` and `Y` database defaults, and Page
  483 uses the master recipient's `DISPLAY_ORDER`.
- Enable Add Row and Delete Row so multiple recipients can be selected.
- Put the grid Automatic Row Processing before the final
  `PKG_HR_PROMOTION.SUBMIT_AND_POST` process.
- Make the signatory item and this grid read-only after status becomes `POSTED`.
- After running the configuration migration, synchronize the Page 477 form
  region so APEX recognizes the new `SIGNATORY_ID` database column.

Fixed-recipient Select List LOV:

```sql
select recipient_name_en
       || case
              when recipient_name_bn is not null
                  then ' / ' || recipient_name_bn
          end d,
       letter_recipient_id r
  from hr_letter_recipient
 where is_active = 'Y'
 order by display_order, letter_recipient_id
```

Set **Display Null Value = Yes**, Null Display Value = `- Select Recipient -`,
and **Value Required = Yes**. Keep **Display Extra Values = Yes** so an existing
selection remains readable if its master record is later deactivated.

Page 477 recipient selections are the complete copy list; zero rows means no
copy section. The employee and old designation remain the letter's generated
`To` address. Final submit rejects a missing/inactive signatory or an inactive
selected recipient. Disabling a master recipient later does not remove it from
an already-posted letter.

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
4. Use no page template printer mode; the region contains A4 print CSS and a
   language-aware Print button. It is designed for the pre-printed company
   letterhead, so it reserves 30 mm at the top and does not print the IBN/SINA
   logo text, company-name banner, or `Quality We Assure` tagline.
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

Page 483 needs no action ID, letter ID, template ID, employee ID, grade, or
salary page items. `P483_PROMOTION_ID` resolves the submitted promotion, its
promoted grade, issued letter, subject, signatory, TO/COPY entries, and narrative body. The
salary list comes from the earning rows in `HR_PROMOTION_SALARY_DTL`. Old salary
history remains available for audit/posting but is not printed in the letter.
The database/application character set must support Unicode; AL32UTF8 is
recommended for the Bengali template and Bengali amount-in-words function.

The promotion templates support these replacement tokens:

- `#EMP_NAME#`, `#EMP_CODE#`, `#PROMOTION_TYPE#`
- `#OLD_DESIGNATION#`, `#NEW_DESIGNATION#`, `#DEPARTMENT#`
- `#LOCATION#`, `#COMPANY_NAME#`, `#COMPANY_NAME_BN#`, `#GRADE#`, `#GRADE_BN#`
- `#PAY_SCALE#`, `#PAY_SCALE_BN#`
- `#EFFECTIVE_DATE#`, `#EFFECTIVE_DATE_BN#`, `#LETTER_DATE#`
- `#SALARY_DETAILS#`, which page 483 replaces with the promoted salary list

The template narrative stores no salary amounts in `BODY_HTML`. Salary values
are read from promotion detail when Page 483 renders.

If the installed template does not contain `#SALARY_DETAILS#`, the package
automatically appends that marker. No salary rows or amounts are stored in
`BODY_HTML`; Page 483 replaces the marker with a borderless `head : amount`
salary breakdown when rendering.

Salary heads `025` and `026` are never filtered from Page 483. Like the
confirmation letter, Page 483 shows earning salary rows as salary-head name,
colon, and promoted amount, followed by the total and amount in words. There is
no comparison table in the printed letter.

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
- Select each of MD, ED, and ED Plants and verify the corresponding bilingual
  name/title prints.
- Select fixed recipients, add an Others/custom recipient, then deactivate and
  reorder TO/COPY rows; verify Page 483 prints exactly the active rows in
  display order and uses the Bengali master name for grades 15-20.
- Force a template error and confirm no employee, salary, action, or promotion
  changes remain after the failed request.

`OLD_GROSS` on the draft header is not used as a posting gate. At final submit,
the package calculates old gross from locked live salary rows, applies the
complete promotion detail, lets `TRG_EMP_SAL_STRUCT_HIST` capture old/new
amounts, recalculates new gross, and stores both header totals. The package does
not insert `EMP_SALARY_STRUCTURE_HIST` directly.
