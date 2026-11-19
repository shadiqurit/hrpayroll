# Simple contract extension

**Select employee → enter extended confirmation date/reason → Save → List → Print.**

Only EMPLOYEES.CONFIRMATION_DUE_DATE changes. Every other employee field, salary,
benefit and contract record remains unchanged. Extension history records the old
and new date, reason and user/time.

## Build the three Oracle APEX pages

Follow [APEX_PAGE_BY_PAGE.md](APEX_PAGE_BY_PAGE.md) for exact items, SQL blocks,
dynamic action settings, the Save process and page links.

| Page | Purpose | Source |
|---|---|---|
| 523 | Extension list with New Extension and Print Letter | page_523_contract_extension_register.sql |
| 524 | Employee selection and one Save Extension button | page_524_contract_extension_entry.sql |
| 525 | A4 letter with Print and Back to List | page_525_contract_extension_letter.sql |

The user does not create/save drafts or perform a separate final submission.
The list shows completed extensions. The form has employee, new confirmation due
date, reason and a defaulted letter signatory; current employee/date are read-only.

## Database setup

The shared HR employee/action/letter/signatory infrastructure must already exist.
Run as HRMS in SQLcl/SQL*Plus from this folder:

```sql
-- New extension installation:
@00_install.sql
-- Or, update an existing installation:
@00_upgrade_dates_only.sql
```

For SQL Workshop script order, see the page-by-page guide. Run the database
update before using the new page snippets; it adds EXTEND_CONFIRMATION_DATE.
The package owns no commit. Its new Save API wraps date update, history and
letter generation in one savepoint; failure rolls the operation back entirely.
It checks the displayed old date under an employee lock before saving.

Unconfirmed probationary/contractual employees (EMP_TYPE 1/3) with an existing
confirmation due date are eligible; separated/confirmed employees are excluded.
The new date must be later. Extension does not set CONF_DATE or change employment
type/probation months. Internal start-date and salary columns/APIs remain only
for compatibility; the new UI exposes none of them. Old salary proposals are
ignored. Existing contracts are never read, created or updated by the package.

Use the existing CONTRACT_EXTEND_VIEW/EDIT/POST role schemes and authenticated
numeric USER_ID mapped to USERS_COMPANY.EMPID. Apply checks to processes and
links as described in the guide. Require an active letter signatory.

## Checks

Run 99_contract_extension_checks.sql after installation. In a disposable HRMS
database, use 98_test_contract_extension.sql employee_internal_id user_id. It
checks unchanged employee/contract/payroll data, extension history and letters,
stale-date/type/version protection and the one-Save API, including full rollback
on a letter-generation failure. All test DML rolls back; identity values are
consumed. Runtime tests need an HRMS database connection.
