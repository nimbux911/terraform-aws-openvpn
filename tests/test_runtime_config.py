"""Offline safety checks: temporary files, fake Docker, no AWS or VPN changes."""

import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch


MODULE = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("runtime", MODULE / "resources/scripts/apply_runtime_config.py")
runtime = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runtime)


class FakeDocker:
    def __init__(self, failed_starts=0):
        self.restarts = 0
        self.failed_starts = failed_starts

    def preflight(self, conf_dir, network):
        pass

    def restart(self):
        self.restarts += 1

    def wait_healthy(self, network):
        if self.failed_starts:
            self.failed_starts -= 1
            raise runtime.RuntimeConfigError("Simulated startup failure")


class RuntimeSafetyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="openvpn-safety-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.conf = self.root / "conf"
        for directory in ("conf/ccd", "conf/pki/issued", "conf/pki/private", "keys"):
            (self.root / directory).mkdir(parents=True, exist_ok=True)
        self.path = self.conf / "openvpn.conf"
        self.original = (
            "server 192.168.255.0 255.255.255.0\ntopology subnet\n"
            "proto udp\nport 1194\ndev tun0\n"
            "client-config-dir /etc/openvpn/ccd\nstatus /tmp/openvpn-status.log\n"
            "push \"route 172.23.0.0 255.255.0.0\"\n"
        )
        self.path.write_text(self.original)
        self.add_client("fixed", "192.168.255.11")
        self.add_client("manual")
        self.request = {
            "volume_path": str(self.root), "vpn_client_cidr": "192.168.255.0/24",
            "config": {"dynamic_pool": {"start": "192.168.255.101", "end": "192.168.255.200"},
                       "receive_buffer_bytes": 1048576},
            "vpn_users": {"fixed": {"group": "admins", "ip": "192.168.255.11"},
                          "manual": {"group": "admins", "ip": None}},
        }
        self.limit = patch.object(runtime, "read_receive_buffer_limit", return_value=4194304)
        self.limit.start()
        self.addCleanup(self.limit.stop)

    def add_client(self, name, address=None):
        for directory, suffix in (("conf/pki/issued", "crt"), ("conf/pki/private", "key"), ("keys", "ovpn")):
            (self.root / directory / f"{name}.{suffix}").write_text("Existing fixture; never replace")
        if address:
            (self.conf / "ccd" / name).write_text(f"ifconfig-push {address} 255.255.255.0\n")

    def identities(self):
        return {str(p.relative_to(self.root)): (p.read_bytes(), p.stat().st_mtime_ns)
                for directory in (self.conf / "ccd", self.conf / "pki", self.root / "keys")
                for p in directory.rglob("*") if p.is_file()}

    def apply(self, docker):
        with contextlib.redirect_stdout(io.StringIO()):
            return runtime.apply_runtime_config(self.request, docker)

    def test_disabled_does_not_change_configuration_or_restart(self):
        self.request["config"] = None
        docker = FakeDocker()
        self.assertFalse(self.apply(docker)["changed"])
        self.assertEqual(self.path.read_text(), self.original)
        self.assertEqual(docker.restarts, 0)

    def test_apply_preserves_identities_and_repeat_is_noop(self):
        before = self.identities()
        docker = FakeDocker()
        result = self.apply(docker)
        self.assertEqual(docker.restarts, 1)
        text = self.path.read_text()
        self.assertIn("server 192.168.255.0 255.255.255.0 nopool\n", text)
        self.assertIn("ifconfig-pool 192.168.255.101 192.168.255.200 255.255.255.0\n", text)
        self.assertIn("rcvbuf 1048576\n", text)
        self.assertEqual(self.identities(), before)
        self.assertFalse((self.conf / "ccd/manual").exists())
        backup = Path(result["backup"])
        self.assertEqual(backup.read_text(), self.original)
        self.assertEqual(backup.stat().st_mode & 0o777, 0o600)
        mtime = self.path.stat().st_mtime_ns
        self.assertFalse(self.apply(docker)["changed"])
        self.assertEqual(docker.restarts, 1)
        self.assertEqual(self.path.stat().st_mtime_ns, mtime)
        self.assertEqual(len(list(backup.parent.iterdir())), 1)

    def test_unknown_ccd_pool_overlap_aborts_before_restart(self):
        self.add_client("unlisted", "192.168.255.150")
        docker = FakeDocker()
        before = self.identities()
        with self.assertRaisesRegex(runtime.RuntimeConfigError, "overlaps"):
            self.apply(docker)
        self.assertEqual(self.path.read_text(), self.original)
        self.assertEqual(self.identities(), before)
        self.assertEqual(docker.restarts, 0)
        self.assertFalse((self.conf / "runtime-config-backups").exists())

    def test_buffer_over_kernel_limit_aborts_before_restart(self):
        self.request["config"]["receive_buffer_bytes"] = 8388608
        docker = FakeDocker()
        with self.assertRaisesRegex(runtime.RuntimeConfigError, "rmem_max"):
            self.apply(docker)
        self.assertEqual(self.path.read_text(), self.original)
        self.assertEqual(docker.restarts, 0)

    def test_failed_start_rolls_back_without_modifying_identities(self):
        docker = FakeDocker(failed_starts=1)
        before = self.identities()
        with self.assertRaisesRegex(runtime.RuntimeConfigError, "original configuration restored"):
            self.apply(docker)
        self.assertEqual(docker.restarts, 2)
        self.assertEqual(self.path.read_text(), self.original)
        self.assertEqual(self.identities(), before)

    def test_failed_recovery_reports_manual_intervention(self):
        docker = FakeDocker(failed_starts=2)
        with self.assertRaisesRegex(runtime.RuntimeConfigError, "Manual recovery required"):
            self.apply(docker)
        self.assertEqual(self.path.read_text(), self.original)
        self.assertEqual(docker.restarts, 2)
        self.assertEqual(len(list((self.conf / "runtime-config-backups").iterdir())), 1)

    def test_concurrent_manual_edit_is_not_overwritten(self):
        docker = FakeDocker()
        def edit(network):
            self.path.write_text("# Administrator changed this during restart\n")
            raise runtime.RuntimeConfigError("Simulated startup failure")
        docker.wait_healthy = edit
        with self.assertRaisesRegex(runtime.RuntimeConfigError, "refusing to overwrite"):
            self.apply(docker)
        self.assertEqual(self.path.read_text(), "# Administrator changed this during restart\n")
        self.assertEqual(docker.restarts, 1)

    def test_custom_firewall_rules_are_rejected(self):
        network = runtime.ipaddress.IPv4Network("192.168.255.0/24")
        default = "*filter\n:INPUT ACCEPT [0:0]\n:FORWARD ACCEPT [0:0]\n:OUTPUT ACCEPT [0:0]\nCOMMIT\n"
        runtime.validate_namespace_rules(default, network)
        with self.assertRaises(runtime.RuntimeConfigError):
            runtime.validate_namespace_rules(default.replace("FORWARD ACCEPT", "FORWARD DROP"), network)
        with self.assertRaises(runtime.RuntimeConfigError):
            runtime.validate_namespace_rules(default.replace("COMMIT", "-A FORWARD -j DROP\nCOMMIT"), network)

    def render(self, template, values):
        expression = "jsonencode(templatefile(" + json.dumps(str(template)) + ",jsondecode(" + json.dumps(json.dumps(values)) + ")))\n"
        result = subprocess.run([os.environ.get("TERRAFORM", "terraform"), "console", "-no-color"],
                                cwd=self.root, input=expression, text=True, capture_output=True, check=True)
        return json.loads(json.loads(result.stdout))

    @unittest.skipUnless(shutil.which(os.environ.get("TERRAFORM", "terraform")), "Terraform is needed to render templates")
    def test_runtime_template_produces_valid_shell_and_python(self):
        script = self.render(MODULE / "resources/scripts/apply_runtime_config.sh.tpl", {
            "runtime_script": (MODULE / "resources/scripts/apply_runtime_config.py").read_text(),
            "request": self.request,
        })
        subprocess.run(["bash", "-n"], input=script, text=True, check=True)
        source = script.split("<<'PY_OPENVPN_RUNTIME'\n", 1)[1].rsplit("\nPY_OPENVPN_RUNTIME", 1)[0]
        compile(source, "rendered-runtime.py", "exec")

    @unittest.skipUnless(shutil.which(os.environ.get("TERRAFORM", "terraform")), "Terraform is needed to render templates")
    def test_additive_script_rejects_fixed_ip_inside_explicit_nopool_range(self):
        self.path.write_text(self.original.replace("255.255.255.0\n", "255.255.255.0 nopool\n", 1)
                             + "ifconfig-pool 192.168.255.101 192.168.255.200 255.255.255.0\n")
        (self.conf / "pki/index.txt").touch()
        script = self.render(MODULE / "resources/scripts/sync_profiles_additive.sh.tpl", {
            "volume_path": str(self.root), "vpn_endpoint": "vpn.example.test", "vpn_client_cidr": "192.168.255.0/24",
            "vpn_users": {"new": {"group": "admins", "ip": "192.168.255.150"}},
        })
        fake_bin = self.root / "bin"
        fake_bin.mkdir()
        for name, body in {
            "flock": "exit 0",
            "docker": "if [ \"$1\" = inspect ]; then echo true; elif [ \"$1\" = exec ] && [ \"$3\" = cat ]; then echo 'ROUTING TABLE'; else exit 99; fi",
        }.items():
            path = fake_bin / name
            path.write_text("#!/bin/bash\n" + body + "\n")
            path.chmod(0o755)
        result = subprocess.run(["bash"], input=script, text=True, capture_output=True,
                                env=dict(os.environ, PATH=f"{fake_bin}:{os.environ['PATH']}"))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("overlaps the dynamic pool", result.stderr)
        self.assertFalse((self.conf / "ccd/new").exists())


if __name__ == "__main__":
    unittest.main()
