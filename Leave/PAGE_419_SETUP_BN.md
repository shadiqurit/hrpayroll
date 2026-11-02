# Page 419: আবেদন এখন কার কাছে pending

Page Designer → Page 419 → নিজের leave applications report region →
Source → SQL Query-তে `page_419_leave_request_report.sql`-এর সম্পূর্ণ query বসান।
এটি read-only report source; SQL Workshop-এ view create করার script নয়।
Filter আগের মতো `lr.empid = :USER_ID`। USER_ID numeric EMPLOYEES.ID;
G_EMP_ID character employee/IPI code।

নতুন report columns:

| Column | Heading | কী দেখাবে |
| --- | --- | --- |
| PENDING_WITH | Pending With | বর্তমান pending approver বা eligible alternative approvers-এর নাম |
| PENDING_ROLE | Pending Role | RP / HOD / Plant Head / Managing Director / HRD Record Keeping |
| CURRENT_STAGE | Current Stage | Pending Approval / Pending HRD Recording / Approved / Rejected / Not Submitted |

নাম আসে EMPLOYEES.F_NAME + L_NAME থেকে, history-এর APPROVER_ID = EMPLOYEES.ID
দিয়ে join করে। নাম পাওয়া না গেলে numeric employee ID দেখাবে।
বর্তমান assignee আসে LEAVE_APP_HISTORY-এর PENDING row থেকে; current role
setup থেকে পুনরায় অনুমান করা হয় না। WAITING rows দেখাবে না।

RP recommend করলে HOD ও Plant Head-এর মতো eligible final candidates-এর নাম
একসঙ্গে দেখাবে; যেকোনো একজন approve করলেই final। HOD-এর নিজের আবেদনে
Plant Head/MD, Plant Head-এর আবেদনে MD দেখাবে। Final approval-এর পরে
request Approved থাকবে, কিন্তু CURRENT_STAGE = Pending HRD Recording এবং
HRD recorder-এর নাম/role দেখাবে। Record হয়ে গেলে stage Approved এবং pending
columns blank হবে। Draft/rejected request-এর pending columns-ও blank থাকবে।

একাধিক distinct final candidate PENDING থাকা স্বাভাবিক; stage Pending Approval
থাকবে। একই person/role duplicate বা RP এবং final group একসঙ্গে pending হলে
review message আসবে। Request report-এ একাধিক row হবে না। Forwarded request-এ pending step
না থাকলে Approval Route Requires Review দেখাবে।

নতুন columns Page Designer-এ synchronize হয়েছে কি না দেখুন। Interactive
Report-এ Actions → Columns থেকে তিনটি column যোগ করুন; saved report layout
থাকলে সেটিতেও columns যোগ করে প্রয়োজনমতো save করুন। Escape Special
Characters = Yes রাখুন। Pending columns-এর Null Display Value `-` দিতে পারেন।
Report refresh করলে approval-এর সর্বশেষ committed অবস্থান দেখাবে।

Live Oracle/APEX execution এই workspace থেকে করা হয়নি।
