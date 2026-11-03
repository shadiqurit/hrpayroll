# Page 422: Approval-এর পরে HRD recording

Existing package এবং `P_422 Update the next.sql`-এ RECORD action আছে। Approval
কাজ করলে নতুন approval package বা দ্বিতীয় action process লাগবে না। একই Page
422-এ HRD inbox এবং RECORD button সেট করুন। Approval select list-এ RECORD
যোগ করবেন না; HRD-এর জন্য পৃথক button ব্যবহার করুন।
Automatic consumption feature install থাকলে debit হয় final approval-এর সময়ই;
এই RECORD button-এ consumption INSERT যোগ করবেন না। Balance/posting setup
`LEAVE_CONSUMPTION_POSTING_BN.md`-এ আছে।

## 1. HRD assignment এবং login

V_LEAVE_ROLES-এ এই company-এর active LEAVE_RECORD role যে employee-কে দেওয়া
আছে, তাঁর login থেকে record হবে। কেবল HRD department-এর employee হলেই
স্বয়ংক্রিয় permission হবে না। বর্তমান role source-এ প্রতি company-তে একজন
active recorder থাকতে হবে। Login global USER_ID numeric EMPLOYEES.ID এবং
G_COM_ID authorized selected company ID। G_EMP_ID character employee/IPI code।

APEX application context-এ assignment পরীক্ষা:

```sql
SELECT r.company_id, r.role_code, r.id AS hrd_employee_id,
       e.emp_id AS employee_code,
       TRIM(e.f_name || ' ' || e.l_name) AS hrd_name,
       e.status AS employee_status
  FROM v_leave_roles r
  LEFT JOIN employees e ON e.id = r.id
 WHERE r.company_id = :G_COM_ID
   AND UPPER(TRIM(r.role_code)) = 'LEAVE_RECORD'
   AND UPPER(TRIM(r.active_yn)) = 'Y';
```

SQL Workshop-এ চালালে G_COM_ID bind-এ actual company ID দিন। Employee status
1 এবং hrd_employee_id = HRD login-এর USER_ID হতে হবে। Final approval-এর পরে
সেই request-এর LEAVE_RECORD history PENDING হবে। WAITING থাকলে এখনও final
approval হয়নি বা পুরোনো route review প্রয়োজন। Assignment বদলালে saved route
স্বয়ংক্রিয় reassign হয় না; package administrator review চাইবে।

## 2. HRD যেন approved request খুলতে পারেন

Existing approval inbox যদি শুধু F/F নেয়, HRD-এর A/A request দেখাবে না।
Page 422-এর pending report (অথবা যে existing report থেকে 422 খোলা হয়)-এর
SQL Source-এ `page_422_pending_inbox.sql` দিন। একই query-তে F/F pending
approvals এবং A/A pending HRD records দুটোই আছে; actor/company filter আছে।

Existing working edit link রাখুন। Selected LEAVE_ID অবশ্যই P422_LEAVE_ID-এ
যাবে। Existing history form-এর primary-key item P422_DID হলে DID-ও সেখানে
পাঠান; LEAVE_ID এবং history DID আলাদা keys। নতুন selected request খুললে
appropriate page cache clear করুন, যাতে আগের request-এর key/remarks না থাকে।
Form initialization/query-তে আলাদা F-only filter থাকলে সেখানেও assigned HRD-এর
A/A request load হতে দিন। Existing page/process authorization বজায় রাখুন।

শুধু HRD-এর আলাদা report region চাইলে query হবে:

```sql
SELECT a.*
  FROM v_leave_approval a
 WHERE a.com_id = :G_COM_ID
   AND a.approver_id = :USER_ID
   AND a.approver_level = 'LEAVE_RECORD'
   AND a.approval_status = 'PENDING'
   AND a.leave_status = 'A'
   AND a.request_status = 'A'
   AND EXISTS (SELECT 1 FROM employees e
                WHERE e.id = a.empid AND e.com_id = :G_COM_ID)
 ORDER BY a.leave_id;
```

## 3. RECORD button

Page Designer → Page 422 → Create Button:

| Property | Value |
| --- | --- |
| Name | RECORD |
| Label | Record by HRD |
| Action | Submit Page |
| Database Action | None / no database action |
| Execute Validations | Yes |
| Server-side Condition Type | SQL Query (returns rows) |

Condition code হিসেবে `P_422 HRD record condition.sql` দিন। এটি selected request
A/A এবং current USER_ID-এর LEAVE_RECORD/PENDING আছে কি না পরীক্ষা করে। Record
হয়ে গেলে button আর দেখাবে না। UI condition-এর পরেও package authorization এবং
repeat-submit checks চালায়।

## 4. Existing process-এই RECORD চালান

Processing → existing Update the next:

| Property | Value |
| --- | --- |
| Type | Execute Code / PL/SQL |
| Point | Processing / After Submit |
| When Button Pressed | খালি; SUBMIT_ACTION-only থাকলে সরান |
| Server-side Condition Type | PL/SQL Expression |
| Expression | apex_application.g_request IN ('SUBMIT_ACTION', 'RECORD') |

Code হিসেবে existing `P_422 Update the next.sql`-এর সম্পূর্ণ block রাখুন।
এটি RECORD request হলে P422_APPROVAL_STATUS উপেক্ষা করে p_action = RECORD
পাঠায়। মূল call একই:

```sql
HRMS.pkg_leave_approval.take_action(
    p_leave_id   => :P422_LEAVE_ID,
    p_company_id => :G_COM_ID,
    p_actor_id   => :USER_ID,
    p_action     => l_action,
    p_comments   => :P422_COMMENTS
);
```

দ্বিতীয় RECORD process বানাবেন না; এক submit-এ একটি action process চলবে।
RECORD-এ normal Form DML বা অন্য status/history update process চলবে না।
Existing success Branch/Close Dialog-এর request condition-এ RECORD যোগ করুন;
সেটি action process-এর পরে চলবে। Report refresh হলে recorded row pending inbox
থেকে চলে যাবে।

## 5. Approval select list ও remarks

P422_APPROVAL_STATUS এবং SUBMIT_ACTION button-এর approval-only F/F condition
আগের মতো রাখুন (`PAGE_422_SETUP_BN.md`-এ query আছে)। HRD recording-এর সময় এগুলো
দেখাবে না। P422_APPROVAL_STATUS-এর Value Required = No রাখুন; selected action
existing process-এ শুধু SUBMIT_ACTION-এর জন্য validate হয়। আলাদা approval
select-list validation থাকলে When Button Pressed = SUBMIT_ACTION দিন, যাতে
RECORD submit-এ Approve/Reject নির্বাচন না চায়।

P422_COMMENTS চাইলে shared Remarks textarea রাখুন; এটি approval-only region-এর
ভেতরে থাকলে HRD-এর সময়ও render হওয়ার ব্যবস্থা করুন। Optional, সর্বোচ্চ 300
bytes; Bengali text-এর character count এবং byte count সমান নয়। Stored history
COMMENTS column-এ এই item-এর direct Form DML mapping লাগাবেন না; package নেয়।

## 6. Record হওয়ার পরে কী থাকবে

| Field | Result |
| --- | --- |
| LEAVE_APP_HISTORY.APPROVER_LEVEL | LEAVE_RECORD |
| APPROVAL_STATUS | RECORDED |
| APPROVAL_DATE | Record করার সময় |
| UPD_BY | HRD employee-এর numeric USER_ID |
| COMMENTS | P422_COMMENTS-এর remarks |
| LEAVE_REQUEST.LEAVE_STATUS / REQUEST_STATUS | A / A |

Completed HRD register করতে উপরের HRD-only report query-তে শুধু
`a.approval_status = 'RECORDED'` দিন। Report columns APPROVAL_DATE, COMMENTS এবং
APPROVER_ID রাখুন; names/remarks-এ Escape Special Characters = Yes রাখুন।

একটি test approved request দিয়ে assigned HRD login থেকে Record করুন। Pending
inbox থেকে row সরে গিয়ে completed register-এ আসবে। আবার record submit করলে
package action গ্রহণ করবে না। Approve হওয়ার আগে বা অন্য employee-এর login
থেকে record করা যাবে না।

Button/request reference: [Oracle APEX: Using REQUEST and When Button Pressed](https://docs.oracle.com/en/database/oracle/apex/24.2/htmdb/using-available-built-in-substitution-strings.html).
Live APEX page এই workspace থেকে পরিবর্তন করা হয়নি।
