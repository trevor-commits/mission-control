#!/usr/bin/env python3
"""Storage invariants, exercised through the public CLI in temporary homes."""
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest

CLI = Path(__file__).with_name('loose-tree')


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


if __name__ == '__main__':
    unittest.main()
