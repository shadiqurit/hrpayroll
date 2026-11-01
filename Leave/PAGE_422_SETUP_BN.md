# Page 422: P422_APPROVAL_STATUS select list থেকে Approve / Reject

এই page-এ user action নির্বাচন করবেন, তারপর SUBMIT_ACTION চাপবেন।
শুধু select list পরিবর্তন করলে database update হবে না।

## 1. Select list

Page Designer → Page 422 → P422_APPROVAL_STATUS:

| Property | Value |
| --- | --- |
| Type | Select List |
| Label | Approval Action |
| Source Type | Null; database column mapping সরান |
| Default | None; PENDING/APPROVED default দেবেন না |
| List of Values Type | SQL Query |
| Display Null Value | Yes |
| Null Display Value | - Select Action - |
| Null Return Value | খালি |
| Display Extra Values | No |
| Page Action on Selection | None |
| Value Required | No; submit process নির্বাচন যাচাই করবে |

SQL Query:

```sql
SELECT 'APPROVE' AS display_value, 'APPROVE' AS return_value FROM dual
UNION ALL
SELECT 'REJECT' AS display_value, 'REJECT' AS return_value FROM dual;
```

এই item একটি action input; stored APPROVAL_STATUS column নয়। Form Initialization
বা computation থেকে PENDING/APPROVED load করবেন না। বর্তমান stored status
দেখাতে চাইলে report column বা আলাদা display-only item ব্যবহার করুন। নতুন
request খুললে action item-এর আগের selection clear করুন। Validation error-এ
পুনরায় page দেখানোর সময় user-এর selection overwrite করবেন না।

## 2. Submit button

| Property | Value |
| --- | --- |
| Name | SUBMIT_ACTION |
| Label | Submit |
| Action | Submit Page |
| Database Action | None / no database action |
| Execute Validations | Yes |

পুরোনো APPROVE/REJECT button-এর বদলে এই button ব্যবহার করুন। একই click-এ
Dynamic Action এবং page process দুটো দিয়ে action call করবেন না।

## 3. Approval process

Processing → existing Update the next process replace করুন:

| Property | Value |
| --- | --- |
| Type | Execute Code |
| Language | PL/SQL |
| Point | Processing / After Submit |
| When Button Pressed | খালি |
| Condition Type | PL/SQL Expression |
| Expression | apex_application.g_request IN ('SUBMIT_ACTION', 'RECORD') |

Code হিসেবে `P_422 Update the next.sql`-এর সম্পূর্ণ block দিন। এটি
SUBMIT_ACTION হলে `P422_APPROVAL_STATUS` থেকে APPROVE/REJECT পড়ে; null,
APPROVED, REJECTED, RECORD বা অন্য return value approval submit-এ গ্রহণ করে না।
RECORD request হলে আলাদা HRD action নেয়; select list-এর পুরোনো value নেয় না।

`P422_LEAVE_ID`-তে selected request ID থাকতে হবে। Actor `:USER_ID` হলো numeric
EMPLOYEES.ID; `:G_EMP_ID` character employee/IPI code। Package database থেকে
pending approver, company, role এবং step order যাচাই করবে।

SUBMIT_ACTION/RECORD-এ Automatic Row Processing (DML) চলবে না। অন্য সরাসরি
status/history update process সরান। Selection APPROVE হলে package history-তে
APPROVED লেখে; REJECT হলে REJECTED লেখে এবং পরের steps cancel করে।
COMMIT বা WHEN OTHERS THEN NULL যোগ করবেন না। Success branch/Close Dialog
এই process-এর পরে রাখুন। Report/modal refresh existing success flow-এ রাখুন।

## 4. Button ও select list-এর visibility

SUBMIT_ACTION button এবং P422_APPROVAL_STATUS select list দুটোতেই
Server-side Condition → SQL Query (returns rows) ব্যবহার করুন:

```sql
SELECT 1
  FROM v_leave_approval a
 WHERE a.leave_id = :P422_LEAVE_ID
   AND a.com_id = :G_COM_ID
   AND a.approver_id = :USER_ID
   AND a.approval_status = 'PENDING'
   AND a.approver_level IN ('RP', 'HOD', 'PLANT_HEAD', 'MANAGING_DIRECTOR')
   AND a.leave_status = 'F'
   AND a.request_status = 'F'
   AND EXISTS (SELECT 1 FROM employees e
                WHERE e.id = a.empid AND e.com_id = :G_COM_ID);
```

এটি UI condition; package-এর server-side checks চূড়ান্ত authorization দেয়।
HRD-এর জন্য RECORD button আলাদা রাখুন; তার A/A + LEAVE_RECORD/PENDING
condition `APEX_COMPANY_APPROVAL.md`-এ আছে। Value Required = No রাখায়
HRD-কে APPROVE/REJECT নির্বাচন করতে হবে না।

## 5. যাচাই

- Pending approver-এর login দিয়ে APPROVE নির্বাচন করে Submit দিন: history
  APPROVED হবে এবং next step PENDING হবে; MD-এর আগে request F/F থাকবে।
- অন্য একটি pending request-এ REJECT দিন: current history REJECTED,
  request R/F, এবং later steps CANCELLED হবে।
- কোনো action নির্বাচন না করে Submit দিলে error হবে; history অপরিবর্তিত থাকবে।
- অন্য employee বা already-completed request দিয়ে action নেওয়া যাবে না।
- MD approve করলে request A/A হবে; শুধু তখন HRD RECORD করতে পারবেন।

LOV reference: [Oracle APEX: Beginners Guide to List of Values](https://blogs.oracle.com/apex/beginners-guide-to-list-of-values-in-oracle-apex).
Live APEX/Oracle-এ এই workspace থেকে প্রয়োগ বা পরীক্ষা করা হয়নি।
