#!/usr/bin/env python3
"""Offline security and transport tests for the Morning Brief deadman sender."""

import contextlib
import importlib.util
from importlib.machinery import SourceFileLoader
import io
import json
import os
import signal
import stat
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from unittest import mock


ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEADMAN_PATH = os.path.join(ROOT, "scripts", "morning-brief-deadman")
sys.path.insert(0, os.path.join(ROOT, "scripts"))
SPEC = importlib.util.spec_from_loader(
    "morning_brief_deadman",
    SourceFileLoader("morning_brief_deadman", DEADMAN_PATH))
DEADMAN = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(DEADMAN)

TOKEN = "123456:TEST_SECRET_abcdefghijklmnopqrstuvwxyz"
CHAT_ID = "12345"


class FakeTelegram:
    def __init__(self, responses=None):
        self.responses = list(responses or [(200, {}, {
            "ok": True, "result": {"message_id": 1}})])
        self.requests = []
        self.lock = threading.Lock()
        owner = self

        class Handler(BaseHTTPRequestHandler):
            def do_POST(self):
                length = int(self.headers.get("Content-Length", "0"))
                body = self.rfile.read(length)
                with owner.lock:
                    owner.requests.append({
                        "path": self.path,
                        "body": body,
                        "content_type": self.headers.get("Content-Type"),
                    })
                    index = min(len(owner.requests) - 1,
                                len(owner.responses) - 1)
                    status, headers, payload = owner.responses[index]
                    headers = dict(headers)
                delay = float(headers.pop("X-Test-Delay", "0"))
                drip = float(headers.pop("X-Test-Drip", "0"))
                if delay:
                    time.sleep(delay)
                encoded = (payload if isinstance(payload, bytes)
                           else json.dumps(payload).encode("utf-8"))
                try:
                    self.send_response(status)
                    for key, value in headers.items():
                        self.send_header(key, value)
                    self.send_header("Content-Type", "application/json")
                    self.end_headers()
                    if drip:
                        for byte in encoded:
                            self.wfile.write(bytes((byte,)))
                            self.wfile.flush()
                            time.sleep(drip)
                    else:
                        self.wfile.write(encoded)
                except (BrokenPipeError, ConnectionResetError):
                    pass

            def log_message(self, _format, *_args):
                pass

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.thread = threading.Thread(target=self.server.serve_forever,
                                       daemon=True)

    @property
    def base_url(self):
        return "http://127.0.0.1:%d" % self.server.server_port

    def __enter__(self):
        self.thread.start()
        return self

    def __exit__(self, *_args):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=2)


class DeadmanSenderTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = os.path.join(self.tmp.name, "home")
        self.state = os.path.join(self.tmp.name, "state")
        self.config = os.path.join(self.tmp.name, "config")
        os.makedirs(self.home)
        os.makedirs(os.path.join(self.state, "morning-brief"))

    def tearDown(self):
        self.tmp.cleanup()

    def direct_env(self, server, **extra):
        values = {
            "HOME": self.home,
            "PATH": "/usr/bin:/bin",
            "MISSION_CONTROL_HOME": self.state,
            "MOBILE_CONNECT_CONFIG": self.config,
            "MORNING_BRIEF_INCIDENTS_CHAT_ID": CHAT_ID,
            "MORNING_BRIEF_TELEGRAM_BOT_TOKEN": TOKEN,
            "MORNING_BRIEF_TELEGRAM_API_BASE": server.base_url,
            "MORNING_BRIEF_TELEGRAM_TEST_MODE": "1",
            "MORNING_BRIEF_SEND_TIMEOUT_S": "2",
            "HTTP_PROXY": "http://127.0.0.1:1",
            "HTTPS_PROXY": "http://127.0.0.1:1",
        }
        values.update(extra)
        return values

    def write_config(self, text, mode=0o600):
        with open(self.config, "w") as handle:
            handle.write(text)
        os.chmod(self.config, mode)

    def assert_direct_request(self, request, category="missing"):
        self.assertTrue(request["path"].startswith("/bot"))
        self.assertTrue(request["path"].endswith("/sendMessage"))
        self.assertEqual(request["content_type"], "application/json")
        payload = json.loads(request["body"].decode("utf-8"))
        self.assertEqual(payload, {
            "chat_id": int(CHAT_ID),
            "text": "Morning Brief deadman: %s. Glance: menu-bar MC (dashboard panel) or light Home (dashboard open)." % category,
            "disable_web_page_preview": True,
        })

    def test_direct_env_send_uses_stdlib_and_category_only_message(self):
        with FakeTelegram() as server, mock.patch.dict(
                os.environ, self.direct_env(server), clear=True), mock.patch.object(
                    DEADMAN.subprocess, "run",
                    side_effect=AssertionError("subprocess transport used")):
            self.assertTrue(DEADMAN._send("missing"))
        self.assertEqual(len(server.requests), 1)
        self.assert_direct_request(server.requests[0])
        with open(DEADMAN_PATH) as handle:
            source = handle.read()
        self.assertNotIn("mobile-connect/mobile-connect.sh",
                         source)
        self.assertNotIn("curl", source)
        self.assertNotIn("ALLOWED_USER_ID", source)
        self.assertNotIn("MORNING_BRIEF_CHAT_ID", source)
        self.assertIn("MC_ROUTE_INCIDENTS_CHAT_ID", source)

    def test_explicit_sender_override_remains_a_narrow_test_seam(self):
        sender = os.path.join(self.tmp.name, "sender")
        open(sender, "w").close()
        os.chmod(sender, stat.S_IRUSR | stat.S_IWUSR | stat.S_IXUSR)
        completed = subprocess.CompletedProcess([], 0)
        env = {
            "HOME": self.home,
            "MORNING_BRIEF_INCIDENTS_CHAT_ID": CHAT_ID,
            "MORNING_BRIEF_SEND_BIN": sender,
            "MORNING_BRIEF_TELEGRAM_BOT_TOKEN": TOKEN,
            "TELEGRAM_BOT_TOKEN": TOKEN,
        }
        with mock.patch.dict(os.environ, env, clear=True), mock.patch.object(
                DEADMAN.subprocess, "run", return_value=completed) as run:
            self.assertTrue(DEADMAN._send("stale"))
        args, kwargs = run.call_args
        self.assertEqual(args[0], [sender, "send", CHAT_ID,
            "Morning Brief deadman: stale. Glance: menu-bar MC (dashboard panel) or light Home (dashboard open)."])
        self.assertNotIn("shell", kwargs)
        self.assertNotIn("MORNING_BRIEF_TELEGRAM_BOT_TOKEN", kwargs["env"])
        self.assertNotIn("TELEGRAM_BOT_TOKEN", kwargs["env"])

    def test_keychain_resolution_uses_fixed_argv_and_beats_plaintext(self):
        fallback = "123456:FALLBACK_abcdefghijklmnopqrstuvwxyz"
        self.write_config(
            "TELEGRAM_BOT_TOKEN_KEYCHAIN_SERVICE='mobile-connect-telegram'\n"
            "TELEGRAM_BOT_TOKEN='%s'\nMC_ROUTE_INCIDENTS_CHAT_ID='%s'\n" %
            (fallback, CHAT_ID))
        env = {
            "HOME": self.home,
            "MOBILE_CONNECT_CONFIG": self.config,
        }
        captured = {}

        def fake_run(argv, **kwargs):
            self.assertEqual(argv, ["/usr/bin/security",
                "find-generic-password", "-s",
                "mobile-connect-telegram", "-w"])
            self.assertNotIn(TOKEN, " ".join(argv))
            self.assertEqual(kwargs["timeout"], 5)
            return subprocess.CompletedProcess(argv, 0, stdout=(TOKEN + "\n").encode("ascii"))

        def fake_direct(chat_id, token, message):
            captured.update(chat_id=chat_id, token=token, message=message)
            return True

        with mock.patch.dict(os.environ, env, clear=True), mock.patch.object(
                DEADMAN.subprocess, "run", side_effect=fake_run) as run, mock.patch.object(
                    DEADMAN, "_direct_send", side_effect=fake_direct):
            self.assertTrue(DEADMAN._send("empty"))
        self.assertEqual(run.call_count, 1)
        self.assertEqual(captured["chat_id"], CHAT_ID)
        self.assertEqual(captured["token"], TOKEN)
        self.assertNotEqual(captured["token"], fallback)
        self.assertEqual(captured["message"],
            "Morning Brief deadman: empty. Glance: menu-bar MC (dashboard panel) or light Home (dashboard open).")

    def test_safe_plaintext_config_is_parsed_without_execution(self):
        marker = os.path.join(self.tmp.name, "injection-ran")
        self.write_config(
            "UNRELATED=$(touch %s)\r\n"
            "TELEGRAM_BOT_TOKEN=\"%s\" # fallback\r\n"
            "MC_ROUTE_INCIDENTS_CHAT_ID='%s'\r\n" % (marker, TOKEN, CHAT_ID))
        env = {"HOME": self.home, "MOBILE_CONNECT_CONFIG": self.config}
        captured = {}

        def fake_direct(chat_id, token, message):
            captured.update(chat_id=chat_id, token=token, message=message)
            return True

        with mock.patch.dict(os.environ, env, clear=True), mock.patch.object(
                DEADMAN.subprocess, "run",
                side_effect=AssertionError("unexpected subprocess")), mock.patch.object(
                    DEADMAN, "_direct_send", side_effect=fake_direct):
            self.assertTrue(DEADMAN._send("unsent"))
        self.assertFalse(os.path.exists(marker))
        self.assertEqual(captured["chat_id"], CHAT_ID)
        self.assertEqual(captured["token"], TOKEN)
        self.assertEqual(captured["message"],
            "Morning Brief deadman: unsent. Glance: menu-bar MC (dashboard panel) or light Home (dashboard open).")

    def test_authorization_id_is_never_a_destination_fallback(self):
        self.write_config(
            "TELEGRAM_BOT_TOKEN='%s'\nALLOWED_USER_ID='%s'\n" %
            (TOKEN, CHAT_ID))
        env = {"HOME": self.home, "MOBILE_CONNECT_CONFIG": self.config}
        with mock.patch.dict(os.environ, env, clear=True), mock.patch.object(
                DEADMAN, "_direct_send",
                side_effect=AssertionError("authorization id reached transport")):
            self.assertFalse(DEADMAN._send("missing"))

    def test_keychain_failure_uses_fallback_but_malformed_service_fails_closed(self):
        fallback = "123456:FALLBACK_abcdefghijklmnopqrstuvwxyz"
        self.write_config(
            "TELEGRAM_BOT_TOKEN_KEYCHAIN_SERVICE='mobile-connect-telegram'\n"
            "TELEGRAM_BOT_TOKEN='%s'\nMC_ROUTE_INCIDENTS_CHAT_ID='%s'\n" %
            (fallback, CHAT_ID))
        env = {"HOME": self.home, "MOBILE_CONNECT_CONFIG": self.config}
        captured = {}
        failed = subprocess.CompletedProcess([], 44, stdout=b"")

        def fake_direct(chat_id, token, message):
            captured.update(chat_id=chat_id, token=token, message=message)
            return True
        with mock.patch.dict(os.environ, env, clear=True), mock.patch.object(
                DEADMAN.subprocess, "run", return_value=failed), mock.patch.object(
                    DEADMAN, "_direct_send", side_effect=fake_direct):
            self.assertTrue(DEADMAN._send("missing"))
        self.assertEqual(captured["token"], fallback)

        marker = os.path.join(self.tmp.name, "hostile-service-ran")
        self.write_config(
            "TELEGRAM_BOT_TOKEN_KEYCHAIN_SERVICE='x; touch %s'\n"
            "TELEGRAM_BOT_TOKEN='%s'\nMC_ROUTE_INCIDENTS_CHAT_ID='%s'\n" %
            (marker, fallback, CHAT_ID))
        env = {"HOME": self.home, "MOBILE_CONNECT_CONFIG": self.config}
        with mock.patch.dict(os.environ, env, clear=True), mock.patch.object(
                DEADMAN.subprocess, "run",
                side_effect=AssertionError("hostile service reached subprocess")), mock.patch.object(
                    DEADMAN, "_direct_send",
                    side_effect=AssertionError("hostile service reached transport")):
            self.assertFalse(DEADMAN._send("missing"))
        self.assertFalse(os.path.exists(marker))

        self.write_config(
            "TELEGRAM_BOT_TOKEN_KEYCHAIN_SERVICE='mobile-connect-telegram'\n"
            "TELEGRAM_BOT_TOKEN='%s'\nMC_ROUTE_INCIDENTS_CHAT_ID='%s'\n" %
            (fallback, CHAT_ID))
        malformed = subprocess.CompletedProcess([], 0, stdout=b"\xff\xfe")
        env = {"HOME": self.home, "MOBILE_CONNECT_CONFIG": self.config}
        with mock.patch.dict(os.environ, env, clear=True), mock.patch.object(
                DEADMAN.subprocess, "run", return_value=malformed), mock.patch.object(
                    DEADMAN, "_direct_send",
                    side_effect=AssertionError("malformed token reached transport")):
            self.assertFalse(DEADMAN._send("missing"))

    def test_invalid_explicit_credential_and_insecure_config_fail_closed(self):
        self.write_config("TELEGRAM_BOT_TOKEN='%s'\nMC_ROUTE_INCIDENTS_CHAT_ID='%s'\n" %
                          (TOKEN, CHAT_ID), mode=0o644)
        with FakeTelegram() as server:
            env = self.direct_env(server,
                MORNING_BRIEF_TELEGRAM_BOT_TOKEN="not-a-token")
            with mock.patch.dict(os.environ, env, clear=True), mock.patch.object(
                    DEADMAN.subprocess, "run",
                    side_effect=AssertionError("unexpected subprocess")):
                self.assertFalse(DEADMAN._send("missing"))
            env.pop("MORNING_BRIEF_TELEGRAM_BOT_TOKEN")
            env.pop("MORNING_BRIEF_INCIDENTS_CHAT_ID")
            with mock.patch.dict(os.environ, env, clear=True), mock.patch.object(
                    DEADMAN.subprocess, "run", return_value=subprocess.CompletedProcess([], 0)):
                self.assertFalse(DEADMAN._send("missing"))
        self.assertEqual(server.requests, [])

    def test_duplicate_and_symlink_configs_fail_closed(self):
        duplicate = ("TELEGRAM_BOT_TOKEN='%s'\nTELEGRAM_BOT_TOKEN='%s'\n"
                     "MC_ROUTE_INCIDENTS_CHAT_ID='%s'\n") % (TOKEN, TOKEN, CHAT_ID)
        self.write_config(duplicate)
        with FakeTelegram() as server:
            env = self.direct_env(server)
            env.pop("MORNING_BRIEF_INCIDENTS_CHAT_ID")
            env.pop("MORNING_BRIEF_TELEGRAM_BOT_TOKEN")
            with mock.patch.dict(os.environ, env, clear=True), mock.patch.object(
                    DEADMAN.subprocess, "run",
                    side_effect=AssertionError("unexpected subprocess")):
                self.assertFalse(DEADMAN._send("missing"))
        self.assertEqual(server.requests, [])

        os.unlink(self.config)
        os.mkfifo(self.config, 0o600)
        with FakeTelegram() as server:
            env = self.direct_env(server)
            env.pop("MORNING_BRIEF_INCIDENTS_CHAT_ID")
            env.pop("MORNING_BRIEF_TELEGRAM_BOT_TOKEN")
            started = time.monotonic()
            with mock.patch.dict(os.environ, env, clear=True), mock.patch.object(
                    DEADMAN.subprocess, "run",
                    side_effect=AssertionError("unexpected subprocess")):
                self.assertFalse(DEADMAN._send("missing"))
            self.assertLess(time.monotonic() - started, 0.5)
        self.assertEqual(server.requests, [])

        target = os.path.join(self.tmp.name, "real-config")
        os.rename(self.config, target)
        os.symlink(target, self.config)
        with FakeTelegram() as server:
            env = self.direct_env(server)
            env.pop("MORNING_BRIEF_INCIDENTS_CHAT_ID")
            env.pop("MORNING_BRIEF_TELEGRAM_BOT_TOKEN")
            with mock.patch.dict(os.environ, env, clear=True), mock.patch.object(
                    DEADMAN.subprocess, "run",
                    side_effect=AssertionError("unexpected subprocess")):
                self.assertFalse(DEADMAN._send("missing"))
        self.assertEqual(server.requests, [])

    def test_http_acknowledgement_failures_never_count_as_sent(self):
        cases = [
            (200, {}, {"ok": False}),
            (200, {}, {"ok": True}),
            (200, {}, {"ok": True, "result": {"message_id": 0}}),
            (200, {}, {"ok": True, "result": {"message_id": True}}),
            (200, {}, []),
            (200, {}, b"not-json"),
            (204, {}, b""),
            (302, {"Location": "https://example.invalid/"}, b""),
            (500, {}, {"ok": True, "result": {"message_id": 1}}),
            (200, {}, b"{" + b"x" * 70000 + b"}"),
        ]
        for response in cases:
            with self.subTest(status=response[0], size=len(response[2])):
                with FakeTelegram([response]) as server, mock.patch.dict(
                        os.environ, self.direct_env(server), clear=True), mock.patch.object(
                            DEADMAN.subprocess, "run",
                            side_effect=AssertionError("unexpected subprocess")):
                    out, err = io.StringIO(), io.StringIO()
                    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
                        self.assertFalse(DEADMAN._send("partial"))
                self.assertEqual(len(server.requests), 1)
                self.assertNotIn(TOKEN, out.getvalue() + err.getvalue())

        with FakeTelegram([(200, {"X-Test-Drip": "0.03"}, {
                "ok": True, "result": {"message_id": 1}})]) as server:
            env = self.direct_env(server, MORNING_BRIEF_SEND_TIMEOUT_S="0.05")
            started = time.monotonic()
            with mock.patch.dict(os.environ, env, clear=True), mock.patch.object(
                    DEADMAN.subprocess, "run",
                    side_effect=AssertionError("unexpected subprocess")):
                self.assertFalse(DEADMAN._send("missing"))
            self.assertLess(time.monotonic() - started, 0.5)

    def test_timeout_and_invalid_api_bases_fail_without_secret_output(self):
        with FakeTelegram([(200, {"X-Test-Delay": "0.25"}, {
                "ok": True, "result": {"message_id": 1}})]) as server:
            env = self.direct_env(server, MORNING_BRIEF_SEND_TIMEOUT_S="0.05")
            with mock.patch.dict(os.environ, env, clear=True), mock.patch.object(
                    DEADMAN.subprocess, "run",
                    side_effect=AssertionError("unexpected subprocess")):
                out, err = io.StringIO(), io.StringIO()
                with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
                    self.assertFalse(DEADMAN._send("missing"))
                self.assertNotIn(TOKEN, out.getvalue() + err.getvalue())
        invalid = [
            "http://example.com", "file:///tmp/x", "https://user@evil.example",
            "https://api.telegram.org.evil.example", "https://api.telegram.org/x",
            "https://api.telegram.org?x=1", "https://api.telegram.org:443",
            " http://127.0.0.1:1",
        ]
        for base in invalid:
            with self.subTest(base=base):
                env = {
                    "HOME": self.home,
                    "MORNING_BRIEF_INCIDENTS_CHAT_ID": CHAT_ID,
                    "MORNING_BRIEF_TELEGRAM_BOT_TOKEN": TOKEN,
                    "MORNING_BRIEF_TELEGRAM_API_BASE": base,
                }
                with mock.patch.dict(os.environ, env, clear=True), mock.patch.object(
                        DEADMAN.subprocess, "run",
                        side_effect=AssertionError("unexpected subprocess")):
                    self.assertFalse(DEADMAN._send("missing"))

    def test_loopback_transport_requires_test_mode_and_purpose_token(self):
        with FakeTelegram() as server:
            env = self.direct_env(server)
            env.pop("MORNING_BRIEF_TELEGRAM_TEST_MODE")
            with mock.patch.dict(os.environ, env, clear=True), mock.patch.object(
                    DEADMAN.subprocess, "run",
                    side_effect=AssertionError("unexpected subprocess")):
                self.assertFalse(DEADMAN._send("missing"))

            env = self.direct_env(server)
            env.pop("MORNING_BRIEF_TELEGRAM_BOT_TOKEN")
            env["TELEGRAM_BOT_TOKEN"] = TOKEN
            with mock.patch.dict(os.environ, env, clear=True), mock.patch.object(
                    DEADMAN.subprocess, "run",
                    side_effect=AssertionError("unexpected subprocess")):
                self.assertFalse(DEADMAN._send("missing"))

            self.write_config(
                "TELEGRAM_BOT_TOKEN_KEYCHAIN_SERVICE='mobile-connect-telegram'\n"
                "MC_ROUTE_INCIDENTS_CHAT_ID='%s'\n" % CHAT_ID)
            env = self.direct_env(server)
            env.pop("MORNING_BRIEF_INCIDENTS_CHAT_ID")
            env.pop("MORNING_BRIEF_TELEGRAM_BOT_TOKEN")
            keychain = subprocess.CompletedProcess([], 0,
                stdout=(TOKEN + "\n").encode("ascii"))
            with mock.patch.dict(os.environ, env, clear=True), mock.patch.object(
                    DEADMAN.subprocess, "run", return_value=keychain):
                self.assertFalse(DEADMAN._send("missing"))
        self.assertEqual(server.requests, [])

    def test_inner_deadline_does_not_postpone_existing_alarm(self):
        previous_handler = signal.getsignal(signal.SIGALRM)
        previous_timer = signal.getitimer(signal.ITIMER_REAL)
        fired = []

        def outer_alarm(_signum, _frame):
            fired.append(time.monotonic())

        started = time.monotonic()
        try:
            signal.signal(signal.SIGALRM, outer_alarm)
            signal.setitimer(signal.ITIMER_REAL, 0.05)
            with DEADMAN._wall_clock_deadline(0.5):
                time.sleep(0.20)
        finally:
            signal.setitimer(signal.ITIMER_REAL, 0)
            signal.signal(signal.SIGALRM, previous_handler)
            if previous_timer[0] > 0:
                signal.setitimer(signal.ITIMER_REAL, previous_timer[0],
                                 previous_timer[1])
        self.assertEqual(len(fired), 1)
        self.assertLess(fired[0] - started, 0.15)

    def test_unknown_category_is_never_transmitted(self):
        with FakeTelegram() as server, mock.patch.dict(
                os.environ, self.direct_env(server), clear=True), mock.patch.object(
                    DEADMAN.subprocess, "run",
                    side_effect=AssertionError("unexpected subprocess")):
            self.assertFalse(DEADMAN._send("missing\nsecret source text"))
        self.assertEqual(server.requests, [])

    def run_process(self, server, now):
        env = self.direct_env(server,
            MORNING_BRIEF_DEADMAN_NOW_EPOCH=str(now),
            MORNING_BRIEF_DEADMAN_THROTTLE_S="3600",
            PYTHONPATH=os.path.join(ROOT, "scripts"))
        argv = [sys.executable, DEADMAN_PATH]
        completed = subprocess.run(argv, env=env, stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, text=True, timeout=10)
        self.assertNotIn(TOKEN, " ".join(argv) + completed.stdout + completed.stderr)
        return completed

    def test_direct_transport_is_serialized_and_failed_send_remains_retryable(self):
        responses = [
            (200, {}, {"ok": False}),
            (200, {}, {"ok": True, "result": {"message_id": 9}}),
        ]
        with FakeTelegram(responses) as server:
            first = self.run_process(server, 1783676000)
            alert_path = os.path.join(self.state, "morning-brief",
                                      "deadman-alert-state.json")
            self.assertNotEqual(first.returncode, 0)
            self.assertFalse(os.path.exists(alert_path))
            second = self.run_process(server, 1783676001)
            self.assertNotEqual(second.returncode, 0)
            self.assertTrue(os.path.isfile(alert_path))
            self.assertEqual(stat.S_IMODE(os.stat(alert_path).st_mode), 0o600)
        self.assertEqual(len(server.requests), 2)

    def test_concurrent_direct_success_sends_once_and_leaks_no_secret(self):
        with FakeTelegram() as server:
            env = self.direct_env(server,
                MORNING_BRIEF_DEADMAN_NOW_EPOCH="1783677000",
                MORNING_BRIEF_DEADMAN_THROTTLE_S="3600",
                PYTHONPATH=os.path.join(ROOT, "scripts"))
            argv = [sys.executable, DEADMAN_PATH]
            first = subprocess.Popen(argv, env=env, stdout=subprocess.PIPE,
                                     stderr=subprocess.PIPE, text=True)
            second = subprocess.Popen(argv, env=env, stdout=subprocess.PIPE,
                                      stderr=subprocess.PIPE, text=True)
            out1, err1 = first.communicate(timeout=10)
            out2, err2 = second.communicate(timeout=10)
        self.assertNotEqual(first.returncode, 0)
        self.assertNotEqual(second.returncode, 0)
        self.assertEqual(len(server.requests), 1)
        self.assertNotIn(TOKEN, " ".join(argv) + out1 + err1 + out2 + err2)
        for directory, _dirs, files in os.walk(self.state):
            for name in files:
                with open(os.path.join(directory, name), errors="replace") as handle:
                    self.assertNotIn(TOKEN, handle.read())


if __name__ == "__main__":
    unittest.main(verbosity=2)
