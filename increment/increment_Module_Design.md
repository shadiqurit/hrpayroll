# Employee Annual Increment Management — Database & System Design

You are designing and implementing an **Employee Annual Increment Management System** for an HR/payroll application.

The main objective is to design a robust database schema and workflow for employee annual increments, including eligibility, consideration, approval, temporary hold, deferment due to punishment, salary structure updates, effective dates, increment history, and increment letters.

## 1. Existing Tables

The application already has existing HR/payroll tables. Do **not** redesign or duplicate these tables unnecessarily.

The following existing tables will be provided for analysis:

* `employees`
* `hr_confirmation`
* `emp_salary_structure`
* `grade`
* `payscale`
* `allowance_head`

Additional existing tables may also be provided.

Before designing anything, inspect the structure, columns, primary keys, foreign keys, relationships, status fields, date fields, and existing business logic of these tables.

The final design must integrate with the existing schema.

---

# 2. Core Business Concept

An employee becomes eligible for annual increment based on their **confirmation date**, not their joining date.

The basic rule is:

> Employee must complete one year from the confirmation date before becoming eligible for annual increment consideration.

Example:

* Joining Date: `01-Jan-2024`
* Confirmation Date: `01-Jul-2024`
* First Increment Consideration Date: `01-Jul-2025`

The system must calculate and maintain the appropriate annual increment consideration date.

---

# 3. Increment Consideration

When an employee reaches the required eligibility date, the employee should appear in an **Increment Consideration List**.

The HR user should be able to create/process an increment cycle for a particular consideration period.

Example:

```text
Increment Cycle: July 2025

Eligible Employees:
Employee A
Employee B
Employee C
Employee D
```

The system should allow HR to review each employee before final processing.

Possible decisions/statuses may include:

* Pending
* Approved for Increment
* Temporary Hold
* Deferred
* Rejected/Stopped
* Processed
* Cancelled

You should recommend the best status model rather than blindly using the above values.

---

# 4. Temporary Hold

A temporary hold is different from a permanent deferment or punishment-related increment stop.

If an employee's increment is temporarily held:

* The employee remains eligible for the increment.
* The increment may be processed later.
* The original increment effective date should remain unchanged.
* The employee should receive the increment according to the original effective date.
* The processing date may be later than the effective date.

Example:

```text
Consideration Date: 01-Jul-2025
Effective Date:     01-Jul-2025
Actual Processing:  01-Sep-2025
Status:             Temporary Hold → Processed
```

The system must preserve both the effective date and actual processing date.

---

# 5. Increment Deferred Due to Punishment

If an employee is subject to disciplinary action/punishment and the increment is stopped or deferred:

* The employee should not receive the current increment according to the normal cycle.
* The next increment consideration should follow the defined annual cycle.
* The system must preserve the reason and decision history.
* The system must not silently modify or delete previous increment eligibility information.

The exact business interpretation of "deferred" should be confirmed against the existing HR rules before implementation.

If there are multiple possible interpretations, clearly identify them and ask for confirmation rather than making assumptions.

---

# 6. Effective Date Rules

The system must clearly distinguish between:

### Consideration Date

The date on which the employee becomes eligible for increment consideration.

### Effective Date

The date from which the new salary becomes effective.

### Processing Date

The date on which the increment is actually processed in the system.

These dates must not be treated as the same field.

For example:

```text
Consideration Date = 01-Jul-2025
Effective Date     = 01-Jul-2025
Processing Date    = 15-Sep-2025
```

The system should support this situation.

If an increment is deferred because of punishment and the effective date needs to change, that must be explicitly recorded with the reason and approval information.

---

# 7. Single Increment Processing

The system should support a **batch increment process**.

HR should not need to manually update each employee's salary structure one by one.

Expected workflow:

```text
Generate Eligible Employee List
        ↓
HR Reviews Employees
        ↓
Mark Hold / Defer / Approve
        ↓
Finalize Increment Batch
        ↓
Process Approved Employees
        ↓
Calculate New Salary
        ↓
Update Employee Salary Structure
        ↓
Create Salary History
        ↓
Create Increment History
        ↓
Generate Increment Letters/Reports
```

The batch process must be transactional.

If the increment process fails for an employee or the entire transaction, the system must not leave the database in a partially updated or inconsistent state.

---

# 8. Salary Structure

The existing salary structure must be analyzed before designing the increment functionality.

Salary may contain components such as:

```text
Basic
House Rent
Medical
Conveyance
Allowance
Other Allowances
Gross Salary
```

However, do not assume these exact components or calculation rules.

Use the existing:

* `emp_salary_structure`
* `allowance_head`
* `grade`
* `payscale`

and other relevant tables to understand how salary is currently maintained.

The increment system should work with the application's existing salary architecture.

---

# 9. Salary History

A very important requirement is that the system must **never lose the previous salary structure** when an increment is processed.

Example:

### Before Increment

```text
Basic       20,000
House Rent   8,000
Medical      2,000
Conveyance   1,000
Gross       31,000
```

### After Increment

```text
Basic       23,000
House Rent   9,200
Medical      2,500
Conveyance   1,200
Gross       35,900
```

The system must preserve both the old and new salary structures.

The design should preferably use a salary structure/version/history approach rather than storing a large number of old/new salary columns directly in the increment table.

---

# 10. Increment History

Every processed increment must have a permanent audit/history record.

The history should allow us to answer:

* Why was the employee eligible?
* Which increment cycle processed the employee?
* What was the consideration date?
* What was the effective date?
* When was it actually processed?
* Who approved it?
* Who processed it?
* What was the old salary?
* What was the new salary?
* Which salary components changed?
* Was the increment held?
* Was it deferred?
* Why was it deferred?
* What was the previous increment?
* What is the next increment consideration date?
* Was the increment later reversed/cancelled?

The design should support a complete audit trail.

---

# 11. Increment Letter

After successful increment processing, the system should be able to generate an increment letter/report.

The letter should show information such as:

```text
Employee Information

Employee Name
Employee Code
Designation
Department
Grade

Previous Salary Structure

Basic
House Rent
Medical
Conveyance
Other Allowances
Gross Salary

New Salary Structure

Basic
House Rent
Medical
Conveyance
Other Allowances
Gross Salary

Increment Effective Date
Increment Percentage/Amount
Increment Cycle
```

The exact format will be finalized later.

---

# 12. Database Design Requirements

Based on the existing tables, determine whether new tables are required.

Possible logical entities may include:

### Increment Cycle/Header

Represents a particular increment processing cycle.

Example:

```text
Increment Cycle
July 2025
```

### Increment Employee/Detail

Represents each employee's decision within the increment cycle.

Example:

```text
Employee A → Approved
Employee B → Temporary Hold
Employee C → Deferred
```

### Increment History

Stores the finalized increment transaction.

### Salary Structure History/Version

Stores the employee's salary structure at a particular point in time.

### Salary Component History

If necessary, stores individual salary-head amounts for each salary structure version.

These are only conceptual suggestions. Determine the final schema after analyzing the existing database.

---

# 13. Important Design Principle

Do not duplicate data unnecessarily.

For example, if employee grade, payscale, salary head, or salary structure already exists in an existing table, use the existing relationship rather than creating another copy.

However, historical salary information must remain immutable once an increment has been finalized.

The design should balance:

* Normalization
* Historical accuracy
* Auditability
* Performance
* Ease of reporting
* Ease of future maintenance

---

# 14. Schema Analysis Before Coding

Before writing any SQL, PL/SQL, API, UI, or application code:

1. Inspect all provided existing tables.
2. Identify primary keys.
3. Identify foreign keys.
4. Identify existing salary relationships.
5. Identify confirmation rules.
6. Identify grade/payscale relationships.
7. Identify allowance/salary-head relationships.
8. Identify existing employee status fields.
9. Identify existing audit fields.
10. Identify existing effective-date logic.
11. Identify existing payroll/salary history if available.
12. Identify any existing increment-related tables or columns.

Then produce a proposed architecture.

---

# 15. Required Design Output

Before implementation, provide the following:

## A. Business Rule Interpretation

Explain the increment rules in your own words.

Clearly identify:

* Eligibility
* Consideration
* Approval
* Temporary hold
* Deferment
* Effective date
* Processing date
* Next increment date

Highlight anything ambiguous.

## B. Entity Relationship Design

Show how the increment entities relate to:

```text
employees
hr_confirmation
emp_salary_structure
grade
payscale
allowance_head
```

and any additional existing tables.

## C. Proposed New Tables

For every new table provide:

* Table name
* Purpose
* Column name
* Data type
* Nullable/not nullable
* Primary key
* Foreign key
* Unique constraints
* Check constraints
* Indexes
* Audit columns

## D. Existing Table Changes

Clearly list any required changes to existing tables.

Do not modify existing tables unless necessary.

## E. Increment Workflow

Describe the complete workflow from:

```text
Eligibility
→ Consideration
→ HR Decision
→ Approval
→ Batch Processing
→ Salary Update
→ History
→ Increment Letter
```

## F. Date Logic

Provide precise rules for:

```text
Joining Date
Confirmation Date
Eligibility Date
Consideration Date
Effective Date
Processing Date
Next Increment Date
```

Use examples.

## G. Salary Versioning

Explain exactly how the system will preserve:

```text
Previous Salary Structure
        ↓
Increment
        ↓
New Salary Structure
```

and how historical salary can be retrieved later.

## H. Transaction and Concurrency Handling

Explain how batch increment processing should prevent:

* Duplicate increment processing
* Double salary updates
* Partial processing
* Incorrect effective dates
* Multiple increments for the same cycle
* Concurrent users processing the same increment batch

## I. Audit Trail

Define who/when/what information should be recorded for:

* Create
* Hold
* Resume
* Approve
* Defer
* Process
* Cancel
* Reverse

## J. Reporting

Identify queries/reports that should be possible, such as:

* Eligible employees
* Pending increment list
* Held increments
* Deferred increments
* Processed increments
* Employee increment history
* Employee salary history
* Increment comparison: old vs new salary
* Increment cycle summary

---

# 16. Implementation Rules

Do not immediately start coding.

The implementation should happen in stages:

### Stage 1 — Analyze Existing Schema

Understand the existing database.

### Stage 2 — Confirm Business Rules

List assumptions and ambiguities.

### Stage 3 — Propose Schema

Provide ERD/logical design and table definitions.

### Stage 4 — Review

Wait for approval of the schema/business rules.

### Stage 5 — Implement

Only after approval, create:

* Tables
* Sequences/identity columns
* Foreign keys
* Indexes
* Constraints
* Views
* Procedures/packages
* APIs
* UI logic
* Reports

Use the technology and coding conventions already present in the project.

---

# 17. Critical Requirement

Do not simplify the system into:

```text
employee → increase salary → save new salary
```

The system must be designed as a proper **increment transaction and salary-history system**.

Historical records must remain reliable even if:

* Salary components change later
* Employee grade changes later
* Payscale changes later
* Allowance heads change later
* Employee receives multiple annual increments
* An increment is held
* An increment is deferred
* An increment is cancelled/reversed

The final design should allow us to reconstruct an employee's salary structure as it existed at any historical increment point.

---

# 18. First Response Expected From You

After receiving the existing table definitions, **do not write implementation code immediately**.

First respond with:

1. Your understanding of the business rules
2. Existing-table relationship analysis
3. Identified ambiguities/questions
4. Proposed entity model
5. Proposed new tables
6. Proposed date/eligibility logic
7. Proposed salary-history/versioning strategy
8. Increment processing workflow
9. ERD/logical relationship diagram
10. Recommended implementation approach

Only after the design is reviewed and approved should coding begin.
