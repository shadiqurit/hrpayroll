# Contract extension — separate from contract renewal

| Module | Pages | Rule |
|---|---|---|
| Existing contract renewal | 520 / 521 / 522 | Existing benefit and salary-increase rules remain in contractual/ |
| Contract extension | 523 / 524 / 525 | Extend the term; grant no automatic increase or benefit |

The original renewal sources have been restored. This folder adds the separate
extension module, with its own package, tables, action type, letter templates,
number sequence and page items.

## Three simple pages

| Page | Name | Layout and actions |
|---:|---|---|
| 523 | Contract Extension Register | Company/due-date filters, due employees, extension register, Prepare Extension, New Extension |
| 524 | Contract Extension Entry | Employee/current term, extended dates, optional manual amounts, additional terms/signatory; Save Draft and Final Submit |
| 525 | Contract Extension Letter | Same A4 letter layout as renewal; view and print |

Use the same Universal Theme page, region and button templates as Pages
520–522. On Page 524 use three regions: **Employee and Current Contract**,
**Extension Details**, and a collapsible **Manual Changes (Optional)** salary
grid. Keep the new end date, reason and additional terms in Extension Details.
Show totals as display-only items. No salary method, grade, scale or step selector.

Flow: Register → Prepare/New Extension → Entry → Final Submit → Letter.
Only DRAFT and POSTED statuses; no approval workflow.

## Extension rules

- Probationary (EMP_TYPE = 1) and contractual (EMP_TYPE = 3) employees are eligible.
- Grade, non-grade, scale, step and salary structure do not determine eligibility.
- Current salary amounts are copied exactly. No increment, step advancement,
  allowance, bonus, leave entitlement or other benefit is granted automatically.
- Any exception/change must be entered manually by HR, including Basic or a new
  salary head. Leave/bonus settings in other modules require their own manual entry.
- Existing benefits continue unless HR explicitly changes them.
- New start is current end + 1 day; HR enters the new end date.
- For a first probation extension, use JOIN_DATE / CONFIRMATION_DUE_DATE.
  For a contractual employee without recorded dates, use New Extension and enter
  the current term manually.
- Posting a probation extension updates CONFIRMATION_DUE_DATE, retaining the
  probation category. Extension is not employment confirmation.
- Future terms can be saved as drafts; post on/after the extended start date,
  because manually entered payroll changes are applied immediately.
- A posted extension is read-only. Unchanged salary rows are never updated.
- The letter states that extension grants no automatic benefit. Additional terms
  are plain text, escaped for printing. New letters use the English extension
  template for every grade and non-grade employee.

Both modules use the existing HR_EMPLOYEE_CONTRACT as the current term, and
existing employee/salary/letter/signatory masters. Extension does not recreate
that table or write an extension ID into LATEST_RENEWAL_ID. Extension history is
stored in HR_CONTRACT_EXTENSION; renewal history stays in HR_CONTRACT_RENEWAL.
The generic employee letter gains a separate CONTRACT_EXTENSION_ID link.

Finish or delete an employee's open renewal draft before preparing/posting an
extension. If renewal changes the current term after an extension draft was
prepared, extension posting rejects the stale draft. Deleting an extension
draft retains the shared current contract record.

## Install and page setup

Install the existing renewal database objects first, then run this folder's
scripts as HRMS in SQLcl/SQL*Plus:

```sql
@00_install.sql
@99_contract_extension_checks.sql
```

The installer adds extension objects and extension-only templates. It does not
execute the renewal installer or merge renewal templates. These are SQL and
Page Designer snippets, not importable APEX page exports. Use each block in:

- page_523_contract_extension_register.sql
- page_524_contract_extension_entry.sql
- page_525_contract_extension_letter.sql

Use CONTRACT_EXTEND_VIEW, CONTRACT_EXTEND_EDIT and CONTRACT_EXTEND_POST
authorization schemes, and apply them to server processes as well as buttons.
The authenticated numeric USER_ID maps to USERS_COMPANY.EMPID for company access;
adapt that mapping if your login uses a different key. Protect USER_ID and the
hidden IDs/version, and require session checksums for page links.

All date items use DD-MON-YYYY. Make P524_SIGNATORY_ID required; default to the
first active HR_LETTER_SIGNATORY by DISPLAY_ORDER. On employee selection, run
the date-loading action followed by the start/end-date calculation action.
Display extra employee LOV values for existing records.

Save/Final Submit process order: validate access and lock/check version (5),
custom salary grid DML (10), save header/totals (20), final submit (30).
Use the supplied custom grid process; hide its standalone Save toolbar action.
Skip unsaved grid/header processing on Refresh Salary and Delete Draft.
Return to Page 524 after save/refresh and Page 525 after posting, passing the
extension/company IDs and clearing target-page cache.

On Page 525 add:

```javascript
function printContractLetter() { window.print(); }
```

The package does not commit. Let APEX roll back the complete request on failure.
Use the same letterhead/page templates as renewal. The new letter template
codes are CONTRACT_EXTENSION_EN and CONTRACT_EXTENSION_BN; existing
CONTRACT_RENEWAL_EN/BN are preserved.

## Verification

Source checks are provided separately from database execution. In a disposable
HRMS test database, run the rollback regression using an eligible, authorized
employee with recorded dates ending before today and no open renewal/extension:

```sql
@98_test_contract_extension.sql employee_internal_id authenticated_user_id
```

It verifies exact copying/manual posting, non-grade/no-salary eligibility,
unchanged salary history, explicit new heads, stale salary/type/version checks,
issued extension letters and posted-record protection. All test DML is rolled
back; sequence/identity values are consumed. It also checks that renewal rows
and renewal letter templates are unchanged.

In APEX verify company access, expired versus closed contracts, optional manual
changes, future drafts, printing, and an unchanged renewal on Pages 520–522.
