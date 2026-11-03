// Offline checks of the actual package SQL and report query using Node 24 SQLite.
// Oracle compilation, PL/SQL routing, locks and savepoints need the Oracle test script.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const { DatabaseSync } = require('node:sqlite');
const root = path.resolve(__dirname, '..');
const source = fs.readFileSync(path.join(root, 'PKG_LEAVE_APPROVAL.sql'), 'utf8');
const db = new DatabaseSync(':memory:');
db.function('TO_CHAR', value => value == null ? null : String(value));
db.function('TRIM', value => value == null ? null : (String(value).trim() || null));
db.function('FN_LEAVE_TYPE_ID', (value, company, activeOnly) => Number(value)); // Numeric fixture IDs only.
db.exec(`
    CREATE TABLE employees (id INTEGER PRIMARY KEY, f_name TEXT, l_name TEXT, com_id INTEGER DEFAULT 1);
    CREATE TABLE leave_app_history (
        id INTEGER PRIMARY KEY, leave_id INTEGER, approver_level TEXT, approver_id INTEGER,
        approval_status TEXT, com_id INTEGER, approval_date TEXT, comments TEXT, upd_date TEXT, upd_by INTEGER);
    CREATE TABLE leave_request (
        leave_id INTEGER PRIMARY KEY, empid INTEGER, leave_status TEXT, request_status TEXT,
        leave_type TEXT, leave_balance REAL, leave_taken REAL, applied_date TEXT,
        l_start_date TEXT, l_end_date TEXT, proposed_days REAL, leave_purpose TEXT,
        app_leave_typ TEXT, leave_address TEXT, ent_date TEXT, ent_by INTEGER,
        upd_date TEXT, upd_by INTEGER, comments TEXT);
    CREATE TABLE leave_allocation (empid INTEGER, leave_type_id INTEGER, allocation_year INTEGER, allocated_days REAL);
    CREATE TABLE leave_consumption (leave_id INTEGER UNIQUE, empid INTEGER, leave_type_id INTEGER, consum_year INTEGER, consumed_days REAL);
    INSERT INTO employees (id,f_name,l_name) VALUES (10,'Test','Applicant'),
        (101, 'Test', 'RP'), (102, 'Test', 'HOD'),
        (103, 'Test', 'Plant'), (104, 'Test', 'MD'), (105, 'Test', 'HRD');
`);

function oracleQuery(sql) {
    return sql.replace(/\bHRMS\./gi, '')
        .replaceAll("e.f_name || ' ' || e.l_name", "IFNULL(e.f_name, '') || ' ' || IFNULL(e.l_name, '')")
        .replace(/\bNVL\(/gi, 'IFNULL(')
        .replace(/\bLISTAGG\(/gi, 'GROUP_CONCAT(')
        .replace(/\s+WITHIN GROUP \(ORDER BY h\.id\)/gi, '')
        .replace(/EXTRACT\(YEAR FROM lr\.l_start_date\)/gi, "CAST(strftime('%Y',lr.l_start_date) AS INTEGER)")
        .replace(/\bSYSDATE\b/g, 'CURRENT_TIMESTAMP');
}
const balanceViewSQL = fs.readFileSync(path.join(root, 'V_LEAVE_YEAR_BALANCE.sql'), 'utf8').split(/\bAS\s*\r?\n/)[1];
db.exec('CREATE VIEW v_leave_year_balance AS ' + oracleQuery(balanceViewSQL));
function statement(sql) {
    return oracleQuery(sql)
        .replace(/l_step\.approver_level/g, ':role')
        .replace(/l_step\.id/g, ':history_id')
        .replace(/\bp_leave_id\b/g, ':leave_id')
        .replace(/\bp_actor_id\b/g, ':actor_id')
        .replace(/\bp_comments\b/g, ':comments')
        .replace(/\bl_action\b/g, ':action');
}
function run(sql, values) {
    const compiled = statement(sql);
    const params = Object.fromEntries([...compiled.matchAll(/:(\w+)/g)].map(match => [match[1], values[match[1]]]));
    return db.prepare(compiled).run(params);
}
const updates = [...source.matchAll(/UPDATE leave_app_history\s+SET[\s\S]*?;/g)].map(match => match[0]);
assert.equal(updates.length, 5, 'Review SQL extraction if the package changes');
const [resolveActor, cancelAll, activateFinals, cancelAlternatives, activateHRD] = updates;
const resolveRequest = source.match(/UPDATE leave_request\s+SET leave_status = CASE[\s\S]*?;/)[0];
const aggregate = source.match(/SELECT COUNT\(CASE WHEN approver_level = 'RP'[\s\S]*?FROM leave_app_history WHERE leave_id = p_leave_id;/)[0];
const variables = aggregate.match(/\bINTO ([\s\S]*?)\s+FROM/)[1].split(',').map(name => name.trim());
const aggregateSQL = aggregate.replace(/\s+INTO [\s\S]*?\s+FROM/, ' FROM');
const groupExpressions = [...source.matchAll(/l_valid := ([\s\S]*?);/g)].map(match => match[1]);
assert.equal(groupExpressions.length, 3);
function validGroup(status) {
    const counts = Object.values(db.prepare(statement(aggregateSQL)).get({ leave_id: 1 }));
    const values = Object.fromEntries(variables.map((name, i) => [name, counts[i]]));
    const expression = groupExpressions[{ F: 0, A: 1, R: 2 }[status]]
        .replace(/\bAND\b/g, '&&').replace(/\bOR\b/g, '||')
        .replace(/<>/g, '!==').replace(/(?<![<>!=])=(?!=)/g, '===');
    return new Function(...Object.keys(values), `return (${expression});`)(...Object.values(values));
}
const reportSQL = oracleQuery(fs.readFileSync(path.join(root, 'page_419_leave_request_report.sql'), 'utf8'));
function report() { return db.prepare(reportSQL).get({ USER_ID: 10 }); }
const diagnosticSource = fs.readFileSync(path.join(root, 'CHECK_COMPANY_APPROVAL.sql'), 'utf8');
const groupDiagnosticSQL = diagnosticSource.match(/SELECT lr\.leave_id, COUNT\(h\.id\)[\s\S]*?;/)[0];
function groupIssues() { return db.prepare(oracleQuery(groupDiagnosticSQL)).all(); }
function seed(roles, rp = false) {
    db.exec('DELETE FROM leave_consumption; DELETE FROM leave_app_history; DELETE FROM leave_request;');
    db.exec("INSERT INTO leave_request (leave_id,empid,leave_type,l_start_date,leave_status,request_status) VALUES (1,10,'1','2099-01-01','F','F');");
    const insert = db.prepare('INSERT INTO leave_app_history (id,leave_id,approver_level,approver_id,approval_status,com_id) VALUES (?,1,?,?,?,1)');
    let id = 1;
    if (rp) insert.run(id++, 'RP', 101, 'PENDING');
    for (const [role, person] of roles) insert.run(id++, role, person, rp ? 'WAITING' : 'PENDING');
    insert.run(id, 'LEAVE_RECORD', 105, 'WAITING');
    assert.equal(validGroup('F'), true);
    assert.equal(groupIssues().length, 0, 'Valid alternative candidates are not diagnostic errors');
}
function decide(person, action) {
    const actor = db.prepare("SELECT * FROM leave_app_history WHERE leave_id=1 AND approver_id=? AND approval_status='PENDING'").get(person);
    assert.ok(actor, 'Actor must have a pending assignment');
    const values = { leave_id: 1, actor_id: person, history_id: actor.id,
        action, role: actor.approver_level, comments: 'Offline SQL test' };
    assert.equal(run(resolveActor, values).changes, 1);
    if (action === 'REJECT') run(cancelAll, values);
    else if (action === 'APPROVE' && actor.approver_level === 'RP') run(activateFinals, values);
    else if (action === 'APPROVE') {
        run(cancelAlternatives, values);
        assert.equal(run(activateHRD, values).changes, 1);
    }
    run(resolveRequest, values);
    const request = db.prepare('SELECT leave_status,request_status FROM leave_request WHERE leave_id=1').get();
    assert.equal(validGroup(request.leave_status), true);
    assert.equal(groupIssues().length, 0);
    return request;
}

let cases = 0;
for (const [roles, rp] of [
    [[['HOD', 102], ['PLANT_HEAD', 103]], true],
    [[['HOD', 102], ['PLANT_HEAD', 103]], false],
    [[['PLANT_HEAD', 103], ['MANAGING_DIRECTOR', 104]], false],
    [[['PLANT_HEAD', 103]], true],
    [[['PLANT_HEAD', 103]], false],
    [[['MANAGING_DIRECTOR', 104]], false]
]) {
    for (const [, winner] of roles) {
        seed(roles, rp);
        if (rp) {
            assert.equal(report().leave_status, 'Pending with Test RP (RP)');
            assert.deepEqual({ ...decide(101, 'APPROVE') }, { leave_status: 'F', request_status: 'F' });
        }
        assert.ok(report().leave_status.startsWith('Pending with '));
        assert.equal(report().leave_status.split(', ').length, roles.length);
        for (const removed of ['pending_with', 'pending_role', 'current_stage']) {
            assert.equal(Object.hasOwn(report(), removed), false);
        }
        assert.deepEqual({ ...decide(winner, 'APPROVE') }, { leave_status: 'A', request_status: 'A' });
        assert.equal(report().leave_status, 'Approved', 'HRD recording pending still displays Approved');
        const finals = db.prepare("SELECT * FROM leave_app_history WHERE approver_level IN ('HOD','PLANT_HEAD','MANAGING_DIRECTOR')").all();
        assert.equal(finals.filter(row => row.approval_status === 'APPROVED').length, 1);
        assert.equal(finals.filter(row => row.approval_status === 'CANCELLED').length, roles.length - 1);
        decide(105, 'RECORD');
        assert.equal(report().leave_status, 'Approved');
        seed(roles, rp);
        if (rp) decide(101, 'APPROVE');
        assert.deepEqual({ ...decide(winner, 'REJECT') }, { leave_status: 'R', request_status: 'F' });
        assert.equal(report().leave_status, 'Rejected');
        assert.equal(db.prepare("SELECT COUNT(*) AS n FROM leave_app_history WHERE approval_status IN ('PENDING','WAITING')").get().n, 0);
        cases += 2;
    }
}
seed([['HOD', 102], ['PLANT_HEAD', 103]], true);
decide(101, 'REJECT');
assert.equal(report().leave_status, 'Rejected');

// Invalid group combinations, duplicate assignees, missing routes and user isolation.
seed([['HOD', 102], ['PLANT_HEAD', 103]], true);
db.exec("UPDATE leave_app_history SET approval_status='PENDING' WHERE approver_level='HOD';");
assert.equal(validGroup('F'), false);
assert.ok(report().leave_status.startsWith('Pending with '));
assert.equal(groupIssues().length, 1);
seed([['HOD', 102], ['PLANT_HEAD', 103]], false);
db.exec("UPDATE leave_app_history SET approval_status='WAITING' WHERE approver_level='PLANT_HEAD';");
assert.equal(validGroup('F'), false);
assert.equal(groupIssues().length, 1, 'Sequential pending/waiting final roles require review');
seed([['HOD', 102], ['PLANT_HEAD', 103]], false);
db.exec("UPDATE leave_app_history SET approval_status='APPROVED' WHERE approver_level IN ('HOD','PLANT_HEAD'); UPDATE leave_app_history SET approval_status='PENDING' WHERE approver_level='LEAVE_RECORD';");
assert.equal(validGroup('A'), false);
seed([['HOD', 102], ['PLANT_HEAD', 102]], false);
assert.ok(report().leave_status.startsWith('Pending with '));
seed([['PLANT_HEAD', 999]], false);
assert.equal(report().leave_status, 'Pending with Employee ID 999 (Plant Head)');
db.exec("UPDATE employees SET l_name=NULL WHERE id=103;");
seed([['PLANT_HEAD', 103]], false);
assert.equal(report().leave_status, 'Pending with Test (Plant Head)');
db.exec('DELETE FROM leave_app_history;');
assert.equal(report().leave_status, 'Pending');
db.exec("UPDATE leave_request SET leave_status='P',request_status='D';");
assert.equal(report().leave_status, 'Pending');
db.exec('UPDATE leave_request SET empid=20;');
assert.equal(report(), undefined);

seed([['HOD', 102], ['PLANT_HEAD', 103], ['MANAGING_DIRECTOR', 104]], false);
const viewSQL = fs.readFileSync(path.join(root, 'V_LEAVE_APPROVAL_STEPS.sql'), 'utf8').split(/\bAS\s*\r?\n/)[1];
const finalGroups = db.prepare(oracleQuery(viewSQL)).all().filter(row => row.approver_level !== 'LEAVE_RECORD');
assert.ok(finalGroups.every(row => row.step_no === 20));

// A person may approve at the final tier and then record separately as HRD.
seed([['HOD', 102], ['PLANT_HEAD', 103]], false);
db.exec("UPDATE leave_app_history SET approver_id=103 WHERE approver_level='LEAVE_RECORD';");
decide(103, 'APPROVE');
assert.equal(report().leave_status, 'Approved');
decide(103, 'RECORD');
assert.equal(report().leave_status, 'Approved');
db.exec('INSERT INTO leave_allocation VALUES (10,1,2099,10); INSERT INTO leave_consumption VALUES (NULL,10,1,2099,2);');
assert.equal(report().leave_balance, 8);
assert.equal(report().leave_taken, 2);
db.exec('INSERT INTO leave_consumption VALUES (1,10,1,2099,3);');
assert.equal(report().leave_balance, 5, 'Page 419 reads live balance rather than stale request fields');
assert.equal(report().leave_taken, 5);
db.close();
console.log(`PASS: ${cases} approval/rejection SQL paths, RP rejection, grouping validation, alternative cancellation, HRD recording, Page 419 single-column pending names/roles and Approved display, invalid assignments and user isolation. Oracle PL/SQL execution remains unverified.`);
