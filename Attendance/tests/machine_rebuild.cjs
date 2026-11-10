// Runs the actual view, MERGE source queries, and MERGE updates with SQLite.
// Oracle PL/SQL compilation, savepoints, commits and locks require Oracle QA.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const { DatabaseSync } = require('node:sqlite');
const root = path.resolve(__dirname, '..');
const read = name => fs.readFileSync(path.join(root, name), 'utf8');
const db = new DatabaseSync(':memory:');
const day = text => Date.parse(text.length === 10 ? text + 'T00:00:00Z' : text + 'Z') / 86400000;
const today = day('2026-11-04');
const strip = text => text.replace(/\/\*[\s\S]*?\*\//g, '').replace(/--[^\n]*/g, '');
db.function('SYSDATE_FN', () => today);
db.function('TO_NUMBER', value => value == null ? null : Number(value));
db.function('TO_DATE', (value, format) => {
    assert.equal(format, 'YYYY-MM-DD');
    return value == null ? null : day(value);
});
db.function('TRUNC', n => n == null ? null : BigInt(Math.floor(n)));
db.function('MOD', (n, divisor) => n == null ? null : n % divisor);
db.function('LPAD', (value, length, pad) => value == null ? null : String(value).padStart(length, pad));
db.function('GREATEST', { varargs: true }, (...args) => args.includes(null) ? null : Math.max(...args));
db.function('LEAST', { varargs: true }, (...args) => args.includes(null) ? null : Math.min(...args));
db.function('DECODE', { varargs: true }, (value, search, same, different) => {
    const equal = value == null || search == null ? value === search
        : typeof value === 'number' || typeof search === 'number'
            ? Number(value) === Number(search) : value === search;
    return equal ? same : different;
});
db.function('TO_CHAR', { varargs: true }, (value, format) => {
    if (value == null) return null;
    if (format == null) return String(value);
    const date = new Date(Math.round(value * 86400000));
    const iso = date.toISOString().slice(0, 10);
    if (format === 'YYYY-MM-DD') return iso;
    if (format === 'YYYY-MM-DD HH24:MI:SS') return date.toISOString().slice(0, 19).replace('T', ' ');
    if (format === 'MM/DD/YYYY') return iso.slice(5, 7) + '/' + iso.slice(8) + '/' + iso.slice(0, 4);
    if (format === 'MMDD') return iso.slice(5, 7) + iso.slice(8);
    if (format === 'DAY') return ['SUNDAY', 'MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY', 'FRIDAY', 'SATURDAY'][date.getUTCDay()];
    throw new Error('Unsupported TO_CHAR format: ' + format);
});
db.function('TO_TIMESTAMP', (value, format) => {
    assert.equal(format, 'MM/DD/YYYY HH:MI AM');
    const match = value.match(/^(\d{2})\/(\d{2})\/(\d{4})\s+(\d{1,2}):(\d{2})\s*(AM|PM)$/i);
    assert.ok(match, 'Valid office clock: ' + value);
    const [, month, date, year, hour, minute, meridian] = match;
    return Date.UTC(+year, +month - 1, +date, +hour % 12 + (meridian.toUpperCase() === 'PM' ? 12 : 0), +minute) / 86400000;
});
function sql(source) {
    return strip(source).replace(/\bHRMS\./gi, '').replace(/\bNVL\s*\(/gi, 'IFNULL(')
        .replace(/\bSYSDATE\b/g, 'SYSDATE_FN()').replace(/\bAS DATE\b/g, 'AS REAL')
        .replace(/INTERVAL '1' DAY/g, '1').replace(/\bWITH\b/g, 'WITH RECURSIVE')
        .replace(/\/\s*(\d+)\b/g, '/ $1.0')
        .replace(/\b(l_from_date|l_to_date|p_emp_id)\b/g, ':$1');
}
function execute(statement, values = {}, method = 'all') {
    const parameterText = statement.replace(/'(?:''|[^'])*'/g, "''");
    const parameters = Object.fromEntries([...parameterText.matchAll(/:(\w+)/g)].map(m => {
        assert.ok(Object.hasOwn(values, m[1]), 'Bound parameter: ' + m[1]);
        return [m[1], values[m[1]]];
    }));
    return db.prepare(statement)[method](parameters);
}
db.exec(`
    CREATE TABLE dual (dummy TEXT);
    INSERT INTO dual VALUES ('X');
    CREATE TABLE employees (id INTEGER PRIMARY KEY, mc_id INTEGER, emp_id TEXT, branch_id INTEGER, com_id INTEGER);
    CREATE TABLE office_schedule (location_id INTEGER, com_id INTEGER, schedule_start_date REAL,
        schedule_end_date REAL, office_start TEXT, office_end TEXT, weekend1 TEXT, weekend2 TEXT);
    CREATE TABLE v_att_gen2 (emp_id INTEGER, com_id INTEGER, mc_id INTEGER, attendance_date REAL,
        dayofweek TEXT, regular_in_time REAL, regular_out_time REAL, hflag TEXT);
    CREATE TABLE att_mcdata (userid INTEGER, atttime REAL, device_id INTEGER DEFAULT 1, flag TEXT DEFAULT 'N', status INTEGER);
    CREATE TABLE t_holiday (is_recurring INTEGER, holiday_date REAL);
    CREATE TABLE attendance_details (attendance_id INTEGER PRIMARY KEY, emp_id INTEGER, mc_id INTEGER,
        attendance_date REAL, dayofweek TEXT, regular_in_time REAL, regular_out_time REAL, com_id INTEGER,
        in_time REAL, out_time REAL, duty_hours TEXT, late_in TEXT, early_out TEXT, status TEXT, remarks TEXT);
`);
const officeView = sql(read('V_ATT_GEN1.sql').split(/\bAS\s+(?=WITH)/i)[1]).replace(/;\s*\/\s*$/, '');
assert.ok(officeView.startsWith('WITH RECURSIVE'));
db.exec('CREATE VIEW v_att_gen1 AS ' + officeView);
// Dependency fixture: the V_ATT_GEN union supplied by the user.
db.exec(`CREATE VIEW v_att_gen AS
    SELECT id AS emp_id, mc_id, day_date AS attendance_date, TRIM(TO_CHAR(day_date, 'DAY')) AS dayofweek,
           regular_in_time, regular_out_time, com_id FROM v_att_gen1 WHERE com_id <> 3
    UNION ALL SELECT emp_id, mc_id, attendance_date, dayofweek, regular_in_time, regular_out_time,
           com_id FROM v_att_gen2 WHERE com_id = 3`);

function closeParen(text, start) {
    let depth = 0, quoted = false;
    for (let i = start; i < text.length; i++) {
        if (text[i] === "'") {
            if (quoted && text[i + 1] === "'") { i++; continue; }
            quoted = !quoted;
        }
        if (quoted) continue;
        if (text[i] === '(') depth++;
        if (text[i] === ')' && --depth === 0) return i;
    }
    throw new Error('Unclosed USING query');
}
function merges(file) {
    const source = strip(read(file));
    return [...source.matchAll(/MERGE INTO HRMS\.attendance_details ad\s+USING\s*\(/gi)].map(match => {
        const open = match.index + match[0].length - 1;
        const close = closeParen(source, open);
        const tail = source.slice(close + 1, source.indexOf(';', close));
        const alias = tail.match(/^\s*(\w+)\s+ON/)[1];
        const update = tail.match(/WHEN MATCHED THEN\s+UPDATE\s+SET([\s\S]*?)(?=WHEN NOT MATCHED THEN|$)/i)[1];
        const where = update.search(/\bWHERE\b/i);
        assert.ok(where > 0);
        const bindings = text => text.replace(new RegExp('\\b' + alias + '\\.(\\w+)', 'g'), ':src_$1');
        const assignments = update.slice(0, where).replace(/\bad\.(\w+)\s*=/g, '$1 =');
        const predicate = update.slice(where + 5);
        const insert = tail.match(/WHEN NOT MATCHED THEN\s+INSERT\s*\(([\s\S]*?)\)\s+VALUES\s*\(([\s\S]*?)\)/i);
        return {
            query: sql(source.slice(open + 1, close)),
            update: sql(bindings('UPDATE attendance_details AS ad SET ' + assignments
                + ' WHERE ad.attendance_id = :target_id AND (' + predicate + ')')),
            insert: insert && sql(bindings('INSERT INTO attendance_details (' + insert[1]
                + ') VALUES (' + insert[2].replace(/HRMS\.s_attdata\.NEXTVAL/gi, 'NULL') + ')')),
        };
    });
}
const procedures = new Map(['P_ATT_SCHEDULE.sql', 'P_ATT_CONT_SHIFT_FAST.sql', 'P_ATT_UPDATE_DETAILS.sql']
    .map(name => [name, merges(name)]));
function run(file, from, to, empId = null) {
    const values = { l_from_date: from, l_to_date: to + 1, p_emp_id: empId };
    for (const merge of procedures.get(file)) {
        for (const row of execute(merge.query, values)) {
            const targets = row.attendance_id == null
                ? execute('SELECT attendance_id FROM attendance_details WHERE emp_id=:emp AND TRUNC(attendance_date)=:date',
                    { emp: row.emp_id, date: row.attendance_date })
                : execute('SELECT attendance_id FROM attendance_details WHERE attendance_id=:id', { id: row.attendance_id });
            const bindings = { ...values, ...Object.fromEntries(Object.entries(row).map(([k, v]) => ['src_' + k, v])) };
            if (!targets.length && merge.insert) execute(merge.insert, bindings, 'run');
            for (const target of targets) execute(merge.update, { ...bindings, target_id: target.attendance_id }, 'run');
        }
    }
}
const wrapper = read('P_ATT_REBUILD_MACHINE.sql');
const calls = [...wrapper.matchAll(/HRMS\.(p_att_\w+)\(l_from_date, l_to_date, p_commit => 0\)/g)].map(m => m[1].toUpperCase() + '.sql');
assert.deepEqual(calls, ['P_ATT_SCHEDULE.sql', 'P_ATT_CONT_SHIFT_FAST.sql', 'P_ATT_UPDATE_DETAILS.sql']);
assert.match(wrapper, /l_from_date := TRUNC\(p_from_date\) - 1/);
assert.match(wrapper, /l_to_date := TRUNC\(p_to_date\) \+ 1/);
function rebuild(from, to = from) {
    for (const file of calls) run(file, from - 1, to + 1);
}
function punch(user, when, status = 1, flag = 'Y') {
    execute('INSERT INTO att_mcdata(userid,atttime,status,flag) VALUES(:user,:when,:status,:flag)',
        { user, when: day(when), status, flag }, 'run');
}
function attendance(emp, when) {
    return execute('SELECT * FROM attendance_details WHERE emp_id=:emp AND attendance_date=:when', { emp, when: day(when) })[0];
}
function diagnose(emp, when) {
    const source = read('DIAGNOSE_ATTENDANCE_DAY.sql');
    const start = source.indexOf('WITH source_schedule AS');
    const end = source.indexOf('\nUNDEFINE', start);
    assert.ok(start > 0 && end > start);
    return execute(sql(source.slice(start, end)
        .replace(/&&att_emp_id/g, String(emp)).replace(/&&att_day/g, when)));
}
function near(actual, expected, label) { assert.ok(Math.abs(actual - expected) < 1e-8, label); }
const snapshot = () => JSON.stringify(db.prepare('SELECT * FROM attendance_details ORDER BY attendance_id').all());

db.exec("INSERT INTO employees VALUES(1,101,'E1',10,1),(2,202,'E2',20,3),(3,303,'E3',11,1)");
execute(`INSERT INTO office_schedule VALUES(10,1,:start,:end,'09:00 AM','05:00 PM','FRIDAY',NULL),
    (11,1,:start,:end,'10:00 PM','06:00 AM','MONDAY',NULL)`,
    { start: day('2026-08-01'), end: day('2026-12-31') }, 'run');
const old = day('2026-08-10'); // An earlier month, Monday.
punch(101, '2026-08-10T08:55:00');
punch(101, '2026-08-10T17:10:00');
rebuild(old);
let row = attendance(1, '2026-08-10');
assert.equal(row.status, 'P', 'Another branch Monday weekend must not mark E1 as off');
assert.equal(row.duty_hours, '8:15');
assert.equal(Number(row.late_in), 0);
let diagnostic = diagnose(1, '2026-08-10');
assert.equal(diagnostic.length, 2);
assert.ok(diagnostic.every(r => r.status_gate === 'ACCEPTED' && r.selection === 'SELECTED'));
assert.ok(diagnostic.every(r => r.assigned_day === '2026-08-10'));
const originalId = row.attendance_id;
let before = snapshot(); rebuild(old); assert.equal(snapshot(), before, 'Rebuild is idempotent');

execute('UPDATE att_mcdata SET atttime=:new WHERE userid=101 AND atttime=:old',
    { old: day('2026-08-10T17:10:00'), new: day('2026-08-10T16:30:00') }, 'run');
execute('UPDATE att_mcdata SET atttime=:new WHERE userid=101 AND atttime=:old',
    { old: day('2026-08-10T08:55:00'), new: day('2026-08-10T09:15:00') }, 'run');
rebuild(old);
row = attendance(1, '2026-08-10');
assert.equal(row.attendance_id, originalId, 'Existing history is updated in place');
assert.equal(row.duty_hours, '7:15');
assert.equal(Number(row.late_in), 15);
assert.equal(Number(row.early_out), 30);
db.exec('UPDATE att_mcdata SET status=0 WHERE userid=101');
rebuild(old);
row = attendance(1, '2026-08-10');
assert.equal(row.in_time, null); assert.equal(row.out_time, null);
assert.equal(row.duty_hours, null); assert.equal(row.status, 'A');
diagnostic = diagnose(1, '2026-08-10');
assert.ok(diagnostic.every(r => r.status_gate === 'EXCLUDED_STATUS' && r.selection === 'NOT_SELECTED'));

punch(303, '2026-08-10T21:55:00');
punch(303, '2026-08-11T06:05:00');
rebuild(old);
row = attendance(3, '2026-08-10');
near(row.regular_out_time, day('2026-08-11T06:00:00'), 'Office night OUT is on next date');
assert.equal(row.duty_hours, '8:10');

execute(`INSERT INTO v_att_gen2 VALUES
    (2,3,202,:night,'THURSDAY',:first_in,:boundary,'Office Day'),
    (2,3,202,:date,'FRIDAY',:boundary,:last_out,'Office Day')`, {
    night: day('2026-08-20'), date: day('2026-08-21'), first_in: day('2026-08-20T22:00:00'),
    boundary: day('2026-08-21T06:00:00'), last_out: day('2026-08-21T14:00:00') }, 'run');
punch(202, '2026-08-20T21:50:00');
punch(202, '2026-08-21T14:01:00');
rebuild(day('2026-08-21'));
let night = attendance(2, '2026-08-20'), next = attendance(2, '2026-08-21');
near(night.out_time, day('2026-08-21T06:00:00'), 'Previous boundary rebuilt across requested start');
near(next.in_time, night.out_time, 'Shared continuous boundary');
assert.equal(night.duty_hours, '8:10'); assert.equal(next.duty_hours, '8:01');
before = snapshot(); rebuild(day('2026-08-21')); assert.equal(snapshot(), before);

// Exercise the moved bridge without calling the separate continuous procedure.
run('P_ATT_SCHEDULE.sql', day('2026-08-20'), day('2026-08-21'));
run('P_ATT_UPDATE_DETAILS.sql', day('2026-08-20'), day('2026-08-21'));
assert.equal(attendance(2, '2026-08-20').duty_hours, '8:10');
assert.equal(attendance(2, '2026-08-21').duty_hours, '8:01');

execute('DELETE FROM att_mcdata WHERE userid=202 AND atttime=:when', { when: day('2026-08-21T14:01:00') }, 'run');
rebuild(day('2026-08-21'));
assert.equal(attendance(2, '2026-08-21').in_time, null, 'Deleted evidence removes derived boundary');
assert.equal(attendance(2, '2026-08-20').duty_hours, '0:00', 'Remaining single punch is recalculated');
punch(202, '2026-08-21T14:01:00'); rebuild(day('2026-08-21'));
execute("UPDATE v_att_gen2 SET regular_in_time=NULL, regular_out_time=NULL, hflag='Weekly Holiday' WHERE attendance_date=:date",
    { date: day('2026-08-21') }, 'run');
rebuild(day('2026-08-21'));
row = attendance(2, '2026-08-21');
assert.equal(row.in_time, null); assert.equal(row.out_time, null);
assert.equal(row.duty_hours, null); assert.equal(row.status, 'W');
assert.equal(row.remarks, 'Weekly Holiday');
diagnostic = diagnose(2, '2026-08-21');
assert.ok(diagnostic.some(r => r.raw_punch === '2026-08-21 14:01:00' && r.selection === 'NO_MATCHING_WINDOW'));

// Manual approval recalculates one employee without changing other applicants.
db.exec("UPDATE attendance_details SET duty_hours='untouched' WHERE emp_id=3");
const otherBefore = JSON.stringify(db.prepare('SELECT * FROM attendance_details WHERE emp_id=3').all());
execute('UPDATE attendance_details SET in_time=:start,out_time=:end WHERE emp_id=1 AND attendance_date=:date',
    { start: day('2026-08-10T09:00:00'), end: day('2026-08-10T17:00:00'), date: old }, 'run');
run('P_ATT_UPDATE_DETAILS.sql', old, old, 1);
assert.equal(attendance(1, '2026-08-10').duty_hours, '8:00');
assert.equal(JSON.stringify(db.prepare('SELECT * FROM attendance_details WHERE emp_id=3').all()), otherBefore,
    'Scoped metric refresh leaves other employees unchanged');

db.exec('DELETE FROM office_schedule');
assert.equal(db.prepare('SELECT COUNT(*) AS n FROM v_att_gen1').get().n, 0, 'Empty configuration yields no invalid date seed');
console.log('PASS: actual SQL for historical upsert, repeat rebuilds, punch edits/status changes/deletion, next-day office shifts, branch weekends, continuous boundaries at range edges, bridge-before-metrics, working-to-holiday resets, employee-scoped recalculation, and read-only diagnosis of selected/excluded/unmatched punches. Oracle PL/SQL runtime and transactions remain unverified.');
