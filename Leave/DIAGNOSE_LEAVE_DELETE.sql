-- Read-only: identify the actual child table/column named in ORA-02292.
SELECT fk.owner AS child_owner,
       fk.table_name AS child_table,
       fk.constraint_name,
       fc.column_name AS child_column,
       pk.owner AS parent_owner,
       pk.table_name AS parent_table,
       pc.column_name AS parent_column,
       fk.delete_rule,
       fk.status
  FROM all_constraints fk
  JOIN all_cons_columns fc
    ON fc.owner = fk.owner AND fc.constraint_name = fk.constraint_name
  JOIN all_constraints pk
    ON pk.owner = fk.r_owner AND pk.constraint_name = fk.r_constraint_name
  JOIN all_cons_columns pc
    ON pc.owner = pk.owner AND pc.constraint_name = pk.constraint_name
   AND pc.position = fc.position
 WHERE fk.owner = 'HRMS'
   AND fk.constraint_name = 'SYS_C0020159'
   AND fk.constraint_type = 'R'
 ORDER BY fc.position;

-- List every child FK referencing LEAVE_REQUEST, including other schemas.
SELECT fk.owner AS child_owner,
       fk.table_name AS child_table,
       fk.constraint_name,
       fk.delete_rule,
       fk.status
  FROM all_constraints fk
  JOIN all_constraints pk
    ON pk.owner = fk.r_owner AND pk.constraint_name = fk.r_constraint_name
 WHERE fk.constraint_type = 'R'
   AND pk.owner = 'HRMS'
   AND pk.table_name = 'LEAVE_REQUEST'
 ORDER BY fk.owner, fk.table_name, fk.constraint_name;

SELECT object_name, object_type, status
  FROM all_objects
 WHERE owner = 'HRMS'
   AND object_name IN ('DELETE_LEAVE_REQUEST', 'TRG_LEAVE_REQUEST_DELETE');

SELECT trigger_name, status, triggering_event
  FROM all_triggers
 WHERE owner = 'HRMS'
   AND table_name = 'LEAVE_REQUEST';

SELECT name, type, line, position, text
  FROM all_errors
 WHERE owner = 'HRMS'
   AND name IN ('DELETE_LEAVE_REQUEST', 'TRG_LEAVE_REQUEST_DELETE')
   AND attribute = 'ERROR'
 ORDER BY name, sequence;
