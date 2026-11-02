# Page 420: LEAVE_REQUEST default Form + Report-এর approval setup

Page 420-এর Form Source `LEAVE_REQUEST`-ই রাখুন। Form-এর Automatic Row
Processing কেবল ওই table-এ insert/update করে। `LEAVE_APP_HISTORY`-তে route
তৈরি করার জন্য তার পরে আলাদা Execute Code process লাগবে।

এই setup-এ default `CREATE` এবং `SAVE` দুটোই আবেদন approval-এ পাঠায়।
`SAVE`-কে draft-only ধরা হচ্ছে না। Default button rename করার দরকার নেই।

## 1. Database prerequisite

Approval package আগে install করা না থাকলে SQL*Plus/SQLcl-এ HRMS হিসেবে চালান:

```sql
@D:\HRPAYROLL\Leave\INSTALL_COMPANY_APPROVAL.sql
@D:\HRPAYROLL\Leave\CHECK_COMPANY_APPROVAL.sql
```

এগুলো local include-সহ installer; APEX process-এর PL/SQL box-এ paste করবেন না।
Existing table-এর DROP/CREATE file বা REQUEST_STATUS upgrade আবার চালাবেন না।
Installer Oracle DDL চালায়, তাই unrelated transaction শেষ করে চালান।

`V_LEAVE_ROLES`-এ applicant company-এর `PLANT_HEAD`, `MANAGING_DIRECTOR`,
`LEAVE_RECORD` assignment দিয়ে route নির্ধারিত হয়। HRD required। সাধারণ
employee-এর final approval HOD অথবা Plant Head; HOD-এর নিজের leave Plant Head
অথবা MD; Plant Head-এর নিজের leave MD। প্রয়োজনীয় final candidate অন্তত একজন
থাকতে হবে। সাধারণ employee-এর জন্য MD assignment বাধ্যতামূলক নয়। RP আসে
EMP_RP থেকে; distinct RP থাকলে তাঁর recommendation-এর পরে final candidates
একসঙ্গে PENDING হয়। Shared-role person একবার final approver হিসেবে act করেন।

## 2. Login context এবং Form items

Application-এর server-side login mapping থেকে নিচের protected items সেট করুন:

| Item | Value |
| --- | --- |
| G_EMP_ID | Character employee code / IPI code; display বা code lookup-এর জন্য |
| USER_ID | Logged-in employee-এর numeric EMPLOYEES.ID; approval actor এবং inbox filter-এর জন্য |
| G_COM_ID | Logged-in user-এর authorized selected company ID |

এই application-এ numeric employee ID-এর global item হলো `USER_ID`। Approval
package-এর `p_actor_id`, ownership check এবং approver report-এ `:USER_ID`
ব্যবহার করুন। `:G_EMP_ID` character code; এটি numeric ID হিসেবে pass বা
TO_NUMBER করবেন না। Existing login mapping দিয়ে globals populate করুন;
applicant page item থেকে authenticated actor বানাবেন না।

Page Designer → Page 420 → Form region এবং items:

| Setting | Value |
| --- | --- |
| Form Region Source | Local Database, LEAVE_REQUEST |
| P420_LEAVE_ID | Hidden; Database Column LEAVE_ID; Primary Key = Yes |
| P420_EMPID | Database Column EMPID; numeric EMPLOYEES.ID; নতুন own-leave request-এর server-side default :USER_ID |
| P420_LEAVE_STATUS | Query Only = Yes, যদি form-এ item থাকে |
| P420_REQUEST_STATUS | Query Only = Yes, যদি form-এ item থাকে |

নতুন request-এ database default `LEAVE_STATUS=P`, `REQUEST_STATUS=D` থাকবে।
Existing row load/edit-এর সময় status reset করবেন না। আপনার item names আলাদা
হলে SQL snippets-এ সেগুলো বসান। Existing Form Initialization process রাখুন।
P420_EMPID-এর LOV থাকলে return value হবে EMPLOYEES.ID; display value-তে
employee/IPI code দেখাতে পারেন। Existing request load-এর সময় EMPID overwrite
করবেন না। Validation process ownership পরীক্ষা করবে।

## 3. Default buttons রাখুন

| Property | CREATE | SAVE |
| --- | --- | --- |
| Name | CREATE | SAVE |
| Action | Submit Page | Submit Page |
| Database Action | SQL INSERT action | SQL UPDATE action |
| Execute Validations | Yes | Yes |
| Server-side Condition | Item is NULL: P420_LEAVE_ID | Item is NOT NULL: P420_LEAVE_ID |

Label Apply Leave / Submit হতে পারে। Request নির্ধারণ হয় Name দিয়ে। এই
setup-এ CREATE নতুন আবেদন save করে route বানায়; SAVE পুরোনো draft update
করে route বানায়। Cancel/Delete-এ route process চলবে না।

## 4. Processing tab-এ ঠিক এই ক্রম রাখুন

সবগুলো submit process একই **Processing / After Submit** point-এ রাখুন।
Sequence উদাহরণ; আপনার existing sequence ভিন্ন হলে relative order একই রাখুন।

| Sequence | Name | Type |
| --- | --- | --- |
| 10 | CHECK_LEAVE_DRAFT | Execute Code |
| 20 | Process form Apply Leave Request | Existing Form - Automatic Row Processing (DML) |
| 30 | BUILD_LEAVE_APPROVAL_ROUTE | Execute Code |
| 40 | Close Dialog (শুধু modal হলে) | Existing Close Dialog |

**CHECK_LEAVE_DRAFT:** `P_420 validate draft.sql`-এর code বসান।
When Button Pressed খালি রাখুন। Server-side Condition → PL/SQL Expression:

```sql
apex_application.g_request IN ('CREATE', 'SAVE', 'APPLY', 'FORWARD')
```

এটি applicant/company এবং existing request draft কি না যাচাই করে।

**Existing DML process:** delete বা duplicate করবেন না। Form Region হিসেবে
LEAVE_REQUEST form নির্বাচন করা থাকবে। Target Type = Region Source।
**Return Primary Key(s) after Insert = Yes** দিন। Insert-এর পর generated
LEAVE_ID অবশ্যই P420_LEAVE_ID-এ আসতে হবে। Existing button conditions যেন
CREATE/SAVE-কে block না করে। Existing authorized Delete handling থাকলে রাখুন।

**BUILD_LEAVE_APPROVAL_ROUTE:** Type = Execute Code, Language = PL/SQL।
`P_420 insert data.sql`-এর সম্পূর্ণ code বসান। When Button Pressed খালি রাখুন,
উপরের একই PL/SQL Expression দিন। FORWARD-only পুরোনো condition সরান।

Process-এর মূল call:

```sql
BEGIN
    HRMS.pkg_leave_approval.submit_request(
        p_leave_id   => :P420_LEAVE_ID,
        p_company_id => :G_COM_ID,
        p_actor_id   => :USER_ID
    );
END;
```

Route বানায় এই package call-ই। Default form DML নিজে history বানাবে না।
History-এর জন্য দ্বিতীয় form DML বা হাতে partial INSERT লাগাবেন না।
পুরোনো approval-history insert process replace করুন; দুটি route process রাখবেন না।

সব process successful হওয়ার পরে report-এ Branch/Close Dialog হবে। মাঝখানে
COMMIT, Clear Session State, Close Dialog বা error গোপন করা code রাখবেন না।
Report page create-link থেকে নতুন আবেদন খুললে Page 420 cache clear করুন;
existing row edit-link-এ তার LEAVE_ID পাঠান। Submitted request edit করা যাবে না।

## 5. Test এবং actual route দেখা

নতুন আবেদন CREATE দিয়ে submit করুন। অথবা আগে শুধু save হওয়া `P/D` draft
নিজের login থেকে খুলে SAVE চাপুন। প্রত্যাশিত ফল:

```text
LEAVE_REQUEST insert/update
  → generated LEAVE_ID returned to P420_LEAVE_ID
  → pkg_leave_approval.submit_request
  → LEAVE_APP_HISTORY: distinct RP থাকলে শুধু RP PENDING, finals WAITING
    RP না থাকলে eligible final candidates সবাই PENDING; HRD WAITING
  → LEAVE_REQUEST: LEAVE_STATUS=F, REQUEST_STATUS=F
  → report / dialog close
```

APEX SQL Workshop-এ নিচের `12345`-এর বদলে actual LEAVE_ID বসান:

```sql
SELECT lr.leave_id, lr.empid, lr.leave_status, lr.request_status,
       h.id AS history_id, h.approver_level, h.approver_id,
       h.approval_status, h.com_id, h.step_no
  FROM leave_request lr
  LEFT JOIN v_leave_approval_steps h ON h.leave_id = lr.leave_id
 WHERE lr.leave_id = 12345
 ORDER BY h.step_no;
```

| Result | কী দেখবেন |
| --- | --- |
| P/D, history_id NULL | Route process চলেনি; request condition ও process order দেখুন |
| Missing LEAVE_ID error | DML order, key item mapping, Return Primary Key setting দেখুন |
| Active employee / applicant error | Server-side numeric USER_ID, G_COM_ID এবং numeric P420_EMPID দেখুন; G_EMP_ID character code |
| Missing company role error | V_LEAVE_ROLES-এর active company assignments ঠিক করুন |
| Existing approval history error | পুরোনো route review করুন; status পাল্টে বা history delete করে bypass করবেন না |
| F/F, RP PENDING অথবা eligible finals সবাই PENDING | Route তৈরি হয়েছে; pending approvers-এর inbox পরীক্ষা করুন |

শুধু F/F update করে দিলে history তৈরি হয় না। Package call প্রয়োজন।

## 6. Approver report (Page 422)

Approval report-এর SQL Source:

```sql
SELECT a.*
  FROM v_leave_approval a
 WHERE a.com_id = :G_COM_ID
   AND a.approver_id = :USER_ID
   AND a.approval_status = 'PENDING'
   AND a.approver_level IN ('RP', 'HOD', 'PLANT_HEAD', 'MANAGING_DIRECTOR')
   AND a.leave_status = 'F'
   AND a.request_status = 'F'
   AND EXISTS (
       SELECT 1 FROM employees e
        WHERE e.id = a.empid AND e.com_id = :G_COM_ID)
 ORDER BY a.leave_id, a.step_no;
```

যাদের step PENDING, তাঁদের login/company-তে আবেদন দেখাবে। Alternative final
approvers একসঙ্গে দেখতে পারবেন; একজন approve করলে অন্যজনের আর action লাগবে
না। যাদের WAITING, তাঁদের inbox-এ এখনই দেখাবে না। Approve/Reject process-এর জন্য
`P_422 Update the next.sql` এবং `APEX_COMPANY_APPROVAL.md` অনুসরণ করুন।
P422_APPROVAL_STATUS select list-এর APPROVE/REJECT এবং SUBMIT_ACTION button
সেটআপের জন্য `PAGE_422_SETUP_BN.md` দেখুন।

APEX behavior reference:
[Oracle: Saving Changes with a Page Process](https://docs.oracle.com/en/database/oracle/apex/26.1/apxdc/saving-changes-page-process.html),
[Oracle: About Page Processes](https://docs.oracle.com/en/database/oracle/apex/24.2/htmdb/about-page-processes.html).

এই workspace থেকে live APEX page পরিবর্তন বা Oracle execution করা হয়নি।
