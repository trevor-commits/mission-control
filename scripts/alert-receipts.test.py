#!/usr/bin/env python3
"""Private receipt, SQLite durability and sender-interruption controls; no network."""
import argparse
from contextlib import contextmanager
import hashlib
import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import signal
import sqlite3
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock

SCRIPTS = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPTS))
LOADER = importlib.machinery.SourceFileLoader("alert_receipts_tool", str(SCRIPTS / "decision-alert"))
SPEC = importlib.util.spec_from_loader(LOADER.name, LOADER)
TOOL = importlib.util.module_from_spec(SPEC)
LOADER.exec_module(TOOL)
NOW = 1783674000


class AlertReceiptTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="mc-alert-receipts-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.state = self.root / "state"
        self.environment = mock.patch.dict(os.environ, {
            "MISSION_CONTROL_HOME": str(self.state), "DECISION_ALERT_NOW_EPOCH": str(NOW),
            "MISSION_CONTROL_ADMISSION_SCHEMA": "0", "PYTHONDONTWRITEBYTECODE": "1"})
        self.environment.start()
        self.addCleanup(self.environment.stop)
        self.admission = mock.patch.object(TOOL, "ADMISSION_SCHEMA_ENABLED", False)
        self.admission.start()
        self.addCleanup(self.admission.stop)
        args = TOOL._parser().parse_args([
            "ingest", "--source-kind", "manual", "--source-key", "receipt-fixture",
            "--text", "Choose the synthetic receipt path", "--evidence", "synthetic evidence",
            "--trust", "structured", "--provenance", "synthetic",
            "--anchor", "fixture:provider-receipt",
            "--resolution-key", "synthetic:receipt-fixture"])
        self.decision_id = TOOL.ingest(args)["decision"]["id"]

    def prepared(self):
        attempt, decision = TOOL._reserve_alert(self.decision_id, NOW)
        message = TOOL._alert_message(decision, TOOL.EgressCounters())
        return attempt, decision, message, self.receipt(message)

    def receipt(self, message):
        return {"schema": 1, "provider": "telegram", "provider_accepted": True,
                "decision_id": self.decision_id,
                "message_hash": hashlib.sha256(message.encode()).hexdigest(),
                "recipient_hash": hashlib.sha256(b"555").hexdigest(),
                "message_id": 9007199254740993}

    def readback(self):
        con = TOOL._connect()
        try:
            self.assertEqual(con.execute("PRAGMA integrity_check").fetchone()[0], "ok")
            attempts = con.execute("SELECT state FROM alert_attempts").fetchall()
            receipts = con.execute("SELECT COUNT(*) FROM alert_receipts").fetchone()[0]
            successes = con.execute("SELECT COUNT(*) FROM decision_events WHERE event_type='alert_success'").fetchone()[0]
            return [row[0] for row in attempts], receipts, successes
        finally:
            con.close()

    def sender(self, mode="valid", extra=""):
        path = self.root / ("sender-" + mode)
        path.write_text("#!" + sys.executable + "\n" +
                        "import hashlib,json,os,signal,sys,time\n" + extra + "\n" +
                        ("time.sleep(30)\n" if mode == "timeout" else
                         "print('x'*8192)\n" if mode == "oversized" else
                         "pass\n" if mode == "empty" else
                         "print(json.dumps({'schema':1,'provider':'telegram','provider_accepted':True,"
                         "'decision_id':sys.argv[4],'message_hash':hashlib.sha256(sys.argv[5].encode()).hexdigest(),"
                         "'recipient_hash':hashlib.sha256(b'555').hexdigest(),'message_id':51}))\n") +
                        ("raise SystemExit(4)\n" if mode == "nonzero" else ""))
        path.chmod(0o700)
        return path

    def alert(self, sender, timeout=3):
        return TOOL.alert(argparse.Namespace(send=True, sender=str(sender), timeout=timeout,
                                            max=1, fresh_within=None, newest_first=False,
                                            decision_ids=[self.decision_id]))

    @contextmanager
    def owned_child(self, argv, purpose):
        proc = subprocess.Popen(argv, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                start_new_session=True)
        identity = subprocess.check_output(["/bin/ps", "-p", str(proc.pid), "-o", "pid=,lstart="], text=True).strip()
        record = {"owner": "alert-receipts-test", "purpose": purpose, "pid": proc.pid,
                  "process_group": proc.pid, "start_identity": identity, "port": None,
                  "stop_method": "signal exact owned unreaped group then wait/reap", "retention": "none"}
        path = self.root / ("process-" + str(proc.pid) + ".json")
        path.write_text(json.dumps(record))
        try:
            yield proc
        finally:
            if proc.poll() is None:
                self.assertEqual(subprocess.check_output(
                    ["/bin/ps", "-p", str(proc.pid), "-o", "pid=,lstart="], text=True).strip(), identity)
                os.killpg(proc.pid, signal.SIGKILL)
            proc.wait(timeout=5)
            record.update(reaped=True, exit_code=proc.returncode)
            path.write_text(json.dumps(record))

    def wait_for(self, predicate):
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            value = predicate()
            if value:
                return value
            time.sleep(0.01)
        self.fail("owned fixture did not reach its finite boundary")

    def test_strict_packet_refuses_invalid_types_bindings_and_private_fields(self):
        message = "fixture café 😺\n\n"
        good = self.receipt(message)
        self.assertEqual(TOOL._parse_provider_receipt(json.dumps(good).encode(), self.decision_id, message), good)
        invalid = [("schema", True), ("schema", 2), ("provider", "other"),
                   ("provider_accepted", "true"), ("provider_accepted", False),
                   ("decision_id", "decision:" + "1" * 24),
                   ("message_hash", "1" * 64), ("message_hash", 1),
                   ("recipient_hash", "not-a-hash"), ("recipient_hash", None),
                   ("message_id", True), ("message_id", "51"), ("message_id", 0),
                   ("message_id", -1), ("message_id", 1.5), ("message_id", None)]
        for key, value in invalid:
            with self.subTest(key=key, value=value):
                packet = dict(good, **{key: value})
                with self.assertRaises(TOOL.DecisionError):
                    TOOL._parse_provider_receipt(json.dumps(packet).encode(), self.decision_id, message)
        for packet in (dict(good, raw_text="private fixture"), {k: v for k, v in good.items() if k != "provider"}):
            with self.assertRaises(TOOL.DecisionError):
                TOOL._parse_provider_receipt(json.dumps(packet).encode(), self.decision_id, message)
        encoded = json.dumps(good).encode()
        for output in (b"", b"not-json", b"null", b"[]", b"\xff", b"x" * 4097,
                       encoded + b"\n" + encoded, encoded.replace(b'"schema": 1', b'"schema": 2, "schema": 1')):
            with self.subTest(output_bytes=len(output)):
                with self.assertRaises(TOOL.DecisionError):
                    TOOL._parse_provider_receipt(output, self.decision_id, message)

    def test_commit_reopen_and_exact_event_binding(self):
        attempt, decision, message, packet = self.prepared()
        TOOL._finish_alert(attempt, decision, NOW, True, message, provider_receipt=packet)
        self.assertEqual(self.readback(), (["success"], 1, 1))
        con = TOOL._connect()
        try:
            newer = dict(packet, message_id=52)
            TOOL._event(con, self.decision_id, "alert_success", decision["evidence_fingerprint"], NOW + 1,
                        evidence_type="provider_acceptance_receipt", evidence_ref="alert:unrelated",
                        detail={"provider_receipt": newer})
            TOOL._event(con, self.decision_id, "alert_success", "1" * 64, NOW + 1,
                        evidence_type="provider_acceptance_receipt", evidence_ref=attempt,
                        detail={"provider_receipt": newer})
            con.commit()
            receipt = TOOL._receipt(con, self.decision_id, decision["evidence_fingerprint"])
            self.assertTrue(receipt["provider_accepted"])
            self.assertEqual(receipt["message_id"], packet["message_id"])
            self.assertEqual(receipt["recipient_hash"], packet["recipient_hash"])
        finally:
            con.close()

    def test_legacy_dedupe_stays_delivery_unverified(self):
        attempt, decision, message, packet = self.prepared()
        con = TOOL._connect()
        try:
            con.execute("UPDATE alert_attempts SET state='success' WHERE attempt_id=?", (attempt,))
            con.execute("INSERT INTO alert_receipts VALUES(?,?,?,?,?)", (
                self.decision_id, decision["evidence_fingerprint"], attempt, NOW, TOOL._sha(message)))
            TOOL._event(con, self.decision_id, "alert_success", decision["evidence_fingerprint"], NOW,
                        evidence_type="fixed_argv_receipt", evidence_ref=attempt)
            TOOL._event(con, self.decision_id, "alert_success", decision["evidence_fingerprint"], NOW + 1,
                        evidence_type="provider_acceptance_receipt", evidence_ref="alert:unrelated",
                        detail={"provider_receipt": packet})
            con.commit()
            receipt = TOOL._receipt(con, self.decision_id, decision["evidence_fingerprint"])
            self.assertFalse(receipt["provider_accepted"])
            self.assertEqual(receipt["verification"], "legacy_sender_exit")
            eligible, skipped = TOOL._alert_eligible_by_ids(con, [self.decision_id], NOW + 1)
            self.assertEqual(eligible, [])
            self.assertEqual(skipped[0]["reason"], "already_sent_or_reserved")
        finally:
            con.close()

    def test_bad_persisted_metadata_and_reservation_binding_refuse_acceptance(self):
        attempt, decision, message, packet = self.prepared()
        with self.assertRaises(TOOL.DecisionError):
            TOOL._finish_alert(attempt, dict(decision, evidence_fingerprint="1" * 64), NOW,
                               True, message, provider_receipt=packet)
        self.assertEqual(self.readback(), (["reserved"], 0, 0))
        TOOL._finish_alert(attempt, decision, NOW, True, message, provider_receipt=packet)
        con = TOOL._connect()
        try:
            con.execute("UPDATE decision_events SET detail_json=? WHERE event_type='alert_success'", (
                json.dumps({"provider_receipt": dict(packet, raw_text="private fixture")}),))
            con.commit()
            receipt = TOOL._receipt(con, self.decision_id, decision["evidence_fingerprint"])
            self.assertFalse(receipt["provider_accepted"])
            self.assertEqual(receipt["verification"], "invalid_provider_receipt")
        finally:
            con.close()

    def test_real_event_trigger_rolls_back_attempt_receipt_and_event(self):
        attempt, decision, message, packet = self.prepared()
        con = TOOL._connect()
        con.execute("CREATE TRIGGER reject_receipt BEFORE INSERT ON decision_events "
                    "WHEN NEW.event_type='alert_success' BEGIN SELECT RAISE(FAIL,'fixture rejection'); END")
        con.commit(); con.close()
        with self.assertRaises(sqlite3.IntegrityError):
            TOOL._finish_alert(attempt, decision, NOW, True, message, provider_receipt=packet)
        self.assertEqual(self.readback(), (["reserved"], 0, 0))

    def rejected_commit(self, *args, **kwargs):
        con = self.original_connect()
        def authorizer(action, first, _second, _database, _source):
            if action == sqlite3.SQLITE_TRANSACTION and str(first).upper() == "COMMIT":
                self.commit_denied = True
                return sqlite3.SQLITE_DENY
            return sqlite3.SQLITE_OK
        con.set_authorizer(authorizer)
        with mock.patch.object(TOOL, "_connect", return_value=con):
            return self.original_finish(*args, **kwargs)

    def test_real_commit_denial_rolls_back_and_classifies_external_acceptance(self):
        self.original_connect = TOOL._connect
        self.original_finish = TOOL._finish_alert
        self.commit_denied = False
        with mock.patch.object(TOOL, "_finish_alert", side_effect=self.rejected_commit):
            result = self.alert(self.sender())
        self.assertTrue(self.commit_denied)
        self.assertFalse(result["ok"])
        self.assertEqual(result["sent_count"], 0)
        self.assertEqual(result["provider_accepted_count"], 0)
        self.assertEqual(result["provider_accepted_persistence_unverified_count"], 1)
        self.assertTrue(result["failed"][0]["provider_accepted"])
        self.assertFalse(result["failed"][0]["persistence_verified"])
        self.assertEqual(self.readback(), (["reserved"], 0, 0))

    def test_sender_finish_denial_preserves_known_acceptance_without_success(self):
        con = TOOL._connect()
        con.execute("CREATE TRIGGER reject_sender_finish BEFORE INSERT ON decision_events "
                    "WHEN NEW.event_type='alert_sender_finish' BEGIN SELECT RAISE(FAIL,'fixture rejection'); END")
        con.commit(); con.close()
        result = self.alert(self.sender())
        self.assertFalse(result["ok"])
        self.assertEqual(result["provider_accepted_count"], 0)
        self.assertEqual(result["provider_accepted_persistence_unverified_count"], 1)
        self.assertTrue(result["failed"][0]["provider_accepted"])
        self.assertFalse(result["failed"][0]["persistence_verified"])
        process = result["failed"][0]["sender_process"]
        self.assertTrue(process["reaped"])
        self.assertTrue(process["group_empty"])
        self.assertFalse(process["finish_persistence_verified"])
        self.assertEqual(self.readback(), (["reserved"], 0, 0))

    def test_term_and_int_during_native_popen_assignment_reap_and_restore(self):
        sender = self.sender("timeout")
        real_popen = subprocess.Popen
        for signum in (signal.SIGTERM, signal.SIGINT):
            with self.subTest(signal=signum):
                con = TOOL._connect()
                con.execute("DELETE FROM alert_attempts"); con.commit(); con.close()
                captured = []
                handlers = {s: signal.getsignal(s) for s in (signal.SIGTERM, signal.SIGINT)}
                mask = signal.pthread_sigmask(signal.SIG_BLOCK, [])
                def create(*args, **kwargs):
                    proc = real_popen(*args, **kwargs)
                    if args[0][0] == str(sender):
                        identity = subprocess.check_output(
                            ["/bin/ps", "-p", str(proc.pid), "-o", "pid=,lstart="], text=True).strip()
                        captured.append((proc, identity))
                        (self.root / ("assignment-process-" + str(proc.pid) + ".json")).write_text(json.dumps({
                            "owner": "alert-receipts-test", "pid": proc.pid, "process_group": proc.pid,
                            "start_identity": identity, "purpose": "actual signal before Popen assignment",
                            "retention": "none", "stop_method": "exact owned group signal and wait/reap"}))
                        os.kill(os.getpid(), signum)
                    return proc
                try:
                    with mock.patch.object(TOOL.subprocess, "Popen", side_effect=create):
                        with self.assertRaises(SystemExit) as raised:
                            self.alert(sender)
                    self.assertEqual(raised.exception.code, 128 + signum)
                    self.assertEqual(len(captured), 1)
                    self.assertIsNotNone(captured[0][0].returncode)
                    self.assertEqual({s: signal.getsignal(s) for s in handlers}, handlers)
                    self.assertEqual(signal.pthread_sigmask(signal.SIG_BLOCK, []), mask)
                    self.assertEqual(self.readback(), (["reserved"], 0, 0))
                finally:
                    for proc, identity in captured:
                        if proc.returncode is None:
                            self.assertEqual(subprocess.check_output(
                                ["/bin/ps", "-p", str(proc.pid), "-o", "pid=,lstart="], text=True).strip(), identity)
                            os.killpg(proc.pid, signal.SIGKILL)
                        proc.wait(timeout=5)

    def test_successful_sender_stops_closed_stdout_descendant(self):
        self.closed_stdout_descendant_control(False)

    def test_signal_denial_with_live_descendant_refuses_success(self):
        self.closed_stdout_descendant_control(True)

    def closed_stdout_descendant_control(self, deny_signal):
        witness = self.root / "sender-descendant.json"
        extra = (
            "import subprocess\n"
            "child=os.fork()\n"
            "if child==0:\n"
            " os.close(1);os.close(2);time.sleep(30);os._exit(0)\n"
            "identity=subprocess.check_output(['/bin/ps','-p',str(child),'-o','pid=,lstart='],text=True).strip()\n"
            "open(" + repr(str(witness)) + ",'w').write(json.dumps({'pid':child,'group':os.getpgrp(),"
            "'start_identity':identity,'owner':'alert-receipts-test','retention':'none',"
            "'purpose':'private closed-stdout descendant','stop_method':'exact owned PID signal and observed kernel reaping'}))")
        try:
            sender = self.sender(extra=extra)
            if deny_signal:
                with mock.patch.object(TOOL.os, "killpg", side_effect=PermissionError("fixture denial")):
                    result = self.alert(sender)
                self.assertFalse(result["ok"])
                self.assertEqual(result["provider_accepted_count"], 0)
                self.assertEqual(result["provider_accepted_persistence_unverified_count"], 1)
                self.assertEqual(self.readback(), (["reserved"], 0, 0))
            else:
                result = self.alert(sender)
                self.assertTrue(result["ok"])
                self.assertEqual(result["provider_accepted_count"], 1)
            descendant = json.loads(witness.read_text())
            current = subprocess.run(["/bin/ps", "-p", str(descendant["pid"]), "-o", "pid=,lstart="],
                                     capture_output=True, text=True).stdout.strip()
            if deny_signal:
                self.assertEqual(current, descendant["start_identity"])
            else:
                self.assertNotEqual(current, descendant["start_identity"])
            con = TOOL._connect()
            try:
                finish = json.loads(con.execute("SELECT detail_json FROM decision_events "
                                               "WHERE event_type='alert_sender_finish'").fetchone()[0])
                self.assertEqual(finish["group_stopped_before_reap"], not deny_signal)
                self.assertEqual(finish["group_empty"], not deny_signal)
                self.assertEqual(finish["retention"], "cleanup-unverified" if deny_signal else "none")
                self.assertEqual(finish["process_group"], descendant["group"])
            finally:
                con.close()
        finally:
            if witness.exists():
                descendant = json.loads(witness.read_text())
                current = subprocess.run(["/bin/ps", "-p", str(descendant["pid"]), "-o", "pid=,lstart="],
                                         capture_output=True, text=True).stdout.strip()
                if current == descendant["start_identity"]:
                    self.assertEqual(os.getpgid(descendant["pid"]), descendant["group"])
                    os.kill(descendant["pid"], signal.SIGKILL)
                    self.wait_for(lambda: subprocess.run(
                        ["/bin/ps", "-p", str(descendant["pid"]), "-o", "pid=,lstart="],
                        capture_output=True, text=True).stdout.strip() != current)

    def test_empty_oversized_nonzero_and_timeout_never_stamp_success(self):
        for mode in ("empty", "oversized", "nonzero", "timeout"):
            with self.subTest(mode=mode):
                con = TOOL._connect()
                con.execute("DELETE FROM alert_attempts"); con.commit(); con.close()
                result = self.alert(self.sender(mode), timeout=1)
                self.assertFalse(result["ok"])
                self.assertEqual(result["provider_accepted_count"], 0)
                self.assertEqual(self.readback(), (["failed"], 0, 0))

    def test_stdout_bound_does_not_cap_other_sender_file_writes(self):
        extra = "open(" + repr(str(self.root / "sender-log")) + ",'wb').write(b'x'*8192)"
        result = self.alert(self.sender(extra=extra))
        self.assertTrue(result["ok"])
        self.assertEqual(result["provider_accepted_count"], 1)
        self.assertEqual((self.root / "sender-log").stat().st_size, 8192)
        con = TOOL._connect()
        try:
            events = con.execute("SELECT event_type,detail_json FROM decision_events "
                                 "WHERE event_type LIKE 'alert_sender_%' ORDER BY event_id").fetchall()
            self.assertEqual([r[0] for r in events], ["alert_sender_start", "alert_sender_finish"])
            finish = json.loads(events[1][1])
            self.assertTrue(finish["reaped"])
            self.assertEqual(finish["exit_code"], 0)
            self.assertEqual(finish["process_group"], finish["pid"])
            self.assertTrue(finish["start_identity"].startswith(str(finish["pid"]) + " "))
        finally:
            con.close()

    def test_parent_term_reaps_owned_sender_and_leaves_no_success(self):
        sender = self.sender("timeout")
        command = [sys.executable, "-B", str(SCRIPTS / "decision-alert"), "alert", "--send", "--sender",
                   str(sender), "--timeout", "30", "--decision-id", self.decision_id]
        def started():
            con = TOOL._connect()
            try:
                row = con.execute("SELECT detail_json FROM decision_events WHERE event_type='alert_sender_start'").fetchone()
                return json.loads(row[0]) if row else None
            finally:
                con.close()
        with self.owned_child(command, "interrupt private alert parent") as parent:
            process = self.wait_for(started)
            parent.send_signal(signal.SIGTERM)
            self.assertEqual(parent.wait(timeout=5), 143)
        result = subprocess.run(["/bin/ps", "-p", str(process["pid"]), "-o", "pid=,lstart="],
                                capture_output=True, text=True, timeout=3)
        self.assertNotEqual(result.stdout.strip(), process["start_identity"])
        self.assertEqual(self.readback(), (["reserved"], 0, 0))

    def test_term_before_and_after_real_sqlite_commit(self):
        for stage in ("before", "after"):
            with self.subTest(stage=stage):
                con = TOOL._connect()
                con.execute("DELETE FROM alert_receipts"); con.execute("DELETE FROM alert_attempts")
                con.execute("DELETE FROM decision_events WHERE event_type='alert_success'")
                con.commit(); con.close()
                attempt, decision, message, packet = self.prepared()
                marker = self.root / ("commit-" + stage)
                program = r'''
import importlib.machinery,importlib.util,json,sys,time
from pathlib import Path
scripts=Path(sys.argv[1]);sys.path.insert(0,str(scripts))
loader=importlib.machinery.SourceFileLoader('private_receipt_control',str(scripts/'decision-alert'))
spec=importlib.util.spec_from_loader(loader.name,loader);tool=importlib.util.module_from_spec(spec);loader.exec_module(tool)
stage,marker,attempt,decision,message,packet=sys.argv[2:]
real=tool._connect()
class CommitBoundary:
 def __getattr__(self,name):return getattr(real,name)
 def commit(self):
  if stage=='after':real.commit()
  Path(marker).write_text('ready')
  time.sleep(30)
  if stage=='before':real.commit()
tool._connect=lambda:CommitBoundary()
tool._finish_alert(attempt,json.loads(decision),1783674000,True,message,provider_receipt=json.loads(packet))
'''
                command = [sys.executable, "-B", "-c", program, str(SCRIPTS), stage, str(marker), attempt,
                           json.dumps(decision), message, json.dumps(packet)]
                with self.owned_child(command, "SQLite " + stage + " commit interruption") as child:
                    self.wait_for(marker.exists)
                    child.send_signal(signal.SIGTERM)
                    child.wait(timeout=5)
                expected = (["reserved"], 0, 0) if stage == "before" else (["success"], 1, 1)
                self.assertEqual(self.readback(), expected)


if __name__ == "__main__":
    unittest.main(verbosity=2)
