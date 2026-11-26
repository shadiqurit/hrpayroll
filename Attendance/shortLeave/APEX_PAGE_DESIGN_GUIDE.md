# Short Leave & Short Tour Application: Complete APEX Page Design Guide

এই গাইডটিতে **Short Leave** (সংক্ষিপ্ত ছুটি / গেট পাস) এবং **Short Tour** (সংক্ষিপ্ত অফিসিয়াল/ব্যক্তিগত ট্যুর)-এর জন্য Oracle APEX-এ সম্পূর্ণ পেজ ডিজাইন, ফর্ম আইটেম, ডায়নামিক অ্যাকশন, ভ্যালিডেশন এবং প্রসেস বিস্তারিত দেওয়া হলো।

---

## ১. পলিসি ও বিজনেস রুলস (Business Rules)

1. **Short Leave (সংক্ষিপ্ত ছুটি / Gate Pass):**
   - দৈনিক ডিউটি চলাকালীন স্বল্প সময়ের জন্য (সাধারণত ১ থেকে ২ ঘণ্টা) অফিসের বাইরে যাওয়ার অনুমতি।
   - **মাসিক কোটা সীমাবদ্ধতা (Monthly Limit):** প্রতি ক্যালেন্ডার মাসে সর্বোচ্চ **৩টি Short Leave (Personal)** অনুমোদিত।
   - ৩টির বেশি আবেদন করতে গেলে সিস্টেম স্বয়ংক্রিয়ভাবে আটকে দেবে এবং নোটিফিকেশন দেবে।
2. **Short Tour (সংক্ষিপ্ত ট্যুর / ফিল্ড ডিউটি):**
   - স্বল্প সময়ের জন্য অফিসিয়াল কাজে বাইরে যাওয়া (ক্লায়েন্ট মিটিং, ফ্যাক্টরি ভিজিট, ব্যাংক/ট্যাক্স অফিস ইত্যাদি)।
   - এটি **Official** অথবা **Personal** উভয় প্রকার হতে পারে।
   - Short Tour-এর জন্য গন্তব্যস্থল (Destination), যাতায়াতের মাধ্যম (Transport Mode) এবং আনুমানিক খরচ (Expense) উল্লেখ করার ব্যবস্থা থাকে।

---

## ২. প্রস্তাবিত APEX পেজ আর্কিটেকচার

| পেজ আইডি (উদাহরণ) | পেজের নাম | ধরন | বিবরণ |
| :--- | :--- | :--- | :--- |
| **Page 425** | Short Leave & Tour Register | Normal Page | নিজের আবেদনসমূহ, বর্তমান মাসের কোটা সামারি (৩টির মধ্যে কয়টি ব্যবহৃত) ও হিস্ট্রি |
| **Page 426** | Apply Short Leave / Tour | Modal Dialog Form | নতুন আবেদন দাখিল ও ড্রাফট এডিট করার ফর্ম |
| **Page 427** | Short Leave Approval Inbox | Normal / Modal | সুপারভাইজার (RP/HOD/HR) এর পেন্ডিং অনুমোদন ও অ্যাকশন পেজ |

---

## ৩. Page 425: Short Leave & Tour Register (আবেদনকারীর ড্যাশবোর্ড)

### Region 1: Monthly Quota Summary (Cards বা Static Content)
উপরে একটি সুন্দর ইনফো-বক্স যেখানে লগইন করা ব্যবহারকারীর বর্তমান মাসের কোটা প্রদর্শিত হবে:

```sql
SELECT 
    TO_CHAR(SYSDATE, 'FMMonth YYYY') AS current_month,
    3 AS max_quota,
    HRMS.fn_get_monthly_sl_count(:USER_ID, SYSDATE, 'SHORT_LEAVE', 'PERSONAL') AS used_quota,
    (3 - HRMS.fn_get_monthly_sl_count(:USER_ID, SYSDATE, 'SHORT_LEAVE', 'PERSONAL')) AS remaining_quota
FROM DUAL;
```
* **HTML Expression / Badge:**
  - `ব্যবহৃত: &USED_QUOTA. / ৩`
  - `অবশিষ্ট: &REMAINING_QUOTA. টি`

### Region 2: My Applications (Interactive Report)
- **Source Type:** SQL Query
- **SQL Query:**
```sql
SELECT 
    r.id,
    r.req_no,
    r.req_category_desc  AS category,
    r.purpose_type_desc  AS purpose_type,
    r.req_date_char      AS leave_date,
    r.out_time_char || ' - ' || r.in_time_char AS timings,
    r.duration_display   AS duration,
    r.reason_purpose     AS reason,
    r.destination_place  AS destination,
    r.status_display_text AS status,
    r.status             AS raw_status,
    -- Edit link for Drafts
    CASE WHEN r.status = 'D' THEN
        APEX_PAGE.GET_URL(
            p_page        => '426',
            p_clear_cache => '426',
            p_items       => 'P426_ID',
            p_values      => r.id
        )
    ELSE NULL END AS edit_url
FROM HRMS.v_short_leave_my_report r
WHERE r.empid = :USER_ID
ORDER BY r.req_date DESC, r.id DESC;
```

- **Top Button:** `APPLY_NEW`
  - Label: `+ Apply Short Leave / Tour`
  - Action: Redirect to Page 426 (Clear Cache 426, P426_ID="")

---

## ৪. Page 426: Apply Short Leave / Tour Form (আবেদন ফর্ম)

### ফর্মের আইটেমসমূহ (Page Items):

| Item Name | Type | Label | Default / Setting |
| :--- | :--- | :--- | :--- |
| `P426_ID` | Hidden | ID | Primary Key |
| `P426_EMPID` | Hidden | Employee ID | Value: `:USER_ID` |
| `P426_REQ_CATEGORY` | Radio Group | আবেদনের ধরন | Static LOV: `Short Leave;SHORT_LEAVE, Short Tour;SHORT_TOUR`. Default: `SHORT_LEAVE` |
| `P426_PURPOSE_TYPE` | Radio Group | উদ্দেশ্যের ধরন | Static LOV: `Personal;PERSONAL, Official;OFFICIAL`. Default: `PERSONAL` |
| `P426_REQ_DATE` | Date Picker | তারিখ (Date) | Format: `YYYY-MM-DD`, Default: `&APP_DATE.` |
| `P426_QUOTA_ALERT` | Display Only | মাসিক কোটা বার্তা | Dynamic (নিচে দেখুন) |
| `P426_OUT_TIME` | Text Field / Time Picker | শুরুর সময় (From Time) | Format: `HH:MI AM` (e.g. 10:30 AM) |
| `P426_IN_TIME` | Text Field / Time Picker | শেষ সময় (To Time) | Format: `HH:MI AM` (e.g. 12:00 PM) |
| `P426_DURATION` | Display Only | মোট সময় (Duration) | Auto-calculated |
| `P426_REASON_PURPOSE` | Textarea | কারণ / বিবরণ (Reason) | Required (বাধ্যতামূলক) |
| `P426_DESTINATION_PLACE` | Text Field | গন্তব্যস্থল (Destination) | Conditional: Only if `REQ_CATEGORY = 'SHORT_TOUR'` |
| `P426_TRANSPORT_MODE` | Select List | যাতায়াত মাধ্যম | LOV: Official Vehicle, Bus, Rickshaw, Personal, etc. |
| `P426_IS_EXPENSE_CLAIM` | Single Checkbox | খরচ ক্লেইম করবেন কি না? | 'Y'/'N' |
| `P426_ESTIMATED_EXPENSE` | Number Field | আনুমানিক খরচ | Conditional: If Expense Claim = 'Y' |
| `P426_CONTACT_DURING_ABS`| Text Field | জরুরি মোবাইল নম্বর | Employee Mobile |

---

### ডায়নামিক অ্যাকশন (Dynamic Actions on Page 426)

#### DA 1: Toggle Tour Fields (ট্যুর ফিল্ড দেখানো/লুকানো)
- **Event:** Change
- **Selection Type:** Item `P426_REQ_CATEGORY`
- **Client-side Condition:** Item = `SHORT_TOUR`
- **True Action:** Show `P426_DESTINATION_PLACE`, `P426_TRANSPORT_MODE`, `P426_IS_EXPENSE_CLAIM`, `P426_ESTIMATED_EXPENSE`.
- **False Action:** Hide above items.

#### DA 2: Show Live Monthly Quota Counter
- **Event:** Change
- **Selection Type:** Items `P426_REQ_DATE`, `P426_REQ_CATEGORY`, `P426_PURPOSE_TYPE`
- **Action:** Set Value (PL/SQL Function Body):
```sql
DECLARE
    l_used NUMBER;
BEGIN
    IF :P426_REQ_CATEGORY = 'SHORT_LEAVE' AND :P426_PURPOSE_TYPE = 'PERSONAL' THEN
        l_used := HRMS.fn_get_monthly_sl_count(
            p_empid        => :USER_ID,
            p_req_date     => TO_DATE(:P426_REQ_DATE, 'YYYY-MM-DD'),
            p_req_category => 'SHORT_LEAVE',
            p_purpose_type => 'PERSONAL',
            p_exclude_id   => :P426_ID
        );
        IF l_used >= 3 THEN
            RETURN '<span style="color:red; font-weight:bold;">⚠️ সতর্কতা: চলতি মাসে আপনি ইতোমধ্যে ৩টি শর্ট লিভ নিয়েছেন বা আবেদন করেছেন। আর আবেদন করা যাবে না।</span>';
        ELSE
            RETURN '<span style="color:green; font-weight:bold;">ℹ️ চলতি মাসে ব্যবহৃত: ' || l_used || '/৩ টি। অবশিষ্ট: ' || (3 - l_used) || ' টি।</span>';
        END IF;
    ELSE
        RETURN '<span style="color:#555;">অফিসিয়াল কাজের জন্য মাসিক কোটা প্রযোজ্য নয়।</span>';
    END IF;
END;
```

---

### ভ্যালিডেশন (Server-side Validation: Max 3 Per Month Rule)

Page Designer → Validations → Create Validation:
- **Name:** `VAL_SHORT_LEAVE_MONTHLY_QUOTA`
- **Type:** PL/SQL Function Returning Error Text
- **PL/SQL Code:**
```sql
DECLARE
    l_used NUMBER;
    l_date DATE;
BEGIN
    l_date := TO_DATE(:P426_REQ_DATE, 'YYYY-MM-DD');

    -- শুধুমাত্র Short Leave (Personal) এর ক্ষেত্রে ৩টির কোটা পরীক্ষা হবে
    IF :P426_REQ_CATEGORY = 'SHORT_LEAVE' AND :P426_PURPOSE_TYPE = 'PERSONAL' THEN
        l_used := HRMS.fn_get_monthly_sl_count(
            p_empid        => :USER_ID,
            p_req_date     => l_date,
            p_req_category => 'SHORT_LEAVE',
            p_purpose_type => 'PERSONAL',
            p_exclude_id   => :P426_ID
        );

        IF l_used >= 3 THEN
            RETURN 'মাসিক কোটা পূর্ণ হয়েছে! প্রতি মাসে সর্বোচ্চ ৩টি ব্যক্তিগত শর্ট লিভ অনুমোদিত। ' ||
                   TO_CHAR(l_date, 'FMMonth YYYY') || ' মাসে আপনি ইতোমধ্যে ' || l_used || 'টি শর্ট লিভ নিয়েছেন/আবেদন করেছেন।';
        END IF;
    END IF;
    RETURN NULL;
END;
```
- **Associated Item:** `P426_REQ_DATE`
- **When Button Pressed:** `CREATE`, `APPLY`, `SAVE`

---

### সাবমিট প্রসেস (Page 426 Submit Process)

Processing → Processes → `Process Short Leave Request`:
- **Type:** Execute Code (PL/SQL)
- **PL/SQL Code:**
```sql
DECLARE
    l_id       NUMBER := :P426_ID;
    l_req_date DATE;
    l_out_time DATE;
    l_in_time  DATE;
BEGIN
    l_req_date := TO_DATE(:P426_REQ_DATE, 'YYYY-MM-DD');
    l_out_time := TO_DATE(:P426_REQ_DATE || ' ' || :P426_OUT_TIME, 'YYYY-MM-DD HH12:MI AM');
    l_in_time  := TO_DATE(:P426_REQ_DATE || ' ' || :P426_IN_TIME, 'YYYY-MM-DD HH12:MI AM');

    -- ১. ড্রাফট সেভ
    HRMS.pkg_short_leave_approval.save_draft(
        p_id                => l_id,
        p_company_id        => :G_COM_ID,
        p_actor_id          => :USER_ID,
        p_empid             => :USER_ID,
        p_req_category      => :P426_REQ_CATEGORY,
        p_purpose_type      => :P426_PURPOSE_TYPE,
        p_req_date          => l_req_date,
        p_out_time          => l_out_time,
        p_in_time           => l_in_time,
        p_reason            => :P426_REASON_PURPOSE,
        p_destination       => :P426_DESTINATION_PLACE,
        p_contact           => :P426_CONTACT_DURING_ABS,
        p_transport_mode    => :P426_TRANSPORT_MODE,
        p_is_expense_claim  => :P426_IS_EXPENSE_CLAIM,
        p_estimated_expense => TO_NUMBER(:P426_ESTIMATED_EXPENSE),
        p_comments          => NULL
    );

    -- ২. যদি ইউজার সাবমিট/ফরওয়ার্ড বাটনে চাপ দেয় তাহলে রুটে পাঠানো হবে
    IF :REQUEST IN ('CREATE', 'APPLY', 'SUBMIT', 'FORWARD') THEN
        HRMS.pkg_short_leave_approval.submit_request(
            p_id         => l_id,
            p_company_id => :G_COM_ID,
            p_actor_id   => :USER_ID
        );
    END IF;

    :P426_ID := l_id;
END;
```
- **Server-side Condition:** Request IN (`'CREATE'`, `'APPLY'`, `'SAVE'`, `'SAVE_DRAFT'`, `'SUBMIT'`)

---

## ৫. Page 427: Short Leave Approval Inbox (অনুমোদন পেজ)

ম্যানেজার / সুপারভাইজার (RP) এবং HOD-দের জন্য পেন্ডিং লিস্ট:

### SQL Query for Approval Inbox:
```sql
SELECT 
    h.history_id,
    h.req_id,
    h.req_no,
    h.empcode || ' - ' || h.emp_name AS employee,
    h.department_name,
    h.designation_name,
    h.req_category,
    h.purpose_type,
    h.req_date_char AS leave_date,
    h.out_time_char || ' - ' || h.in_time_char AS timing,
    h.duration_display AS duration,
    h.reason_purpose AS reason,
    h.destination_place AS destination,
    h.monthly_sl_used || ' of 3 used' AS monthly_quota_status,
    h.applied_date
FROM HRMS.v_short_leave_pending_inbox h
WHERE h.approver_id = :USER_ID;
```

### Approver Actions (Approve / Reject):
- **APPROVE Process:**
```sql
HRMS.pkg_short_leave_approval.process_approval(
    p_history_id => :P427_HISTORY_ID,
    p_action     => 'APPROVED',
    p_actor_id   => :USER_ID,
    p_comments   => :P427_COMMENTS
);
```
- **REJECT Process:**
```sql
HRMS.pkg_short_leave_approval.process_approval(
    p_history_id => :P427_HISTORY_ID,
    p_action     => 'REJECTED',
    p_actor_id   => :USER_ID,
    p_comments   => :P427_COMMENTS
);
```

---

## ৬. সংক্ষেপ ও সুবিধা (Key Advantages)

1. **একই টেবিলে শর্ট লিভ এবং শর্ট ট্যুর:** একটি ইউনিফাইড টেবিল `SHORT_LEAVE_TOUR_REQ` ব্যবহারের ফলে ডাটাবেজ অপ্টিমাইজড থাকে এবং একই অ্যাপ্রুভাল ইঞ্জিন কাজ করে।
2. **কঠোর মাসিক কোটা এনফোর্সমেন্ট:** ডাটাবেজ ট্রিগার, ফাংশন, প্যাকেজ এবং APEX ফর্ম ভ্যালিডেশন—সব লেভেলেই **প্রতি মাসে সর্বোচ্চ ৩টি শর্ট লিভ** নিশ্চিত করা হয়েছে।
3. **লাইভ কোটা ট্র্যাকিং:** পেজের ভেতরে ইউজার আবেদন করার সময়ই দেখতে পারবে সে কয়টি লিভ ইতোমধ্যে নিয়েছে এবং কয়টি বাকি আছে।
