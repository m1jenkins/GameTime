#!/usr/bin/env python3
"""Owned-process cleanup checks; these do not claim database race coverage."""
import contextlib
import importlib.util
import io
from pathlib import Path
import select
import subprocess
import sys
import unittest


source = Path(__file__).resolve().parents[1] / "beta-scoped-locks-p4-concurrency.py"
spec = importlib.util.spec_from_file_location("p4_runner", source)
assert spec and spec.loader
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class OwnedCleanupTests(unittest.TestCase):
    def setUp(self):
        self.children = []

    def tearDown(self):
        for child in self.children:
            if child.poll() is None:
                child.kill()
            child.communicate(timeout=5)

    def waiting_child(self):
        child = subprocess.Popen(
            [sys.executable, "-u", "-c", "import time; print('ready'); time.sleep(60)"],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        self.children.append(child)
        self.assertTrue(select.select([child.stdout], [], [], 5)[0], "child did not start")
        self.assertEqual(child.stdout.readline().strip(), "ready")
        return child

    def test_timed_out_child_is_collected_before_gate_shutdown(self):
        child = self.waiting_child()
        with self.assertRaises(subprocess.TimeoutExpired):
            child.communicate(timeout=0.02)
        shutdown_called = []

        def disable_gates():
            self.assertIsNotNone(child.returncode, "shutdown must not wait behind our child")
            shutdown_called.append(True)
            return subprocess.CompletedProcess([], 0, "", "")

        with contextlib.redirect_stdout(io.StringIO()) as output:
            runner.cleanup_owned([child], disable_gates)
        self.assertEqual(shutdown_called, [True])
        self.assertIn("gates disabled", output.getvalue())

    def test_cleanup_leaves_an_unowned_process_running(self):
        owned = self.waiting_child()
        unowned = self.waiting_child()
        with contextlib.redirect_stdout(io.StringIO()):
            runner.cleanup_owned([owned], lambda: subprocess.CompletedProcess([], 0, "", ""))
        self.assertIsNotNone(owned.returncode)
        self.assertIsNone(unowned.poll())

    def test_failed_gate_shutdown_is_reported_without_success_claim(self):
        with contextlib.redirect_stdout(io.StringIO()) as output:
            with self.assertRaisesRegex(RuntimeError, "Could not disable.*permission denied"):
                runner.cleanup_owned([], lambda: subprocess.CompletedProcess([], 1, "", "permission denied"))
        self.assertNotIn("gates disabled", output.getvalue())

    def test_already_collected_child_can_be_cleaned_up_again(self):
        child = self.waiting_child()
        child.kill()
        child.communicate(timeout=5)
        with contextlib.redirect_stdout(io.StringIO()) as output:
            runner.cleanup_owned([child], lambda: subprocess.CompletedProcess([], 0, "", ""))
        self.assertIn("gates disabled", output.getvalue())

    def test_shutdown_timeout_propagates_after_child_cleanup(self):
        child = self.waiting_child()

        def timeout():
            raise subprocess.TimeoutExpired("owned gate shutdown", 20)

        with contextlib.redirect_stdout(io.StringIO()) as output:
            with self.assertRaises(subprocess.TimeoutExpired):
                runner.cleanup_owned([child], timeout)
        self.assertIsNotNone(child.returncode)
        self.assertNotIn("gates disabled", output.getvalue())


if __name__ == "__main__":
    unittest.main()
