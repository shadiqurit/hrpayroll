# Page 482 confirmation-letter regions

Configure two **PL/SQL Dynamic Content** regions on Page 482.

## Region 1 — grades 1–14

Keep the existing English PL/SQL source. Set **Server-side Condition** as:

- Type: `Rows returned`
- SQL Query (do not include a trailing semicolon in the APEX field):

```sql
SELECT 1
  FROM hr_confirmation c
 WHERE c.confirm_id = TO_NUMBER(:P482_CONFIRM_ID)
   AND c.grade_order BETWEEN 1 AND 14
```

## Region 2 — grades 15–20

Create a second **PL/SQL Dynamic Content** region and paste the complete source
from `page_482_region_2_bengali_confirmation_letter.sql`. Set **Server-side
Condition** as:

- Type: `Rows returned`
- SQL Query (do not include a trailing semicolon in the APEX field):

```sql
SELECT 1
  FROM hr_confirmation c
 WHERE c.confirm_id = TO_NUMBER(:P482_CONFIRM_ID)
   AND c.grade_order BETWEEN 15 AND 20
```

The Bengali region includes its own `printBengaliConfirmation()` function. It
prints the letter in a clean browser window, preventing the APEX theme and
other page regions from changing the print layout. Only one letter region is
rendered for a confirmation record, so the shared `divToPrint` ID remains
unique on the page.

The Bengali source is UTF-8. Import/paste it without changing encoding. For
best rendering, install or serve a Bengali font such as **Noto Sans Bengali**;
the CSS also includes common fallback fonts.
