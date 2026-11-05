#!/usr/bin/env python3
"""Storage invariants, exercised through the public CLI in temporary homes."""
import concurrent.futures
import errno
import fcntl
import hashlib
import json
import os
import signal
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest

# Allows the same regression cases to challenge an immutable prior source tree.
CLI = Path(os.environ.get('LOOSE_TREE_TEST_SCRIPTS', Path(__file__).parent)) / 'loose-tree'


class StorageTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.store = Path(self.tmp.name) / 'store.json'

    def run_cli(self, *args):
        return subprocess.run([sys.executable, str(CLI), '--store', str(self.store), *args],
                              capture_output=True, text=True, timeout=30)

    def add(self, title, *args):
        p = self.run_cli('add', '--title', title, *args)
        self.assertEqual(p.returncode, 0, p.stderr)
        return p.stdout.strip()

    def test_corruption_is_not_overwritten(self):
        for content in ('{broken', '{"version":1,"nodes":{}}', '{"version":99,"nodes":[]}'):
            self.store.write_text(content)
            self.assertNotEqual(self.run_cli('add', '--title', 'new').returncode, 0)
            self.assertEqual(self.store.read_text(), content)

    def test_parallel_writers_preserve_every_item(self):
        with concurrent.futures.ThreadPoolExecutor(max_workers=12) as pool:
            result = list(pool.map(lambda i: self.run_cli('add', '--title', 'item-%s' % i), range(48)))
        self.assertTrue(all(p.returncode == 0 for p in result))
        nodes = json.loads(self.store.read_text())['nodes']
        self.assertEqual(len(nodes), 48)
        self.assertEqual(len({n['id'] for n in nodes}), 48)

    def test_readers_use_committed_store_while_writer_holds_lock(self):
        nid = self.add('committed obligation')
        with open(str(self.store) + '.lock', 'a') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            for args in [('json',), ('queue',), ('show', nid), ('board',)]:
                p = subprocess.run([sys.executable, str(CLI), '--store',
                                    str(self.store), *args], capture_output=True,
                                   text=True, timeout=3)
                self.assertEqual(p.returncode, 0, p.stderr)

    def test_competing_writer_times_out_without_replacing_lock_or_store(self):
        self.add('preserve me')
        before = self.store.read_bytes()
        with open(str(self.store) + '.lock', 'a') as lock:
            inode = os.fstat(lock.fileno()).st_ino
            fcntl.flock(lock, fcntl.LOCK_EX)
            started = time.monotonic()
            p = subprocess.run([sys.executable, str(CLI), '--store',
                                str(self.store), 'add', '--title', 'must not land'],
                               capture_output=True, text=True, timeout=7)
            self.assertNotEqual(p.returncode, 0)
            self.assertIn('timed out', p.stderr)
            self.assertLess(time.monotonic() - started, 6.5)
            self.assertEqual(os.stat(str(self.store) + '.lock').st_ino, inode)
        self.assertEqual(self.store.read_bytes(), before)
        self.add('writer works after release')

    def test_slow_json_consumer_does_not_lock_out_writers(self):
        self.add('large committed view')
        data = json.loads(self.store.read_text())
        data['nodes'][0]['note'] = 'x' * (512 * 1024)
        self.store.write_text(json.dumps(data))
        proc = subprocess.Popen([sys.executable, str(CLI), '--store',
                                 str(self.store), 'json'], stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE)
        try:
            self.assertEqual(proc.stdout.read(1), b'{')
            p = subprocess.run([sys.executable, str(CLI), '--store',
                                str(self.store), 'add', '--title', 'concurrent'],
                               capture_output=True, text=True, timeout=3)
            self.assertEqual(p.returncode, 0, p.stderr)
        finally:
            proc.communicate(timeout=5)

    def test_all_parent_mutators_reject_cycles(self):
        parent = self.add('parent')
        child = self.add('child', '--parent', parent)
        for command in ('update', 'adopt'):
            before = self.store.read_bytes()
            p = self.run_cli(command, parent, '--parent', child)
            self.assertNotEqual(p.returncode, 0, command)
            self.assertEqual(self.store.read_bytes(), before)

    def test_update_cannot_bypass_open_child_guard(self):
        parent = self.add('parent')
        self.add('child', '--parent', parent)
        for command in (('update', parent, '--status', 'done'), ('drop', parent)):
            before = self.store.read_bytes()
            self.assertNotEqual(self.run_cli(*command).returncode, 0)
            self.assertEqual(self.store.read_bytes(), before)

    def test_blank_decision_does_not_answer_question(self):
        question = self.add('question', '--status', 'awaiting-trevor')
        before = self.store.read_bytes()
        self.assertNotEqual(self.run_cli('update', question, '--decision', '  ').returncode, 0)
        self.assertEqual(self.store.read_bytes(), before)

    def evidence(self, name, data):
        path = Path(self.tmp.name) / name
        path.write_text(json.dumps(data))
        return str(path)

    def manage(self, nid, **updates):
        plan = dict(owner_session='owner-1', owner_harness='codex',
                    authority='user:approved-current-task', next_action='Check the result',
                    acceptance=['Result independently checked'], dependencies=[], priority=1)
        plan.update(updates)
        result = self.run_cli('manage', nid, '--plan', self.evidence(nid + '.json', plan))
        self.assertEqual(result.returncode, 0, result.stderr)

    def observation(self, **updates):
        proof = dict(owner_session='owner-1', state='idle', observed_at=int(time.time()),
                     latest_intent_checked=True, no_active_writer=True,
                     authority='user:approved-current-task', source='native:exact-owner-snapshot')
        proof.update(updates)
        return self.evidence('observation.json', proof)

    def proof(self, nid, **updates):
        artifact = Path(self.tmp.name) / 'result.txt'
        artifact.write_text('actual checked result')
        data = dict(task_id=nid, owner_session='owner-1', verifier_session='reviewer-2',
                    plan_sha256=next(n for n in json.loads(self.store.read_text())['nodes'] if n['id']==nid).get('workflow',{}).get('binding',{}).get('sha256'),
                    checked_at=int(time.time()), result='passed',
                    terminal={'status': 'completed', 'error': None},
                    checks=[dict(criterion='Result independently checked', passed=True,
                                 path=str(artifact), sha256=hashlib.sha256(artifact.read_bytes()).hexdigest())])
        data.update(updates)
        return self.evidence('proof.json', data)

    def test_only_reviewed_authorized_tasks_are_ready(self):
        candidate = self.add('inferred', '--auto')
        ready = self.add('approved')
        self.manage(ready)
        q = self.run_cli('queue')
        self.assertEqual(q.returncode, 0, q.stderr)
        data = json.loads(q.stdout)
        self.assertEqual([n['id'] for n in data['ready']], [ready])
        self.assertEqual(data['candidate_count'], 1)
        self.assertNotIn(candidate, [n['id'] for n in data['ready']])

    def test_active_unknown_stale_owner_and_dependency_block_dispatch(self):
        nid = self.add('approved')
        self.manage(nid)
        for changes in ({'state': 'active'}, {'state': 'unknown'},
                        {'observed_at': 1}, {'latest_intent_checked': False},
                        {'no_active_writer': False}, {'owner_session': 'wrong'}):
            self.assertNotEqual(self.run_cli('dispatch', nid, '--observation', self.observation(**changes)).returncode, 0)
        dep = self.add('unverified dependency')
        self.manage(nid, dependencies=[dep])
        self.assertNotEqual(self.run_cli('dispatch', nid, '--observation', self.observation()).returncode, 0)

    def test_dispatch_reservation_blocks_replay_and_same_owner_overlap(self):
        one, two = self.add('one'), self.add('two')
        self.manage(one)
        self.manage(two)
        obs = self.observation()
        first = self.run_cli('dispatch', one, '--observation', obs)
        self.assertEqual(first.returncode, 0, first.stderr)
        for nid in (one, two):
            self.assertNotEqual(self.run_cli('dispatch', nid, '--observation', obs).returncode, 0)

    def test_managed_done_requires_independent_complete_artifact_proof(self):
        nid = self.add('approved')
        self.manage(nid)
        for args in [('done', nid), ('update', nid, '--status', 'done')]:
            self.assertNotEqual(self.run_cli(*args).returncode, 0)
        for updates in ({'checks': []}, {'verifier_session': 'owner-1'},
                        {'terminal': {'status': 'inProgress', 'error': None}}):
            self.assertNotEqual(self.run_cli('verify', nid, '--evidence', self.proof(nid, **updates)).returncode, 0)
        good = self.run_cli('verify', nid, '--evidence', self.proof(nid))
        self.assertEqual(good.returncode, 0, good.stderr)
        queue = json.loads(self.run_cli('queue').stdout)
        self.assertEqual([n['id'] for n in queue['verified_done']], [nid])

    def test_changed_artifact_and_missing_acceptance_fail_verification(self):
        nid = self.add('approved')
        self.manage(nid)
        proof = self.proof(nid)
        (Path(self.tmp.name) / 'result.txt').write_text('changed')
        self.assertNotEqual(self.run_cli('verify', nid, '--evidence', proof).returncode, 0)
        self.assertNotEqual(self.run_cli('verify', nid, '--evidence', self.proof(nid, checks=[{'criterion':'wrong','passed':True}])).returncode, 0)

    def test_receipt_and_terminal_proof_bind_exact_dispatch(self):
        nid = self.add('dispatch target')
        self.manage(nid)
        attempt = json.loads(self.run_cli('dispatch', nid, '--observation', self.observation()).stdout)
        bad = self.evidence('receipt.json', dict(attempt='wrong', owner_session='owner-1', state='delivered', source='native'))
        self.assertNotEqual(self.run_cli('receipt', nid, '--evidence', bad).returncode, 0)
        receipt = self.evidence('receipt.json', dict(attempt=attempt['id'], owner_session='owner-1', state='delivered', turn_id='turn-1', source='native'))
        self.assertEqual(self.run_cli('receipt', nid, '--evidence', receipt).returncode, 0)
        self.assertNotEqual(self.run_cli('verify', nid, '--evidence', self.proof(nid)).returncode, 0)
        terminal = dict(id='turn-1', status='completed', error=None, started_at=attempt['prepared_at'])
        result = self.run_cli('verify', nid, '--evidence', self.proof(nid, attempt=attempt['id'], terminal=terminal))
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_supersession_preserves_node_and_requires_checked_target_evidence(self):
        old, current = self.add('old candidate', '--auto'), self.add('current outcome')
        proof = json.loads(Path(self.proof(old)).read_text())
        proof.update(target_id=current, reason='same verified outcome')
        proof['checks'][0]['criterion'] = 'same outcome or superseded authority'
        p = self.evidence('supersede.json', proof)
        result = self.run_cli('supersede', old, '--evidence', p)
        self.assertEqual(result.returncode, 0, result.stderr)
        original = next(n for n in json.loads(self.store.read_text())['nodes'] if n['id'] == old)
        self.assertEqual(original['superseded_by'], current)
        self.assertFalse(original['auto'])
        self.assertEqual(original['title'], 'old candidate')

    def test_partial_verification_never_marks_done(self):
        nid = self.add('partial')
        self.manage(nid)
        p = self.proof(nid, result='partial', reason='provider result missing')
        self.assertEqual(self.run_cli('verify', nid, '--evidence', p).returncode, 0)
        queue = json.loads(self.run_cli('queue').stdout)
        self.assertEqual([n['id'] for n in queue['waiting']], [nid])
        self.assertEqual(queue['verified_done'], [])

    def test_json_projects_current_queue_without_changing_the_store(self):
        nid, target = self.add('current outcome'), self.add('canonical outcome')
        data = json.loads(self.store.read_text())
        data['work_queue'] = {'ready': [{'id': 'obsolete-cached-task'}]}
        self.store.write_text(json.dumps(data))

        def check(bucket):
            before = self.store.read_bytes()
            exported = json.loads(self.run_cli('json').stdout)
            current = json.loads(self.run_cli('queue').stdout)
            self.assertEqual(exported['work_queue'], current)
            self.assertEqual(self.store.read_bytes(), before, 'read rewrote the ledger')
            self.assertEqual(exported['nodes'], json.loads(before)['nodes'])
            if bucket:
                self.assertIn(nid, [n['id'] for n in current[bucket]])

        self.manage(nid)
        check('ready')
        self.assertEqual(self.run_cli('update', nid, '--status', 'doing').returncode, 0)
        check('doing')
        self.assertEqual(self.run_cli('update', nid, '--status', 'blocked').returncode, 0)
        check('waiting')
        p = json.loads(Path(self.proof(nid)).read_text())
        p.update(target_id=target, reason='same checked outcome')
        p['checks'][0]['criterion'] = 'same outcome or superseded authority'
        self.assertEqual(self.run_cli('supersede', nid, '--evidence', self.evidence('supersede.json', p)).returncode, 0)
        check(None)
        self.assertEqual(json.loads(self.run_cli('json').stdout)['work_queue']['retired_count'], 1)

    def test_prepared_without_receipt_cannot_close(self):
        nid = self.add('prepared only')
        self.manage(nid)
        attempt = json.loads(self.run_cli('dispatch', nid, '--observation', self.observation()).stdout)
        p = self.proof(nid, attempt=attempt['id'], terminal=dict(id='fake-turn', status='completed', error=None, started_at=attempt['prepared_at']))
        self.assertNotEqual(self.run_cli('verify', nid, '--evidence', p).returncode, 0)
        receipt = dict(attempt=attempt['id'], owner_session='owner-1', state='delivered', source='native')
        self.assertNotEqual(self.run_cli('receipt', nid, '--evidence', self.evidence('receipt.json', receipt)).returncode, 0)
        receipt.update(state='unknown')
        self.assertEqual(self.run_cli('receipt', nid, '--evidence', self.evidence('receipt.json', receipt)).returncode, 0)
        self.assertNotEqual(self.run_cli('verify', nid, '--evidence', p).returncode, 0)

    def test_managed_parent_needs_its_own_verification(self):
        parent = self.add('parent')
        child = self.add('child', '--parent', parent)
        self.manage(parent)
        self.assertIn(parent, [n['id'] for n in json.loads(self.run_cli('queue').stdout)['waiting']])
        self.assertNotEqual(self.run_cli('verify', parent, '--evidence', self.proof(parent)).returncode, 0)
        self.assertEqual(self.run_cli('done', child).returncode, 0)
        n = next(n for n in json.loads(self.store.read_text())['nodes'] if n['id']==parent)
        self.assertEqual(n['status'], 'todo')
        self.assertIn(parent, [n['id'] for n in json.loads(self.run_cli('queue').stdout)['ready']])
        self.assertEqual(self.run_cli('verify', parent, '--evidence', self.proof(parent)).returncode, 0)
        self.add('new child', '--parent', parent)
        self.assertNotIn(parent, [n['id'] for n in json.loads(self.run_cli('queue').stdout)['verified_done']])

    def test_confirmed_turn_cannot_be_retargeted_but_unknown_can_resolve(self):
        nid = self.add('immutable delivery')
        self.manage(nid)
        attempt = json.loads(self.run_cli('dispatch', nid, '--observation', self.observation()).stdout)
        receipt = dict(attempt=attempt['id'], owner_session='owner-1', state='unknown', source='native')
        self.assertEqual(self.run_cli('receipt', nid, '--evidence', self.evidence('receipt.json', receipt)).returncode, 0)
        receipt.update(state='delivered', turn_id='first-turn')
        path = self.evidence('receipt.json', receipt)
        self.assertEqual(self.run_cli('receipt', nid, '--evidence', path).returncode, 0)
        before = self.store.read_bytes()
        for changes in ({'state':'delivered', 'turn_id':'unrelated-turn'}, {'state':'unknown', 'turn_id':None}):
            receipt.update(changes)
            self.assertNotEqual(self.run_cli('receipt', nid, '--evidence', self.evidence('receipt.json', receipt)).returncode, 0)
            self.assertEqual(self.store.read_bytes(), before)
        receipt.update(state='delivered', turn_id='first-turn')
        self.assertEqual(self.run_cli('receipt', nid, '--evidence', self.evidence('receipt.json', receipt)).returncode, 0)
        self.assertEqual(self.store.read_bytes(), before)
        terminal = dict(id='unrelated-turn', status='completed', error=None, started_at=attempt['prepared_at'])
        self.assertNotEqual(self.run_cli('verify', nid, '--evidence', self.proof(nid, attempt=attempt['id'], terminal=terminal)).returncode, 0)
        terminal['id'] = 'first-turn'
        self.assertEqual(self.run_cli('verify', nid, '--evidence', self.proof(nid, attempt=attempt['id'], terminal=terminal)).returncode, 0)

    def test_old_plan_cannot_verify_after_reassignment(self):
        nid = self.add('reassigned')
        self.manage(nid)
        attempt = json.loads(self.run_cli('dispatch', nid, '--observation', self.observation()).stdout)
        receipt = dict(attempt=attempt['id'], owner_session='owner-1', state='delivered', turn_id='old-turn', source='native')
        self.assertEqual(self.run_cli('receipt', nid, '--evidence', self.evidence('receipt.json', receipt)).returncode, 0)
        terminal = dict(id='old-turn', status='completed', error=None, started_at=attempt['prepared_at'])
        partial = self.proof(nid, attempt=attempt['id'], terminal=terminal, result='partial', reason='More work remains')
        self.assertEqual(self.run_cli('verify', nid, '--evidence', partial).returncode, 0)
        old = json.loads(Path(self.proof(nid, attempt=attempt['id'], terminal=terminal)).read_text())
        self.manage(nid, owner_session='owner-2')
        old['owner_session'] = 'owner-2'
        self.assertNotEqual(self.run_cli('verify', nid, '--evidence', self.evidence('old.json',old)).returncode, 0)
        # Even substituting the new hash cannot make the previous attempt current.
        current = next(n for n in json.loads(self.store.read_text())['nodes'] if n['id']==nid)
        old['plan_sha256'] = current['workflow']['binding']['sha256']
        self.assertNotEqual(self.run_cli('verify', nid, '--evidence', self.evidence('old.json',old)).returncode, 0)
        self.assertEqual(self.run_cli('verify', nid, '--evidence', self.proof(nid, owner_session='owner-2')).returncode, 0)

    def test_superseded_task_cannot_be_reopened(self):
        old, target = self.add('old'), self.add('canonical')
        self.manage(old)
        p = json.loads(Path(self.proof(old)).read_text())
        p.update(target_id=target, reason='superseded')
        p['checks'][0]['criterion'] = 'same outcome or superseded authority'
        self.assertEqual(self.run_cli('supersede', old, '--evidence', self.evidence('sup.json', p)).returncode, 0)
        self.assertNotEqual(self.run_cli('update', old, '--status', 'todo').returncode, 0)
        self.assertNotEqual(self.run_cli('dispatch', old, '--observation', self.observation()).returncode, 0)
        # A legacy/corrupt status must still not revive the retired authority.
        data = json.loads(self.store.read_text())
        next(n for n in data['nodes'] if n['id']==old)['status'] = 'todo'
        self.store.write_text(json.dumps(data))
        self.assertNotEqual(self.run_cli('dispatch', old, '--observation', self.observation()).returncode, 0)


class CollectorLockTests(unittest.TestCase):
    """Real collector/CLI processes, with a FIFO standing in for delayed feed I/O."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name) / 'home'
        (self.home / 'data').mkdir(parents=True)
        self.store = self.home / 'loosetree' / 'store.json'
        self.processes = []
        self.writers = []
        self.addCleanup(self.cleanup_processes)
        self.nid = self.cli('add', '--title', 'original', '--auto',
                            '--auto-key', 'existing').stdout.strip()
        data = json.loads(self.store.read_text())
        data['nodes'][0]['workflow_history'] = [{'event': 'original-review'}]
        self.store.write_text(json.dumps(data))

    def cli(self, *args):
        p = subprocess.run([sys.executable, str(CLI), '--store', str(self.store),
                            *args], capture_output=True, text=True, timeout=3)
        self.assertEqual(p.returncode, 0, p.stderr)
        return p

    def cleanup_processes(self):
        for fd in self.writers:
            os.close(fd)
        for proc in self.processes:
            try:
                proc.communicate(timeout=6)
            except subprocess.TimeoutExpired:
                # This exact unreaped session leader was started by this fixture.
                self.assertEqual(os.getpgid(proc.pid), proc.pid)
                os.killpg(proc.pid, signal.SIGKILL)
                proc.communicate(timeout=3)

    def start_collector(self, budget, fault=False):
        # Load the real embedded engine, omitting only its CLI main invocation.
        # The production built-in still runs its actual worker and timeout path.
        code = """
import json, os, pathlib, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text().split('engine() {', 1)[1].split("<<'PYEOF'\\n", 1)[1]
text = text.split('\\nPYEOF\\n}', 1)[0].rsplit('\\nsys.exit(main())', 1)[0]
scope = {'__name__': 'collector_regression'}
exec(compile(text, str(path), 'exec'), scope)
print(json.dumps(scope['_collect_one']('loosetree', 300, '',
                                      'DASHBOARD_CMD_LOOSETREE', float(sys.argv[2]))))
"""
        env = {k: v for k, v in os.environ.items()
               if not k.startswith('DASHBOARD_CMD_')}
        env.update(MISSION_CONTROL_HOME=str(self.home),
                   REPO_ROOT=str(CLI.parent.parent),
                   MISSION_CONTROL_RUNTIME_DIR=str(CLI.parent),
                   PYTHONDONTWRITEBYTECODE='1')
        if fault:
            env['LOOSE_TREE_FAULT'] = '1'
        proc = subprocess.Popen([sys.executable, '-c', code,
                                 str(CLI.with_name('dashboard')), str(budget)],
                                env=env, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, text=True,
                                start_new_session=True)
        self.processes.append(proc)
        return proc

    def stall_chats(self, budget):
        fifo = self.home / 'data' / 'chats.json'
        os.mkfifo(fifo)
        proc = self.start_collector(budget)
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            if proc.poll() is not None:
                stdout, stderr = proc.communicate()
                self.fail('collector exited before slow-read barrier: %s %s' %
                          (stdout, stderr))
            try:
                fd = os.open(fifo, os.O_WRONLY | os.O_NONBLOCK)
                self.writers.append(fd)
                return proc, fd
            except OSError as exc:
                if exc.errno != errno.ENXIO:  # The reader has not opened the FIFO yet.
                    raise
                time.sleep(.01)
        self.fail('collector did not reach the synthetic slow chats read')

    def chats(self):
        return {'schema': 1, 'feed': 'chats', 'cadence_s': 1800,
                'ok': True, 'generated_epoch': int(time.time()),
                'data': {'nodes': [], 'counts': {
                    'last_full_ingest_age_s': 0, 'full_ingest_state': 'fresh',
                    'full_ingest_stale': False}, 'loose_ends': [
                    {'item_key': 'existing', 'kind': 'todo_open',
                     'text': 'older feed title', 'source_node': 'repo:fixture'},
                    {'item_key': 'new', 'kind': 'todo_open',
                     'text': 'new obligation', 'source_node': 'repo:fixture'}]}}

    def finish(self, proc):
        stdout, stderr = proc.communicate(timeout=15)
        self.assertEqual(proc.returncode, 0, stderr)
        return json.loads(stdout)

    def test_slow_feed_preparation_keeps_cli_live_and_merges_latest_history(self):
        proc, fd = self.stall_chats(8)
        self.cli('json')
        self.cli('adopt', self.nid)
        self.cli('update', self.nid, '--title', 'newer manual title',
                 '--note', 'newer decision evidence')
        os.write(fd, json.dumps(self.chats()).encode())
        os.close(fd)
        self.writers.remove(fd)
        self.assertEqual(self.finish(proc), 'ok')
        nodes = json.loads(self.store.read_text())['nodes']
        existing = next(n for n in nodes if n['id'] == self.nid)
        self.assertFalse(existing['auto'])
        self.assertEqual(existing['title'], 'newer manual title')
        self.assertEqual(existing['note'], 'newer decision evidence')
        self.assertEqual(existing['workflow_history'], [{'event': 'original-review'}])
        self.assertEqual(sum(n.get('auto_key') == 'new' for n in nodes), 1)
        published = json.loads((self.home / 'data' / 'loosetree.json').read_text())
        self.assertEqual(published['data']['nodes'], nodes)

    def test_stalled_feed_hits_budget_and_preserves_last_good_and_store(self):
        before = self.store.read_bytes()
        last_good = self.home / 'data' / 'loosetree.json'
        last_good.write_text(json.dumps({'ok': True, 'generated_epoch': int(time.time()),
                                        'data': json.loads(before)}))
        prior_feed = last_good.read_bytes()
        started = time.monotonic()
        # Include real interpreter/shell startup in the budget on loaded Macs.
        proc, _ = self.stall_chats(8)
        self.assertEqual(self.finish(proc), 'error')
        self.assertLess(time.monotonic() - started, 14)
        self.assertEqual(self.store.read_bytes(), before)
        self.assertEqual(last_good.read_bytes(), prior_feed)
        error = json.loads((self.home / 'data' / 'loosetree.error.json').read_text())
        self.assertIn('timed out', error['error'])
        try:
            fd = os.open(self.home / 'data' / 'chats.json', os.O_WRONLY | os.O_NONBLOCK)
        except OSError as exc:
            self.assertEqual(exc.errno, errno.ENXIO)
        else:
            os.close(fd)
            self.fail('timed-out collector left a FIFO reader alive')
        self.cli('add', '--title', 'usable after bounded failure')

    def test_collector_preserves_corruption_and_failed_atomic_write(self):
        (self.home / 'data' / 'chats.json').write_text(json.dumps(self.chats()))
        valid = self.store.read_bytes()
        for before, fault in [(b'{broken', False), (valid, True)]:
            self.store.write_bytes(before)
            self.assertEqual(self.finish(self.start_collector(2, fault)), 'error')
            self.assertEqual(self.store.read_bytes(), before)
            self.assertFalse(list(self.store.parent.glob('.loosetree-*.tmp')))


if __name__ == '__main__':
    unittest.main()
