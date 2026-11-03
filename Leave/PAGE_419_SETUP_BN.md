# Page 419: একটি status column-এ pending নাম ও role

Page Designer → Page 419 → নিজের leave applications report region →
Source → SQL Query-তে `page_419_leave_request_report.sql`-এর সম্পূর্ণ query বসান।
Filter আগের মতো `lr.empid = :USER_ID`। USER_ID numeric EMPLOYEES.ID;
G_EMP_ID character employee/IPI code।
আগে updated INSTALL_COMPANY_APPROVAL.sql install করুন; report এখন
V_LEAVE_YEAR_BALANCE, FN_LEAVE_TYPE_ID এবং consumption-এর LEAVE_ID link ব্যবহার করে।

শুধু existing LEAVE_STATUS column ব্যবহার হবে; heading Leave Status দিন।
PENDING_WITH, PENDING_ROLE, CURRENT_STAGE অতিরিক্ত columns আর query-তে নেই।

| অবস্থা | LEAVE_STATUS-এ দেখাবে |
| --- | --- |
| RP recommendation pending | Pending with Name (RP) |
| HOD / Plant Head final decision pending | Pending with Name (HOD), Name (Plant Head) |
| Final approval complete; HRD recording pending অথবা complete | Approved |
| Rejected | Rejected |
| Draft D | Draft |
| Pending P অথবা forwarded F কিন্তু pending approver পাওয়া যায়নি | Pending |

নাম ও role প্রতিটি ব্যক্তির জন্য একসঙ্গে রাখা হয়। নাম আসে EMPLOYEES.F_NAME +
L_NAME থেকে, history-এর APPROVER_ID = EMPLOYEES.ID দিয়ে join করে। নাম পাওয়া
না গেলে numeric employee ID দেখাবে। শুধু saved approval route-এর PENDING
RP/HOD/PLANT_HEAD/MANAGING_DIRECTOR rows আসবে; WAITING বা HRD recording
person এখানে দেখাবে না। Final approval-এর পরে এই applicant report-এ Approved
দেখাবে; HRD-এর কাজ Page 422 recording inbox-এ আগের মতো থাকবে।

Aggregation-এর কারণে একাধিক eligible final approver থাকলেও request report-এ
একটি row থাকবে। Existing package checks এবং CHECK_COMPANY_APPROVAL.sql route
validation করবে; applicant report-এ আলাদা technical review column থাকবে না।

Query পরিবর্তনের পরে Page Designer/report-এর পুরোনো তিনটি column এবং saved
report layout-এর references সরান। LEAVE_STATUS column-এ Escape Special
Characters = Yes রাখুন। Report refresh করলে latest committed status দেখাবে।
LEAVE_BALANCE এবং LEAVE_TAKEN-ও ledger থেকে live হিসাব হবে, request-এ save হওয়া
পুরোনো values থেকে নয়। Year হবে leave start date-এর year; posted request-এর
জন্য saved consumption account ব্যবহার হবে। একই account-এর পরের leave approve
হলেও পুরোনো report row-তে current balance দেখাবে।

Live Oracle/APEX execution এই workspace থেকে করা হয়নি।
