#!/usr/bin/env python3
"""Storage invariants, exercised through the public CLI in temporary homes."""
import concurrent.futures
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
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


if __name__ == '__main__':
    unittest.main()
