// Executes the actual posting/type-resolution/balance SQL in SQLite (Node 24).
// PL/SQL control flow, Oracle locks, trigger compilation and savepoints still
// require TEST_COMPANY_APPROVAL.sql in a test Oracle database.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const { DatabaseSync } = require('node:sqlite');
const root = path.resolve(__dirname, '..');
const read = name => fs.readFileSync(path.join(root, name), 'utf8');
const db = new DatabaseSync(':memory:');
db.function('TRUNC', value => value == null ? null : typeof value === 'number' ? Math.trunc(value) : String(value).slice(0, 10));
db.function('TO_NUMBER', value => Number(value));
const source = read('POST_LEAVE_CONSUMPTION.sql');
function sql(text) {
    return text.replace(/\bHRMS\./g, '').replace(/\bNVL\(/g, 'IFNULL(')
        .replace(/\s+INTO\s+[\s\S]*?\s+FROM/, ' FROM')
        .replace(/\s+FOR UPDATE/g, '').replace(/\bSYSDATE\b/g, 'CURRENT_TIMESTAMP')
        .replace(/\bl_step\.id\b/g, ':history_id').replace(/\bl_step\.approver_level\b/g, ':role')
        .replace(/\bl_request\.([a-z_]+)/g, ':request_$1')
        .replace(/\b(p_leave_id|p_company_id|p_actor_id|p_comments|p_active_only|l_value|l_type|l_year|l_allocated|l_consumed|l_company|l_action)\b/g, ':$1');
}
function query(text, values = {}, mode = 'all') {
    const compiled = sql(text);
    const params = Object.fromEntries([...compiled.matchAll(/:(\w+)/g)].map(match => [match[1], values[match[1]]]));
    return db.prepare(compiled)[mode](params);
}
db.exec(`
 CREATE TABLE employees (id INTEGER PRIMARY KEY, com_id INTEGER, status INTEGER);
 CREATE TABLE leave_types (lt_id INTEGER PRIMARY KEY, short_code TEXT, com_id INTEGER, active_flag TEXT);
 CREATE TABLE leave_request (leave_id INTEGER PRIMARY KEY, empid INTEGER, leave_type TEXT,
   leave_status TEXT, request_status TEXT, l_start_date TEXT, l_end_date TEXT,
   proposed_days REAL, leave_balance REAL DEFAULT 10, leave_taken REAL DEFAULT 0,
   upd_date TEXT, upd_by INTEGER);
 CREATE TABLE leave_app_history (id INTEGER PRIMARY KEY, leave_id INTEGER,
   approver_level TEXT, approver_id INTEGER, approval_status TEXT, com_id INTEGER,
   approval_date TEXT, comments TEXT, upd_date TEXT, upd_by INTEGER);
 CREATE TABLE leave_allocation (empid INTEGER, leave_type_id INTEGER, allocation_year INTEGER,
   allocated_days REAL, UNIQUE(empid,leave_type_id,allocation_year));
 CREATE TABLE leave_consumption (consumption_id INTEGER PRIMARY KEY, leave_id INTEGER UNIQUE
   REFERENCES leave_request(leave_id), empid INTEGER, leave_type_id INTEGER, consumed_days REAL,
   consumption_date TEXT, start_date TEXT, end_date TEXT, ent_date TEXT, ent_by INTEGER,
   com_id INTEGER, consum_year INTEGER,
   CHECK(leave_id IS NULL OR (consum_year IS NOT NULL AND consum_year=TRUNC(consum_year) AND consumed_days>0)));
 INSERT INTO employees VALUES (10,7,1),(11,7,1),(102,7,1),(105,7,1);
 INSERT INTO leave_types VALUES (1,'CL',NULL,'Y'),(2,'CL',7,'Y'),(3,'SL',8,'Y'),
   (4,'EL',NULL,'Y'),(5,'OLD',NULL,'N');
 INSERT INTO leave_allocation VALUES (10,2,2099,10),(11,2,2099,100),(10,4,2099,30),(10,2,2100,20);
 INSERT INTO leave_consumption (empid,leave_type_id,consumed_days,consum_year,start_date,end_date)
 VALUES (10,2,2,2099,'2099-01-01','2099-01-02'),(11,2,50,2099,'2099-01-01','2099-02-19');
`);
db.exec('CREATE VIEW v_leave_year_balance AS ' + sql(read('V_LEAVE_YEAR_BALANCE.sql').split(/\bAS\s*\r?\n/)[1]));
const typeQueries = [...read('FN_LEAVE_TYPE_ID.sql').matchAll(/SELECT (?:lt_id|lt\.lt_id) INTO l_id[\s\S]*?;/g)].map(match => match[0]);
assert.equal(typeQueries.length, 2);
function resolveType(value, company, activeOnly = 1) {
    const normalized = String(value).trim().toUpperCase();
    const rows = query(typeQueries[/^[0-9]+$/.test(normalized) ? 0 : 1],
        { l_value: normalized, p_company_id: company, p_active_only: activeOnly });
    if (rows.length !== 1) throw new Error(rows.length ? 'Ambiguous type' : 'Missing type');
    return rows[0].lt_id;
}
assert.equal(resolveType('cl', 7), 2);
assert.equal(resolveType('CL', 9), 1);
assert.equal(resolveType('01', 7), 1, 'Explicit numeric global ID stays that ID');
assert.throws(() => resolveType('3', 7), /Missing type/);
assert.throws(() => resolveType('5', 7), /Missing type/);
assert.equal(resolveType('5', 7, 0), 5);
db.exec("INSERT INTO leave_types VALUES(6,'CL',7,'Y');");
assert.throws(() => resolveType('CL', 7), /Ambiguous type/);
db.exec('DELETE FROM leave_types WHERE lt_id=6;');

const selects = [...source.matchAll(/SELECT [\s\S]*?;/g)].map(match => match[0]);
assert.equal(selects.length, 9, 'Review SQL extraction when the procedure changes');
const [loadRequest, loadCompany, activeActor, finalActor, allocation,
    existingPosting, manualMatch, usedBefore, usedAfter] = selects;
const insert = source.match(/INSERT INTO leave_consumption[\s\S]*?;/)[0];
const snapshot = source.match(/UPDATE leave_request[\s\S]*?;/)[0];
const formattedBalance = read('F_LEAVE_BA.sql').match(/SELECT NVL\(MAX\(balance_days\)[\s\S]*?;/)[0]
    .replace(/\bp_empid\b/g, ':empid').replace(/\bp_leave_type_id\b/g, ':type_id').replace(/\bp_year\b/g, ':year');
function balance(year = 2099, type = 2) {
    return db.prepare(sql(formattedBalance)).get({ empid: 10, type_id: type, year });
}
function request(id, days, start = '2099-12-31', end = '2100-01-02') {
    db.prepare("INSERT INTO leave_request(leave_id,empid,leave_type,leave_status,request_status,l_start_date,l_end_date,proposed_days) VALUES(?,10,'CL','A','A',?,?,?)").run(id, start, end, days);
    db.prepare("INSERT INTO leave_app_history(leave_id,approver_level,approver_id,approval_status,com_id) VALUES(?,'HOD',102,'APPROVED',7)").run(id);
}
function post(id, actor = 102) {
    const values = { p_leave_id: id, p_company_id: 7, p_actor_id: actor };
    const req = query(loadRequest, values)[0];
    assert.ok(req);
    Object.assign(values, Object.fromEntries(Object.entries(req).map(([key, value]) => ['request_' + key, value])));
    const company = Object.values(query(loadCompany, values)[0])[0];
    values.l_company = company;
    if (company !== 7 || req.leave_status !== 'A' || req.request_status !== 'A') throw new Error('Not approved');
    if (Object.values(query(activeActor, values)[0])[0] !== 1) throw new Error('Inactive actor');
    const final = Object.values(query(finalActor, values)[0]);
    if (final[0] !== 1 || final[1] !== 1) throw new Error('Wrong final actor');
    values.l_type = resolveType(req.leave_type, company);
    values.l_year = Number(req.l_start_date.slice(0, 4));
    const accounts = query(allocation, values);
    if (accounts.length !== 1) throw new Error('Missing allocation');
    values.l_allocated = accounts[0].allocated_days;
    const exists = Object.values(query(existingPosting, values)[0]);
    if (exists[0]) {
        if (exists[0] !== 1 || exists[1] !== 1) throw new Error('Posting mismatch');
    } else {
        if (Object.values(query(manualMatch, values)[0])[0]) throw new Error('Manual match');
        values.l_consumed = Object.values(query(usedBefore, values)[0])[0];
        if (req.proposed_days > values.l_allocated - values.l_consumed) throw new Error('Insufficient balance');
        query(insert, values, 'run');
    }
    values.l_consumed = Object.values(query(usedAfter, values)[0])[0];
    query(snapshot, values, 'run');
}
assert.deepEqual(Object.values(balance()), [8, 2]);
assert.deepEqual(Object.values(balance(2200)), [0, 0]);
request(1001, 3);
assert.throws(() => post(1001,105), /Wrong final actor/);
post(1001);
assert.deepEqual(Object.values(balance()), [5, 5]);
assert.deepEqual(Object.values(balance(2100)), [20, 0], 'No cross-year split');
const posted = db.prepare('SELECT * FROM leave_consumption WHERE leave_id=1001').get();
assert.equal(posted.consum_year, 2099);
assert.equal(posted.consumed_days, 3);
assert.equal(posted.end_date, '2100-01-02');
assert.equal(posted.ent_by, 102);
assert.equal(posted.com_id, 7);
post(1001);
assert.deepEqual(Object.values(balance()), [5,5], 'Retry does not spend twice');
assert.throws(() => db.prepare('INSERT INTO leave_consumption(leave_id,consumed_days,consum_year) VALUES(1001,3,2099)').run(), /UNIQUE/);
assert.throws(() => db.prepare('INSERT INTO leave_consumption(leave_id,consumed_days) VALUES(1002,1)').run(), /CHECK/);
request(1002,0.5,'2099-02-01','2099-02-01');
post(1002);
assert.deepEqual(Object.values(balance()), [4.5,5.5]);
request(1003,4.5,'2099-03-01','2099-03-05');
post(1003);
assert.deepEqual(Object.values(balance()), [0,10], 'Exact remaining balance is allowed');
request(1004,0.5,'2099-04-01','2099-04-01');
assert.throws(() => post(1004), /Insufficient balance/);
assert.equal(db.prepare('SELECT COUNT(*) AS n FROM leave_consumption WHERE leave_id=1004').get().n, 0);
request(1005,1,'2200-01-01','2200-01-01');
assert.throws(() => post(1005), /Missing allocation/);
db.prepare('UPDATE leave_request SET proposed_days=4 WHERE leave_id=1001').run();
assert.throws(() => post(1001), /Posting mismatch/);
db.prepare('UPDATE leave_request SET proposed_days=3 WHERE leave_id=1001').run();
request(1006,2,'2099-01-01','2099-01-02');
assert.throws(() => post(1006), /Manual match/);
assert.equal(db.prepare('SELECT COUNT(*) AS n FROM leave_consumption WHERE leave_id=1006').get().n, 0);
assert.equal(db.prepare('SELECT allocated_days FROM leave_allocation WHERE empid=10 AND leave_type_id=2 AND allocation_year=2099').get().allocated_days, 10);
assert.equal(db.prepare('SELECT balance_days FROM v_leave_year_balance WHERE empid=11 AND leave_type_id=2 AND leave_year=2099').get().balance_days, 50);
assert.equal(db.prepare('SELECT balance_days FROM v_leave_year_balance WHERE empid=10 AND leave_type_id=4 AND leave_year=2099').get().balance_days, 30);

// Exercise the production final-decision UPDATE statements and an outer rollback
// when posting fails. This checks the SQL contract, not Oracle SAVEPOINT runtime.
request(1007,1,'2099-05-01','2099-05-01');
db.exec("UPDATE leave_request SET leave_status='F',request_status='F' WHERE leave_id=1007; UPDATE leave_app_history SET approval_status='PENDING' WHERE leave_id=1007;");
const historyId = db.prepare('SELECT id FROM leave_app_history WHERE leave_id=1007').get().id;
const packageSource = read('PKG_LEAVE_APPROVAL.sql');
const resolveActor = packageSource.match(/UPDATE leave_app_history\s+SET[\s\S]*?;/)[0];
const resolveRequest = packageSource.match(/UPDATE leave_request\s+SET leave_status = CASE[\s\S]*?;/)[0];
const finalValues = { p_leave_id:1007, p_actor_id:102, p_comments:'Final',
    history_id:historyId, role:'HOD', l_action:'APPROVE' };
db.exec('BEGIN;');
try {
    query(resolveActor,finalValues,'run');
    query(resolveRequest,finalValues,'run');
    post(1007);
    db.exec('COMMIT;');
    assert.fail('Insufficient posting should fail');
} catch (error) {
    db.exec('ROLLBACK;');
    assert.match(error.message,/Insufficient balance/);
}
assert.equal(db.prepare('SELECT leave_status FROM leave_request WHERE leave_id=1007').get().leave_status,'F');
assert.equal(db.prepare('SELECT approval_status FROM leave_app_history WHERE leave_id=1007').get().approval_status,'PENDING');
assert.equal(db.prepare('SELECT COUNT(*) AS n FROM leave_consumption WHERE leave_id=1007').get().n,0);
assert.deepEqual(Object.values(balance()),[0,10]);
post(1001);
assert.deepEqual(Object.values(balance()),[0,10], 'Retry remains harmless even after the rest of the balance is spent');
db.close();
console.log('PASS: actual type lookup, allocation/consumption SQL, full start-year charge, fractional/exact balance, insufficient/missing allocation, safe retries, unique link, manual duplicate/mismatch checks and live balance totals. Oracle execution/locking remains unverified.');
