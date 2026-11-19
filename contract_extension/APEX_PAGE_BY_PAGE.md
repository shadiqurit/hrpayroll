# Contract Extension: Oracle APEX page-by-page setup

The user selects an employee, enters a new confirmation due date and reason,
clicks **Save Extension**, then prints the letter from the list.
Only EMPLOYEES.CONFIRMATION_DUE_DATE changes. The history records the old/new
date, reason and user/time. Salary, other employee fields and contracts stay unchanged.

| Page | Name | User action |
|---|---|---|
| 523 | Contract Extension List | New Extension or Print Letter |
| 524 | New Contract Extension | Select employee, enter new due date/reason, Save Extension |
| 525 | Contract Extension Letter | Print or Back to List |

There is no user-visible draft, separate final submission, salary section or
approval page. Save records the extension and generates its letter together.

## 1. Prepare the database

Use the existing HR application with Parsing Schema **HRMS**, its authenticated
numeric USER_ID application item, USERS_COMPANY access mapping, and shared
employee/action/letter/signatory tables. At least one letter signatory must be active.

In **SQL Workshop → SQL Scripts**, run the complete database scripts in this order:

| Installation | Scripts, in order |
|---|---|
| New extension module | 01_contract_extension_tables.sql → 02_contract_extension_letter_config.sql → 04_contract_extension_views.sql → 03_pkg_hr_contract_extension.sql → 99_contract_extension_checks.sql |
| Existing extension module | 02_contract_extension_letter_config.sql → 04_contract_extension_views.sql → 03_pkg_hr_contract_extension.sql → 99_contract_extension_checks.sql |

For SQLcl/SQL*Plus, run 00_install.sql for a new installation or
00_upgrade_dates_only.sql for an existing one from this folder. Those two files
use @@ include commands; do not paste them as Page Designer source.
Check USER_ERRORS for compilation errors before building the pages.

Reuse the application's role rules for these authorization schemes:
CONTRACT_EXTEND_VIEW (list/letter), CONTRACT_EXTEND_EDIT (entry),
CONTRACT_EXTEND_POST (Save button and process). Authenticated USER_ID must be
server-controlled. Never replace the company checks with a browser-supplied user ID.

## 2. Page 523 — Contract Extension List

1. In App Builder, create a **Blank Page**, number **523**, Normal page mode,
   name **Contract Extension List**. Add it to the application navigation menu.
   Set Authorization Scheme to CONTRACT_EXTEND_VIEW.
2. Add P523_COM_ID as a required **Select List**, label **Company**.
   Copy the company LOV SELECT from
   [page_523_contract_extension_register.sql](page_523_contract_extension_register.sql).
   Set Page Action on Selection to **Submit Page**. There are no save processes
   on Page 523. An unselected company returns no report rows.
3. Add one **Interactive Report** region, title **Extensions**, Static ID
   **extension_list**. Copy only the report SELECT under “Region: Extensions”
   from the same file. Set Page Items to Submit to P523_COM_ID.
4. Set these report headings and formats:

   | Column | Heading / setting |
   |---|---|
   | EXTENSION_NO | Reference |
   | EMPLOYEE_CODE | Employee ID |
   | EMPLOYEE_NAME | Employee |
   | PREVIOUS_CONFIRMATION_DUE_DATE | Previous Confirmation Date; DD-MON-YYYY |
   | EXTENDED_CONFIRMATION_DUE_DATE | Extended Confirmation Date; DD-MON-YYYY |
   | REASON | Reason |
   | RECORDED_DATE | Recorded On; DD-MON-YYYY HH24:MI |
   | RECORDED_BY | Recorded By; optional visible column |
   | PRINT_URL | Link column; Link Text **Print Letter**, Target Type URL, URL **#PRINT_URL#** |

   Keep ordinary employee/reason text escaped. Set the link through column
   attributes, not an unescaped HTML expression. Save the desired default report.
5. Add button **NEW_EXTENSION**, label **New Extension**, Authorization Scheme
   CONTRACT_EXTEND_EDIT. Action **Redirect to Page in this Application**:
   page 524, Clear Cache 524, Set Items P524_COM_ID, With Values &P523_COM_ID.
   Show the button only when P523_COM_ID is not null.

The SQL shows only completed extensions. No due-date filter, term-month selector,
Prepare action, draft status filter or edit link is needed.

## 3. Page 524 — New Contract Extension

1. Create **Blank Page 524**, Normal page mode, name **New Contract Extension**.
   Set Authorization Scheme to CONTRACT_EXTEND_EDIT. Do not use an automatic
   table form or automatic row processing.
2. Add one **Static Content** region named **Contract Extension**. Add these items:

   | Item | Type | Required | Label / setting |
   |---|---|---|---|
   | P524_COM_ID | Hidden | — | Passed from Page 523; protected |
   | P524_EXTENSION_ID | Hidden | — | Protected, initially null; output of Save |
   | P524_EMP_ID | Popup LOV | Yes | Employee |
   | P524_EMP_NAME | Display Only | — | Employee Name |
   | P524_CURRENT_TO_DATE | Display Only | — | Current Confirmation Due Date; retain/send session state |
   | P524_NEW_TO_DATE | Date Picker | Yes | Extended Confirmation Due Date; DD-MON-YYYY |
   | P524_REASON | Textarea | Yes | Reason; maximum 1000 characters |
   | P524_SIGNATORY_ID | Select List | Yes | Letter Signatory |

   Set the current displayed date format to DD-MON-YYYY. Use the Display Only
   item's Save Session State / Send on Page Submit setting so Save receives the
   date loaded by the dynamic action. Do not give it a source that overwrites
   the loaded value on submit. No automatic form initialization is needed.
3. For P524_EMP_ID, copy the **Employee Popup LOV** SELECT from
   [page_524_contract_extension_entry.sql](page_524_contract_extension_entry.sql).
   Set Items to Submit to P524_COM_ID. The LOV lists authorized employees who
   are awaiting confirmation and already have a confirmation due date.
4. Create dynamic action **LOAD_EMPLOYEE** on Change of P524_EMP_ID.
   Add True Action **Execute Server-side Code**, Wait for Result Yes, Fire on
   Initialization No. Copy the LOAD_EMPLOYEE PL/SQL block from the entry file.

   - Items to Submit: P524_EMP_ID,P524_COM_ID.
   - Items to Return: P524_EMP_NAME,P524_CURRENT_TO_DATE,P524_NEW_TO_DATE.

   Selecting or clearing an employee resets the old displayed date and clears
   the new date. HR must enter the extended date explicitly.
5. For P524_SIGNATORY_ID, copy the signatory LOV SELECT from the entry file.
   Set Default Type **SQL Query**, using its following single-value default
   query. The first active signatory is selected automatically.
6. Add button **SAVE_EXTENSION**, label **Save Extension**.
   Set Action **Submit Page**, Show Processing Yes, Execute Validations Yes,
   Authorization Scheme CONTRACT_EXTEND_POST. Add **CANCEL** as a redirect to
   Page 523, Clear Cache 523, Set P523_COM_ID = &P524_COM_ID.; it must not submit.
7. In the Processing tab, add **one Execute Code process** named SAVE_EXTENSION,
   sequence 10, point Processing. Set **When Button Pressed = SAVE_EXTENSION**
   and Authorization Scheme CONTRACT_EXTEND_POST. Paste only the complete
   SAVE_EXTENSION DECLARE ... END; block from the entry file.
   Set Success Message to **Extension saved. Select Print Letter from the list.**

   That process calls EXTEND_CONFIRMATION_DATE. The package validates the old
   date, saves the new date/history and generates the letter in one transaction.
   If any step fails, it rolls back all its changes. Do not add COMMIT or catch
   and suppress its exception. The new date must be later than the old date.
8. Add an **After Processing branch** for button SAVE_EXTENSION to Page 523.
   Set P523_COM_ID = &P524_COM_ID. and Clear Cache **523,524**. Preserve the process
   success message if that option is available. Validation/process errors stay
   on the entry page; a successful Save returns to the list.

**Visible input is only employee, extended date, reason and letter signatory.**
The current date/name are display-only. Do not add start dates, salary controls,
grade, probation months, remarks, draft/save-final buttons or approval controls.

## 4. Page 525 — Contract Extension Letter

1. Create **Blank Page 525**, Normal page mode, name **Contract Extension Letter**,
   using Blank with Attributes or another minimal page template.
   Set Authorization Scheme to CONTRACT_EXTEND_VIEW.
2. Add hidden items P525_EXTENSION_ID and P525_COM_ID. Links from the report pass
   these values. Enable page/item session checksum protection for linked values;
   do not use a setting that forbids all URL assignment.
3. Add an **HTP-based PL/SQL Dynamic Content** region (labelled Legacy in newer
   APEX releases). Paste the complete DECLARE ... END; renderer from
   [page_525_contract_extension_letter.sql](page_525_contract_extension_letter.sql).
   This source uses HTP.P/PRN; do not paste it into a CLOB-returning Dynamic Content
   region. Use a region template without a visible header or border.
4. Under Page → JavaScript → Function and Global Variable Declaration, add:

   ```javascript
   function printContractLetter() { window.print(); }
   ```

5. The region already contains **Back to List** and **Print Contract Extension
   Letter** buttons. There are no page submit processes. The print CSS hides the
   toolbar and APEX interface, showing the A4 letter only. Select A4 in the browser
   print dialog and disable browser headers/footers if they appear.

The new letter shows the employee, old/new confirmation date and unchanged salary,
benefits and other terms. Internal reason notes stay in the extension list.
Historical letters retain their saved body and any legacy salary display.

## 5. Replace an older page setup

Remove the old due-employees region/Prepare action on Page 523. On Page 524 remove
old buttons, processes, branches and dynamic actions before adding the new ones:
CREATE_DRAFT, VALIDATE_AND_LOCK, salary grid DML, SAVE_HEADER, FINAL_SUBMIT,
REFRESH_SALARY, DELETE_DRAFT and existing-record loading. Keep only the items
listed above. No posted history or employee/payroll data needs to be deleted.

If old DRAFT rows exist, resolve them before switching: the new form deliberately
excludes those employees. An authorized administrator can remove a reviewed draft
with PKG_HR_CONTRACT_EXTENSION.DELETE_DRAFT(extension_id, authenticated_user_id)
in their own transaction. Never delete a posted extension.

## 6. Verify the flow

Run Page 523 → choose company → New Extension → choose employee → enter later
confirmation due date and reason → Save Extension. The entry should appear at
the top of Page 523. Open Print Letter → preview A4 → Back to List.

Check that only EMPLOYEES.CONFIRMATION_DUE_DATE changed; all other employee,
contract and payroll data must match their previous values. A failed Save must
leave no date update, extension, action or letter. The regression script
98_test_contract_extension.sql covers this in a disposable HRMS database,
including stale dates and rollback if letter generation fails.

## Oracle references

[Oracle: managing buttons and submit/redirect actions](https://docs.oracle.com/en/database/oracle/apex/26.1/htmdb/creating-buttons.html).
[Oracle: rendering HTML with the PL/SQL Web Toolkit](https://docs.oracle.com/en/database/oracle/apex/24.2/htmdb/rendering-html-using-custom-plsql.html).
