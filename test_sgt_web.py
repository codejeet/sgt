#!/usr/bin/env python3
"""Tests for sgt-web control panel."""

import importlib.machinery
import json
import os
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import patch


# Import sgt-web module (has a hyphen in the filename)
import importlib.util

_sgt_web_path = str(Path(__file__).parent / "sgt-web")
spec = importlib.util.spec_from_loader(
    "sgt_web",
    importlib.machinery.SourceFileLoader("sgt_web", _sgt_web_path),
)
sgt_web = importlib.util.module_from_spec(spec)

# Override __name__ so the module's `if __name__ == "__main__"` block doesn't run
sgt_web.__name__ = "sgt_web"
spec.loader.exec_module(sgt_web)


class TestStateReader(unittest.TestCase):
    """Test state file parsing and data reading."""

    def setUp(self):
        self.tmpdir = tempfile.mkdtemp()
        self.sgt_root = Path(self.tmpdir)
        self.config = self.sgt_root / ".sgt"
        self.config.mkdir(parents=True)

        # Set up directories
        for d in ["rigs", "polecats", "dogs", "crew", "merge-queue"]:
            (self.config / d).mkdir()
        (self.sgt_root / "molecules").mkdir()

        # Patch module globals
        sgt_web.SGT_ROOT = self.sgt_root
        sgt_web.SGT_CONFIG = self.config
        sgt_web.SGT_RIGS = self.config / "rigs"
        sgt_web.SGT_POLECATS = self.config / "polecats"
        sgt_web.SGT_DOGS = self.config / "dogs"
        sgt_web.SGT_CREW = self.config / "crew"
        sgt_web.SGT_MERGE_QUEUE = self.config / "merge-queue"
        sgt_web.SGT_LOG = self.sgt_root / "sgt.log"
        sgt_web.SGT_DAEMON_PID = self.config / "daemon.pid"
        sgt_web.SGT_DEACON_HEARTBEAT = self.config / "deacon-heartbeat.json"
        sgt_web.SGT_MOLECULES = self.sgt_root / "molecules"
        sgt_web.SGT_ESCALATION = self.config / "escalation.json"

    def tearDown(self):
        import shutil
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def test_parse_state_file(self):
        f = self.config / "test"
        f.write_text('FOO="bar"\nBAZ=qux\n# comment\nNUM=42\n')
        result = sgt_web.parse_state_file(f)
        self.assertEqual(result["FOO"], "bar")
        self.assertEqual(result["BAZ"], "qux")
        self.assertEqual(result["NUM"], "42")

    def test_get_rigs(self):
        (self.config / "rigs" / "myapp").write_text("https://github.com/owner/repo\n")
        rigs = sgt_web.get_rigs()
        self.assertEqual(len(rigs), 1)
        self.assertEqual(rigs[0]["name"], "myapp")
        self.assertEqual(rigs[0]["owner_repo"], "owner/repo")

    def test_get_rigs_empty(self):
        rigs = sgt_web.get_rigs()
        self.assertEqual(rigs, [])

    def test_get_polecats(self):
        (self.config / "polecats" / "myapp-abc123").write_text(
            'RIG="myapp"\nREPO="https://github.com/o/r"\nISSUE="5"\nSTATUS="running"\n'
        )
        pcs = sgt_web.get_polecats()
        self.assertEqual(len(pcs), 1)
        self.assertEqual(pcs[0]["name"], "myapp-abc123")
        self.assertEqual(pcs[0]["RIG"], "myapp")
        self.assertEqual(pcs[0]["STATUS"], "running")

    def test_get_dogs(self):
        (self.config / "dogs" / "dog-xyz").write_text(
            'RIG="myapp"\nSTATUS="running"\n'
        )
        dogs = sgt_web.get_dogs()
        self.assertEqual(len(dogs), 1)
        self.assertEqual(dogs[0]["RIG"], "myapp")

    def test_get_crew(self):
        (self.config / "crew" / "alice").write_text(
            'NAME="alice"\nRIG="myapp"\nROLE="reviewer"\n'
        )
        crew = sgt_web.get_crew()
        self.assertEqual(len(crew), 1)
        self.assertEqual(crew[0]["ROLE"], "reviewer")

    def test_get_merge_queue(self):
        (self.config / "merge-queue" / "entry1").write_text(
            'POLECAT="myapp-abc"\nPR="42"\nAUTO_MERGE="true"\n'
        )
        q = sgt_web.get_merge_queue()
        self.assertEqual(len(q), 1)
        self.assertEqual(q[0]["PR"], "42")

    def test_get_log(self):
        (self.sgt_root / "sgt.log").write_text("line1\nline2\nline3\nline4\nline5\n")
        log = sgt_web.get_log(3)
        self.assertEqual(len(log), 3)
        self.assertEqual(log[0], "line3")

    def test_get_log_empty(self):
        log = sgt_web.get_log()
        self.assertEqual(log, [])

    def test_get_molecules(self):
        (self.sgt_root / "molecules" / "feature.yml").write_text("name: feature\n")
        mols = sgt_web.get_molecules()
        self.assertEqual(len(mols), 1)
        self.assertEqual(mols[0]["name"], "feature")

    def test_get_escalation(self):
        data = {"levels": {"critical": {"timeout_minutes": 15}}}
        (self.config / "escalation.json").write_text(json.dumps(data))
        esc = sgt_web.get_escalation()
        self.assertEqual(esc["levels"]["critical"]["timeout_minutes"], 15)

    def test_get_escalation_missing(self):
        self.assertIsNone(sgt_web.get_escalation())

    def test_get_full_status(self):
        status = sgt_web.get_full_status()
        self.assertIn("timestamp", status)
        self.assertIn("rigs", status)
        self.assertIn("polecats", status)
        self.assertIn("dogs", status)
        self.assertIn("agents", status)
        # Must be JSON serializable
        json.dumps(status)

    def test_get_agents_no_daemon(self):
        agents = sgt_web.get_agents()
        self.assertIn("daemon", agents)
        self.assertFalse(agents["daemon"]["running"])


class TestHTTPServer(unittest.TestCase):
    """Test the HTTP server endpoints."""

    @classmethod
    def setUpClass(cls):
        cls.tmpdir = tempfile.mkdtemp()
        cls.sgt_root = Path(cls.tmpdir)
        cls.config = cls.sgt_root / ".sgt"
        cls.config.mkdir(parents=True)
        for d in ["rigs", "polecats", "dogs", "crew", "merge-queue"]:
            (cls.config / d).mkdir()
        (cls.sgt_root / "molecules").mkdir()
        (cls.sgt_root / "sgt.log").write_text("[2026-01-01] test log\n")

        # Add a rig
        (cls.config / "rigs" / "test-rig").write_text("https://github.com/test/repo\n")

        # Patch globals
        sgt_web.SGT_ROOT = cls.sgt_root
        sgt_web.SGT_CONFIG = cls.config
        sgt_web.SGT_RIGS = cls.config / "rigs"
        sgt_web.SGT_POLECATS = cls.config / "polecats"
        sgt_web.SGT_DOGS = cls.config / "dogs"
        sgt_web.SGT_CREW = cls.config / "crew"
        sgt_web.SGT_MERGE_QUEUE = cls.config / "merge-queue"
        sgt_web.SGT_LOG = cls.sgt_root / "sgt.log"
        sgt_web.SGT_DAEMON_PID = cls.config / "daemon.pid"
        sgt_web.SGT_DEACON_HEARTBEAT = cls.config / "deacon-heartbeat.json"
        sgt_web.SGT_MOLECULES = cls.sgt_root / "molecules"
        sgt_web.SGT_ESCALATION = cls.config / "escalation.json"

        # Start server in a thread
        import threading
        from http.server import HTTPServer
        cls.server = HTTPServer(("127.0.0.1", 7799), sgt_web.SGTHandler)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        time.sleep(0.5)

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        import shutil
        shutil.rmtree(cls.tmpdir, ignore_errors=True)

    def _get(self, path):
        import urllib.request
        url = f"http://127.0.0.1:7799{path}"
        with urllib.request.urlopen(url) as resp:
            return resp.status, json.loads(resp.read())

    def _get_html(self, path):
        import urllib.request
        url = f"http://127.0.0.1:7799{path}"
        with urllib.request.urlopen(url) as resp:
            return resp.status, resp.read().decode()

    def test_dashboard_html(self):
        status, body = self._get_html("/")
        self.assertEqual(status, 200)
        self.assertIn("SGT Control Panel", body)
        self.assertIn("connectSSE", body)

    def test_api_status(self):
        status, data = self._get("/api/status")
        self.assertEqual(status, 200)
        self.assertIn("timestamp", data)
        self.assertIn("rigs", data)
        self.assertEqual(len(data["rigs"]), 1)
        self.assertEqual(data["rigs"][0]["name"], "test-rig")

    def test_api_rigs(self):
        status, data = self._get("/api/rigs")
        self.assertEqual(status, 200)
        self.assertEqual(len(data["rigs"]), 1)

    def test_api_polecats(self):
        status, data = self._get("/api/polecats")
        self.assertEqual(status, 200)
        self.assertIsInstance(data["polecats"], list)

    def test_api_log(self):
        status, data = self._get("/api/log?lines=10")
        self.assertEqual(status, 200)
        self.assertEqual(len(data["log"]), 1)
        self.assertIn("test log", data["log"][0])

    def test_api_agents(self):
        status, data = self._get("/api/agents")
        self.assertEqual(status, 200)
        self.assertIn("daemon", data["agents"])

    def test_api_molecules(self):
        status, data = self._get("/api/molecules")
        self.assertEqual(status, 200)
        self.assertIsInstance(data["molecules"], list)


if __name__ == "__main__":
    unittest.main()
