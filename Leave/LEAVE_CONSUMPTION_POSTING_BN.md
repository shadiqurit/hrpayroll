# Final approval → consumption → live balance

HOD/Plant Head/MD-এর eligible final approval-এ package এখন
POST_LEAVE_CONSUMPTION call করে। RP recommendation এবং HRD RECORD-এ debit হয়
না। Existing Page 422 process এবং USER_ID/G_COM_ID mapping আগের মতো থাকবে।
আলাদা APEX consumption insert process লাগবে না।

## আপনার নির্ধারিত নিয়ম

- Balance যথেষ্ট না হলে final approval বন্ধ হবে। Request F/F এবং final
  candidates pending অবস্থায় থাকবে; approval/history/consumption একসঙ্গে rollback হবে।
- CONSUMED_DAYS = approved PROPOSED_DAYS। Half-day হলে যেমন 0.5 সেভ হবে।
- CONSUM_YEAR = L_START_DATE-এর calendar year। December–January leave হলেও
  পুরো quantity start year-এ যাবে; year অনুযায়ী ভাগ হবে না।
- ALLOCATED_DAYS মোট allocation হিসেবেই থাকবে। এর থেকে deduct করে আবার
  consumption বাদ দিলে double deduction হবে, তাই allocation update করা হয় না।
- Balance = ওই employee/type/year-এর allocated days minus consumed days,
  আপনার F_LEAVE_BA function-এর একই formula। Historical EL carry/ERP adjustment-এর
  আলাদা V_EL_BALANCE module এই annual formula-এর অংশ নয়।

## Install

HRMS হিসেবে SQL*Plus/SQLcl-এ, unrelated transaction শেষ করে এবং approval ও
consumption writes সাময়িক বন্ধ রেখে চালান (Oracle DDL commits):

```sql
@D:\HRPAYROLL\Leave\INSTALL_COMPANY_APPROVAL.sql
@D:\HRPAYROLL\Leave\CHECK_COMPANY_APPROVAL.sql
```

এটি UPGRADE_LEAVE_CONSUMPTION.sql, FN_LEAVE_TYPE_ID.sql,
V_LEAVE_YEAR_BALANCE.sql, F_LEAVE_BA.sql, POST_LEAVE_CONSUMPTION.sql এবং updated
PKG_LEAVE_APPROVAL.sql install করে। Existing table DROP/CREATE exports চালাবেন না।
Installer existing business rows post/delete বা পুরোনো allocation recalculate করে না।

Consumption table-এ nullable LEAVE_ID foreign key, UNIQUE(LEAVE_ID), linked
row-এর year/quantity check এবং sequence-backed ID trigger যোগ হয়। Existing
consumption rows-এর LEAVE_ID NULL-ই থাকবে। Existing sequences reset হয় না।
First install-এ existing max ID-এর পরে নতুন sequence শুরু হয়। Existing ID
triggers/manual ID allocation থাকলে compatibility ও sequence position DBA
দিয়ে যাচাই করুন; নতুন positive IDs sequence-এর সামনে নিজে allocate করবেন না।

Allocation-এর employee/type/year duplicate থাকলে installer থামবে; আগে review
করুন। Approved requests balance check-এর সময় সেই unique allocation row lock
করে। একই account-এর concurrent approvals এক balance দুবার spend করতে পারে না।
অন্য posting integrations-কেও এই account-lock protocol মানতে হবে।

## Leave type mapping

Page 420 LEAVE_TYPE LOV-এর return value হিসেবে numeric LEAVE_TYPES.LT_ID
ব্যবহার করুন, text column-এ numeric string হিসেবে থাকলেও চলে। Existing short
code যেমন CL/SL/EL থাকলে FN_LEAVE_TYPE_ID company-specific code আগে, তারপর
global code resolve করে। Numeric ID দিলে exact ID-ই ব্যবহার হয়। Company scope,
active flag বা duplicate code ভুল হলে approval error দেখাবে।

## Page 422-এ যা রাখবেন

Existing `P_422 Update the next.sql` process-ই থাকবে। Package final approval
transition-এর পরে একই transaction-এ posting চালায়। Consumption insert, balance
snapshot বা insufficient-balance check-এর জন্য দ্বিতীয় APEX process যোগ করবেন
না। পুরোনো আলাদা consumption INSERT থাকলে এই workflow থেকে বাদ দিন। মাঝখানে
COMMIT বা WHEN OTHERS THEN NULL থাকবে না।

Final approval-এ সংরক্ষিত data:

| LEAVE_CONSUMPTION field | Source |
| --- | --- |
| LEAVE_ID | Approved request ID; unique |
| EMPID | LEAVE_REQUEST.EMPID |
| LEAVE_TYPE_ID | Resolved LEAVE_TYPES.LT_ID |
| CONSUMED_DAYS | PROPOSED_DAYS |
| START_DATE / END_DATE | Leave dates, time বাদ দিয়ে |
| CONSUM_YEAR | Leave start year |
| CONSUMPTION_DATE / ENT_DATE | Approval/posting time |
| ENT_BY | Final approver-এর numeric USER_ID |
| COM_ID | Applicant company |

HRD পরে RECORD করলে history RECORDED হবে; consumption-এর quantity বা entry
আবার তৈরি হবে না। UNIQUE request link এবং parent lock duplicate posting ঠেকায়।
একই approved request-এর matching posting retry করলে নতুন debit হয় না।

## Balance display এবং Page 419

F_LEAVE_BA-এর signature একই:

```sql
SELECT HRMS.f_leave_ba(:employee_id, :leave_type_id, :leave_year)
  FROM dual;
```

এখানে employee_id numeric EMPLOYEES.ID, leave_type_id numeric LT_ID এবং
leave_year start-date year। Output: `Balance : 8 Taken : 2`। No allocation/usage
থাকলে zero দেখাবে। Function একটি SQL snapshot থেকে values পড়ে। Numeric data:

```sql
SELECT allocated_days, consumed_days, balance_days
  FROM HRMS.v_leave_year_balance
 WHERE empid = :employee_id
   AND leave_type_id = :leave_type_id
   AND leave_year = :leave_year;
```

Page 419 SQL Source-এ updated `page_419_leave_request_report.sql` দিন। Existing
LEAVE_BALANCE/LEAVE_TAKEN columns live view থেকে আসবে। নতুন status columns নেই;
আগের single LEAVE_STATUS pending names/roles অথবা Approved দেখাবে। Report
refresh করুন। Function call database values পড়ে; existing APEX balance item-ও
refresh/reload করতে হবে।

## Existing approved/manual data

পুরোনো approved requests bulk backfill করা হয়নি। CHECK_COMPANY_APPROVAL.sql
linked consumption নেই এমন approved requests এবং negative ledger balances
দেখায়। Existing manual consumption থাকলে আগে matching rows review করে সঠিক
request link করুন। একই employee/type/dates/quantity-এর unlinked consumption
পাওয়া গেলে নতুন posting -20838 দিয়ে থামবে; এটি নিজে থেকে old row link করে না।
Legacy sequential approvals বা unmatched/changed quantities DBA review চাইবে।
Existing ledger delete, allocation কমানো, বা request status reset করে resubmit
করবেন না। এই APIs trusted server processes-এর জন্য; actor-parameter posting
API untrusted database users-কে grant করবেন না।

## Verify

একটি ছোট request final approve করে actual ID দিয়ে দেখুন:

```sql
SELECT leave_id, empid, leave_type_id, consumed_days, consum_year, ent_by
  FROM HRMS.leave_consumption WHERE leave_id = :leave_id;
```

একটি row হবে। RP approve/reject-এ row হবে না। HRD record/repeat submit-এ দ্বিতীয়
row হবে না। Balance কম হলে final approval rollback হবে। Test HRMS database-এ
TEST_COMPANY_APPROVAL.sql পুরো flow, consumption, insufficient balance rollback,
cross-year start-year posting এবং manual duplicate review পরীক্ষা করে। Test
allocations/consumption rollback হয়; sequence values consume হয়। Live Oracle
compilation/execution এই workspace থেকে করা হয়নি।

Offline SQL checks: `node Leave/tests/approval_queries.cjs` এবং
`node Leave/tests/consumption_queries.cjs`। এগুলো production SELECT/UPDATE/INSERT
SQL ও live balance view SQLite-এ compatibility substitutions দিয়ে চালায়;
Oracle PL/SQL compilation, allocation locks এবং SAVEPOINT runtime verify করে না।
