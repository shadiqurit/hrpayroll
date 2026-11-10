// Execute actual workflow DML/group predicates and report/inbox SQL in SQLite.
// Oracle PL/SQL routing, triggers, locks and transactions need the Oracle script.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const { DatabaseSync } = require('node:sqlite');
const root = path.resolve(__dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const source = read('PKG_M_ATT_APPROVAL.sql');
const db = new DatabaseSync(':memory:');
db.function('TO_CHAR', value => value == null ? null : String(value));
db.function('TRIM', value => value == null ? null : String(value).trim() || null);
db.function('APEX_REQUEST_URL', (page, cache, item, id) => {
    assert.equal(String(page), cache, 'Link clears its target page cache');
    assert.equal(item, `P${page}_ID`, 'Link passes the application key to its target page');
    return `f?p=100:${page}:test::NO:${cache}:${item}:${id}`;
});
function sql(text) {
    return text.replace(/\bHRMS\./gi, '')
        .replace(/\bAPEX_PAGE\.GET_URL\(/g, 'APEX_REQUEST_URL(')
        .replace(/\bp_(?:page|clear_cache|items|values)\s*=>\s*/g, '')
        .replaceAll("e.f_name || ' ' || e.l_name", "IFNULL(e.f_name, '') || ' ' || IFNULL(e.l_name, '')")
        .replace(/\bNVL\(/gi, 'IFNULL(').replace(/\bLISTAGG\(/gi, 'GROUP_CONCAT(')
        .replace(/\s+WITHIN GROUP \(ORDER BY h\.id\)/gi, '')
        .replace(/\bSYSDATE\b/g, 'CURRENT_TIMESTAMP')
        .replace(/l_step\.approver_level/g, ':role').replace(/l_step\.id/g, ':history_id')
        .replace(/\bp_att_id\b/g, ':att_id').replace(/\bp_actor_id\b/g, ':actor_id')
        .replace(/\bp_company_id\b/g, ':company_id')
        .replace(/\bp_comments\b/g, ':comments').replace(/\bl_action\b/g, ':action');
}
db.exec(`
    CREATE TABLE employees (id INTEGER PRIMARY KEY, f_name TEXT, l_name TEXT,
        com_id INTEGER DEFAULT 1, status INTEGER DEFAULT 1);
    CREATE TABLE v_emp (emp_id INTEGER PRIMARY KEY, ipi TEXT, fullname TEXT, department TEXT, designation TEXT);
    CREATE TABLE manual_att (id INTEGER PRIMARY KEY, empid INTEGER, empcode TEXT,
        reason TEXT, m_intime REAL, m_outtime REAL, status TEXT, comments TEXT, com_id INTEGER,
        ent_date TEXT, ent_by INTEGER, upd_date TEXT, upd_by INTEGER, att_date REAL,
        request_status TEXT, workflow_version INTEGER);
    CREATE TABLE m_att_app_history (id INTEGER PRIMARY KEY, m_att_id INTEGER, approver_level TEXT,
        approver_id INTEGER, approval_status TEXT, com_id INTEGER, approval_date TEXT, comments TEXT,
        ent_date TEXT, ent_by INTEGER, upd_date TEXT, upd_by INTEGER);
    INSERT INTO employees (id,f_name,l_name) VALUES (10,'Test','Applicant'), (101,'Test','RP'),
        (102,'Test','HOD'), (103,'Test','Plant'), (104,'Test','MD'), (105,'Test','HRD');
    INSERT INTO v_emp SELECT id, CAST(id AS TEXT), f_name || ' ' || l_name, 'Department', 'Designation' FROM employees;
`);
for (const [name, file] of [
    ['v_m_att_approval_steps', 'V_M_ATT_APPROVAL_STEPS.sql'],
    ['v_m_att_report', 'V_M_ATT_REPORT.sql'], ['v_m_att_approval', 'V_M_ATT_APPROVAL.sql']
]) {
    const query = read(file).split(/CREATE OR REPLACE VIEW [\w.]+ AS\s*/i)[1];
    assert.ok(query, 'Actual view source: ' + file);
    db.exec(`CREATE VIEW ${name} AS ` + sql(query));
}
function prepare(text, values = {}) {
    const compiled = sql(text);
    const names = [...compiled.replace(/--[^\n]*/g, '').matchAll(/:(\w+)/g)].map(m => m[1]);
    const params = Object.fromEntries(names.map(key => {
        assert.ok(Object.hasOwn(values, key), 'Bound parameter: ' + key);
        return [key, values[key]];
    }));
    return { statement: db.prepare(compiled), params };
}
function all(text, values) { const p = prepare(text, values); return p.statement.all(p.params); }
function run(text, values) { const p = prepare(text, values); return p.statement.run(p.params); }
const updates = [...source.matchAll(/UPDATE m_att_app_history\s+SET[\s\S]*?;/g)].map(m => m[0]);
assert.equal(updates.length, 5, 'Review extraction if workflow SQL changes');
const [resolveActor, cancelAll, activateFinals, cancelAlternatives, activateHRD] = updates;
const resolveRequest = source.match(/UPDATE manual_att\s+SET status = CASE[\s\S]*?;/)[0];
const pendingSelection = source.match(/SELECT \* INTO l_step FROM m_att_app_history[\s\S]*?;/)[0]
    .replace(' INTO l_step', '').replace(' FOR UPDATE', '');
const aggregate = source.match(/SELECT COUNT\(CASE WHEN approver_level = 'RP'[\s\S]*?FROM m_att_app_history WHERE m_att_id = p_att_id;/)[0];
const variables = aggregate.match(/\bINTO ([\s\S]*?)\s+FROM/)[1].split(',').map(n => n.trim());
const aggregateSQL = aggregate.replace(/\s+INTO [\s\S]*?\s+FROM/, ' FROM');
const predicates = [...source.matchAll(/l_valid := ([\s\S]*?);/g)].map(m => m[1]);
assert.equal(predicates.length, 3);
function valid(status) {
    const values = Object.values(all(aggregateSQL, { att_id: 1 })[0]);
    const expression = predicates[{ F: 0, A: 1, R: 2 }[status]]
        .replace(/\bAND\b/g, '&&').replace(/\bOR\b/g, '||')
        .replace(/<>/g, '!==').replace(/(?<![<>!=])=(?!=)/g, '===');
    return new Function(...variables, `return (${expression});`)(...values);
}
const report = () => all(read('apex_applicant_report.sql'), { USER_ID: 10, G_COM_ID: 1 })[0];
const inbox = (actor = 101, company = 1) => all(read('apex_pending_inbox.sql'), { USER_ID: actor, G_COM_ID: company });
const recorded = actor => all(read('apex_recorded_report.sql'), { USER_ID: actor, G_COM_ID: 1 });
const canApprove = actor => all(read('apex_approval_condition.sql'), { P418_ID: 1, USER_ID: actor, G_COM_ID: 1 }).length > 0;
const canRecord = actor => all(read('apex_record_condition.sql'), { P418_ID: 1, USER_ID: actor, G_COM_ID: 1 }).length > 0;
const canEdit = (actor, id = 1) => all(read('apex_entry_edit_condition.sql'), { P411_ID: id, USER_ID: actor, G_COM_ID: 1 }).length > 0;
function seed(roles, rp = true) {
    db.exec('DELETE FROM m_att_app_history; DELETE FROM manual_att;');
    db.exec(`INSERT INTO manual_att (id, empid, status, request_status, workflow_version, com_id, reason)
        VALUES (1, 10, 'F', 'F', 1, 1, 'Missing punch');`);
    const insert = db.prepare('INSERT INTO m_att_app_history (id,m_att_id,approver_level,approver_id,approval_status,com_id) VALUES (?,1,?,?,?,1)');
    let id = 1;
    if (rp) insert.run(id++, 'RP', 101, 'PENDING');
    for (const [role, person] of roles) insert.run(id++, role, person, rp ? 'WAITING' : 'PENDING');
    insert.run(id, 'LEAVE_RECORD', 105, 'WAITING');
    assert.equal(valid('F'), true);
}
function decide(actor, action) {
    const step = all(pendingSelection, { att_id: 1, actor_id: actor, company_id: 1 })[0];
    assert.ok(step, 'Actor has a pending assignment');
    const values = { att_id: 1, actor_id: actor, history_id: step.id, action,
        role: step.approver_level, comments: 'Offline workflow SQL test' };
    assert.equal(run(resolveActor, values).changes, 1);
    if (action === 'REJECT') run(cancelAll, values);
    else if (action === 'APPROVE' && step.approver_level === 'RP') run(activateFinals, values);
    else if (action === 'APPROVE') {
        run(cancelAlternatives, values);
        assert.equal(run(activateHRD, values).changes, 1);
    }
    run(resolveRequest, values);
    const request = db.prepare('SELECT status FROM manual_att WHERE id=1').get();
    assert.equal(valid(request.status), true);
    return report();
}
let cases = 0;
for (const [roles, rp] of [
    [[['HOD', 102], ['PLANT_HEAD', 103]], true],
    [[['HOD', 102], ['PLANT_HEAD', 103]], false],
    [[['PLANT_HEAD', 103], ['MANAGING_DIRECTOR', 104]], false],
    [[['PLANT_HEAD', 103]], true], [[['PLANT_HEAD', 103]], false],
    [[['MANAGING_DIRECTOR', 104]], false]
]) {
    for (const [, winner] of roles) {
        seed(roles, rp);
        assert.equal(report().request_url, 'f?p=100:411:test::NO:411:P411_ID:1');
        assert.equal(canEdit(10), false, 'Forwarded entries are read-only on Page 411');
        assert.equal(canRecord(105), false);
        assert.equal(inbox(105).length, 0, 'HRD cannot act before final approval');
        assert.equal(inbox(winner, 2).length, 0, 'Company filter');
        assert.equal(inbox(10).length, 0, 'Applicant has no approval assignment');
        if (rp) {
            assert.equal(canApprove(101), true);
            assert.equal(canApprove(winner), false);
            assert.equal(report().status_text, 'Pending with Test RP (Reporting Person)');
            assert.equal(inbox(winner).length, 0, 'Finals wait for RP');
            decide(101, 'APPROVE');
            assert.equal(inbox(101).length, 0, 'RP action disappears');
        }
        for (const [, actor] of roles) {
            assert.equal(inbox(actor).length, 1);
            assert.equal(inbox(actor)[0].request_url, 'f?p=100:418:test::NO:418:P418_ID:1');
            assert.equal(canApprove(actor), true);
        }
        assert.match(report().status_text, /^Pending with /);
        const approved = decide(winner, 'APPROVE');
        assert.equal(approved.status_text, 'Approved');
        assert.equal(approved.recording_status, 'Pending HRD recording');
        assert.equal(approved.pending_with, 'Test HRD (HRD Record Keeping)');
        for (const [, actor] of roles) {
            assert.equal(inbox(actor).length, 0, 'Final alternatives close');
            assert.equal(canApprove(actor), false);
        }
        assert.equal(canRecord(105), true);
        assert.equal(inbox(105).length, 1);
        assert.equal(recorded(105).length, 0);
        const completed = decide(105, 'RECORD');
        assert.equal(completed.status_text, 'Approved');
        assert.equal(completed.recording_status, 'Recorded');
        assert.equal(completed.pending_with, null);
        assert.equal(inbox(105).length, 0);
        assert.equal(recorded(105).length, 1);
        assert.equal(recorded(105)[0].request_url, 'f?p=100:418:test::NO:418:P418_ID:1');
        assert.equal(canRecord(105), false);
        cases++;

        seed(roles, rp);
        if (rp) decide(101, 'APPROVE');
        const rejected = decide(winner, 'REJECT');
        assert.equal(rejected.status_text, 'Rejected');
        assert.equal(rejected.recording_status, 'Not required');
        assert.equal(rejected.pending_with, null);
        assert.equal(inbox(105).length, 0);
        assert.equal(db.prepare("SELECT COUNT(*) n FROM m_att_app_history WHERE approval_status IN ('PENDING','WAITING')").get().n, 0);
        cases++;
    }
}
seed([['HOD', 102]]);
assert.equal(decide(101, 'REJECT').status_text, 'Rejected');
assert.equal(inbox(102).length, 0);
// Malformed group states must fail the actual check_history group predicates.
seed([['HOD', 102], ['PLANT_HEAD', 103]], false);
decide(102, 'APPROVE');
db.exec("UPDATE m_att_app_history SET approval_status='APPROVED' WHERE approver_level='PLANT_HEAD'");
assert.equal(valid('A'), false, 'Two final approvals are invalid');
seed([['HOD', 102]], true);
db.exec("UPDATE m_att_app_history SET approval_status='PENDING' WHERE approver_level='HOD'");
assert.equal(valid('F'), false, 'Finals cannot start before RP');
// Drafts remain visible despite having no history.
db.exec("DELETE FROM m_att_app_history; UPDATE manual_att SET status='D',request_status='D'");
assert.equal(report().status_text, 'Draft');
assert.equal(report().pending_with, null);
assert.equal(inbox().length, 0);
assert.equal(canEdit(10), true);
assert.equal(canEdit(104), false);
assert.equal(canEdit(10, null), true);
// Missing v_emp/employee display data cannot hide the application or assignment.
seed([['HOD', 102]], false);
db.exec('DELETE FROM v_emp WHERE emp_id IN (10,102); DELETE FROM employees WHERE id=102;');
assert.equal(report().status_text, 'Pending with Employee ID 102 (Head of Department)');
assert.equal(inbox(102).length, 1);
// Legacy data is visible for review but excluded from new actions.
db.exec('UPDATE manual_att SET workflow_version=0');
assert.equal(report().status_text, 'Pending - administrator review');
assert.equal(inbox(102).length, 0);
// Authorized detail/history queries reject a guessed ID, actor, or company.
const detail = (actor, company) => all(read('apex_request_detail.sql'), { P411_ID: 1, USER_ID: actor, G_COM_ID: company });
assert.equal(detail(10, 1).length, 1);
assert.equal(detail(102, 1).length, 1);
assert.equal(detail(104, 1).length, 0);
assert.equal(detail(10, 2).length, 0);
assert.equal(all(read('apex_request_history.sql'), { P411_ID: 1, USER_ID: 104, G_COM_ID: 1 }).length, 0);
assert.equal(all(read('apex_approval_detail.sql'), { P418_ID: 1, USER_ID: 105, G_COM_ID: 1 }).length, 1);
assert.equal(all(read('apex_approval_history.sql'), { P418_ID: 1, USER_ID: 104, G_COM_ID: 1 }).length, 0);
assert.equal(canApprove(102), false, 'Legacy assignments cannot show approval actions');
console.log(`PASS: ${cases} final-decision paths, RP rejection, group invariants, draft/legacy visibility, pending people, approval/HRD inboxes, recorded history, missing names, authorized detail, Page 410 links to 411/418, and entry/approval/record controls. Oracle/APEX runtime remains unverified.`);
