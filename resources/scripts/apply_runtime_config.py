"""Opt-in OpenVPN pool/buffer reconciliation. Invoked by SSM, not at bootstrap."""

import datetime
import fcntl
import ipaddress
import json
import os
from pathlib import Path
import re
import shlex
import stat
import subprocess
import tempfile
import time


class RuntimeConfigError(RuntimeError):
    pass


def directives(text):
    """Read active options without interpreting inline certificate/key material."""
    result = []
    inline = None
    for index, line in enumerate(text.splitlines(keepends=True)):
        stripped = line.strip()
        if inline:
            if stripped == f"</{inline}>":
                inline = None
            continue
        if stripped.startswith("<") and stripped.endswith(">"):
            inline = stripped[1:-1]
            continue
        try:
            words = shlex.split(line, comments=True)
        except ValueError as error:
            raise RuntimeConfigError(f"Cannot parse configuration line {index + 1}.") from error
        if words:
            if words[0] in ("config", "include", "plugin"):
                raise RuntimeConfigError("Included configurations/plugins need manual review; no changes made.")
            result.append((index, words))
    if inline:
        raise RuntimeConfigError("Unterminated inline configuration block.")
    return result


def one_option(options, name, required=False):
    matches = [(index, words) for index, words in options if words[0] == name]
    if len(matches) > 1 or (required and not matches):
        raise RuntimeConfigError(f"Expected {'exactly one' if required else 'at most one'} {name} directive.")
    return matches[0] if matches else None


def validate_ccds(conf_dir, network, pool, users):
    addresses = {}
    by_name = {}
    ccd_dir = conf_dir / "ccd"
    if not ccd_dir.is_dir():
        raise RuntimeConfigError("CCD directory is missing; refusing to change the pool.")
    for path in sorted(ccd_dir.iterdir()):
        if not path.is_file() or path.name.startswith("."):
            continue
        option = one_option(directives(path.read_text()), "ifconfig-push")
        if not option:
            continue
        words = option[1]
        if len(words) not in (3, 4) or words[2] != str(network.netmask):
            raise RuntimeConfigError(f"Unsupported fixed-address directive in CCD {path.name}.")
        address = ipaddress.IPv4Address(words[1])
        if not network.network_address + 1 < address < network.broadcast_address:
            raise RuntimeConfigError(f"CCD {path.name} has an invalid client address.")
        if pool[0] <= address <= pool[1]:
            raise RuntimeConfigError(f"CCD {path.name} overlaps the requested dynamic pool.")
        if address in addresses:
            raise RuntimeConfigError(f"Duplicate fixed address in CCDs {addresses[address]} and {path.name}.")
        addresses[address] = path.name
        by_name[path.name] = address
    for name, user in users.items():
        if user.get("ip") is None:
            continue
        address = ipaddress.IPv4Address(user["ip"])
        if not network.network_address + 1 < address < network.broadcast_address:
            raise RuntimeConfigError(f"Declared fixed IP for {name} is outside the client address range.")
        if pool[0] <= address <= pool[1]:
            raise RuntimeConfigError(f"Declared fixed IP for {name} overlaps the requested dynamic pool.")
        if name in by_name and by_name[name] != address:
            raise RuntimeConfigError(f"CCD for {name} differs from its declared fixed IP.")
        if address in addresses and addresses[address] != name:
            raise RuntimeConfigError(f"Declared fixed IP for {name} is reserved by another CCD.")
        if name not in by_name and (conf_dir / "pki" / "issued" / f"{name}.crt").exists():
            raise RuntimeConfigError(f"Existing client {name} has no matching fixed CCD; migrate it separately.")


def read_receive_buffer_limit():
    return int(Path("/proc/sys/net/core/rmem_max").read_text().strip())


def build_candidate(original, request, conf_dir):
    config = request["config"]
    if not config or all(config.get(key) is None for key in ("dynamic_pool", "receive_buffer_bytes")):
        raise RuntimeConfigError("Configure a pool and/or receive buffer, or disable runtime management.")
    options = directives(original)
    server = one_option(options, "server", required=True)
    if len(server[1]) not in (3, 4) or (len(server[1]) == 4 and server[1][3] != "nopool"):
        raise RuntimeConfigError("Unsupported server directive.")
    network = ipaddress.IPv4Network(f"{server[1][1]}/{server[1][2]}", strict=True)
    if network != ipaddress.IPv4Network(request["vpn_client_cidr"], strict=True):
        raise RuntimeConfigError("vpn_client_cidr differs from the running configuration.")
    proto = one_option(options, "proto", required=True)
    if proto[1][1:] not in (["udp"], ["udp4"]):
        raise RuntimeConfigError("Runtime management currently supports the module's IPv4 UDP server only.")
    if one_option(options, "dev", required=True)[1][1:] != ["tun0"] or one_option(options, "port", required=True)[1][1:] != ["1194"]:
        raise RuntimeConfigError("Runtime management requires the module's tun0 device and port 1194.")
    topology = one_option(options, "topology", required=True)
    if topology[1][1:] != ["subnet"]:
        raise RuntimeConfigError("Runtime management requires topology subnet.")
    replacements = {}
    additions = []
    pool = config.get("dynamic_pool")
    if pool is not None:
        first, last = ipaddress.IPv4Address(pool["start"]), ipaddress.IPv4Address(pool["end"])
        if not network.network_address + 1 < first <= last < network.broadcast_address:
            raise RuntimeConfigError("Dynamic pool is reversed or includes reserved/out-of-subnet addresses.")
        validate_ccds(conf_dir, network, (first, last), request.get("vpn_users", {}))
        desired_server = ["server", str(network.network_address), str(network.netmask), "nopool"]
        if server[1] != desired_server:
            replacements[server[0]] = " ".join(desired_server) + "\n"
        explicit = one_option(options, "ifconfig-pool")
        desired_pool = ["ifconfig-pool", str(first), str(last), str(network.netmask)]
        if explicit is None:
            additions.append(" ".join(desired_pool) + "\n")
        elif explicit[1] != desired_pool:
            replacements[explicit[0]] = " ".join(desired_pool) + "\n"
    buffer_size = config.get("receive_buffer_bytes")
    if buffer_size is not None:
        if isinstance(buffer_size, bool) or not isinstance(buffer_size, int) or not 1 <= buffer_size <= 2147483647:
            raise RuntimeConfigError("receive_buffer_bytes must be a positive integer.")
        if buffer_size > read_receive_buffer_limit():
            raise RuntimeConfigError("receive_buffer_bytes exceeds the host rmem_max; no sysctl was changed.")
        current = one_option(options, "rcvbuf")
        desired_buffer = ["rcvbuf", str(buffer_size)]
        if current is None:
            additions.append(" ".join(desired_buffer) + "\n")
        elif current[1] != desired_buffer:
            replacements[current[0]] = " ".join(desired_buffer) + "\n"
    lines = original.splitlines(keepends=True)
    candidate = "".join(replacements.get(index, line) for index, line in enumerate(lines))
    if additions:
        candidate = candidate.rstrip("\n") + "\n" + "".join(additions)
    return candidate, network


def validate_filter_rules(text):
    policies = {}
    for line in text.splitlines():
        if not line or line.startswith(("#", "*")) or line == "COMMIT":
            continue
        if line.startswith(":"):
            chain, policy = line[1:].split()[:2]
            policies[chain] = policy
        else:
            raise RuntimeConfigError("Custom container filter rules would be lost on restart; no changes made.")
    if policies != {"INPUT": "ACCEPT", "FORWARD": "ACCEPT", "OUTPUT": "ACCEPT"}:
        raise RuntimeConfigError("Custom container filter policies/chains require manual review before restart.")


def validate_namespace_rules(text, network, ipv6=False):
    """Only default policies and NAT reconstructed by the module/image are safe."""
    tables = {}
    current = None
    for line in text.splitlines():
        if not line or line.startswith("#"):
            continue
        if line.startswith("*"):
            current = line[1:]
            tables[current] = []
        elif line != "COMMIT" and current:
            tables[current].append(line)
    for table, lines in tables.items():
        if table == "filter":
            validate_filter_rules("\n".join(lines))
            continue
        defaults = {
            "raw": {"PREROUTING", "OUTPUT"},
            "mangle": {"PREROUTING", "INPUT", "FORWARD", "OUTPUT", "POSTROUTING"},
            "security": {"INPUT", "FORWARD", "OUTPUT"},
            "nat": {"PREROUTING", "INPUT", "OUTPUT", "POSTROUTING"},
        }
        if table not in defaults:
            raise RuntimeConfigError("Custom container firewall tables require manual review.")
        for line in lines:
            if line.startswith(":"):
                chain, policy = line[1:].split()[:2]
                if chain in defaults[table] and policy == "ACCEPT":
                    continue
                if not ipv6 and table == "nat" and chain in ("DOCKER_OUTPUT", "DOCKER_POSTROUTING") and policy == "-":
                    continue
            elif table == "nat" and not ipv6:
                if line == f"-A POSTROUTING -s {network} -o eth0 -j MASQUERADE":
                    continue
                if line in ("-A OUTPUT -d 127.0.0.11/32 -j DOCKER_OUTPUT",
                            "-A POSTROUTING -d 127.0.0.11/32 -j DOCKER_POSTROUTING"):
                    continue
                if re.fullmatch(r"-A DOCKER_OUTPUT -d 127\.0\.0\.11/32 -p (tcp|udp) -m \1 --dport 53 -j DNAT --to-destination 127\.0\.0\.11:[0-9]+", line):
                    continue
                if re.fullmatch(r"-A DOCKER_POSTROUTING -s 127\.0\.0\.11/32 -p (tcp|udp) -m \1 --sport [0-9]+ -j SNAT --to-source :53", line):
                    continue
            raise RuntimeConfigError("Custom container firewall/NAT rules would be lost on restart; no changes made.")


class DockerRuntime:
    def run(self, args, timeout=15):
        try:
            result = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
        except (OSError, subprocess.TimeoutExpired) as error:
            raise RuntimeConfigError(f"Command {args[0]} could not complete.") from error
        if result.returncode:
            # Never print command output: profile/configuration material could be sensitive.
            raise RuntimeConfigError(f"Command {args[0]} failed with exit code {result.returncode}.")
        return result.stdout

    def preflight(self, conf_dir, network):
        info = json.loads(self.run(["docker", "inspect", "openvpn"]))[0]
        if not info["State"]["Running"] or info["State"].get("Restarting"):
            raise RuntimeConfigError("OpenVPN is not running; refusing an automatic restart.")
        if info["Config"].get("Cmd") not in (["ovpn_run"], ["/usr/local/bin/ovpn_run"]):
            raise RuntimeConfigError("Custom container startup commands need manual review.")
        if info["Config"].get("Entrypoint") or info.get("HostConfig", {}).get("NetworkMode") in ("host", "none"):
            raise RuntimeConfigError("Custom entrypoints or network modes need manual review.")
        if not any(mount.get("Type") == "bind" and mount.get("Destination") == "/etc/openvpn"
                   and Path(mount["Source"]).resolve() == conf_dir.resolve() and mount.get("RW")
                   for mount in info.get("Mounts", [])):
            raise RuntimeConfigError("Expected the module's writable /etc/openvpn directory bind mount.")
        validate_namespace_rules(self.run(["docker", "exec", "openvpn", "iptables-save"]), network)
        ipv6 = self.run(["docker", "exec", "openvpn", "sh", "-c",
                         "if command -v ip6tables-save >/dev/null; then ip6tables-save; fi"])
        if ipv6.strip():
            validate_namespace_rules(ipv6, network, ipv6=True)

    def restart(self):
        self.run(["docker", "restart", "--time", "10", "openvpn"], timeout=60)

    def healthy(self, network):
        try:
            if self.run(["docker", "inspect", "-f", "{{.State.Running}}", "openvpn"]).strip() != "true":
                return False
            if self.run(["docker", "exec", "openvpn", "cat", "/proc/1/comm"]).strip() != "openvpn":
                return False
            addresses = self.run(["docker", "exec", "openvpn", "ip", "-4", "-o", "addr", "show", "dev", "tun0"])
            if f"inet {network.network_address + 1}/{network.prefixlen} " not in addresses:
                return False
            sockets = self.run(["docker", "exec", "openvpn", "cat", "/proc/net/udp"])
            return any(len(fields) > 1 and fields[1].endswith(":04AA")
                       for fields in (line.split() for line in sockets.splitlines()))
        except RuntimeConfigError:
            return False

    def wait_healthy(self, network, timeout=45):
        deadline = time.monotonic() + timeout
        consecutive = 0
        while time.monotonic() < deadline:
            consecutive = consecutive + 1 if self.healthy(network) else 0
            if consecutive >= 2:
                return
            time.sleep(1)
        raise RuntimeConfigError("OpenVPN did not become healthy after restart.")


def write_atomic(path, data, metadata):
    fd, name = tempfile.mkstemp(prefix=".runtime-config-", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            os.fchmod(stream.fileno(), stat.S_IMODE(metadata.st_mode))
            os.fchown(stream.fileno(), metadata.st_uid, metadata.st_gid)
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def apply_runtime_config(request, runtime=None):
    if request.get("config") is None:
        return {"changed": False, "reason": "Runtime management disabled."}
    conf_dir = Path(request["volume_path"]) / "conf"
    path = conf_dir / "openvpn.conf"
    if path.is_symlink() or not path.is_file():
        raise RuntimeConfigError("Expected a regular openvpn.conf file.")
    runtime = runtime or DockerRuntime()
    with (conf_dir / ".profile-sync.lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise RuntimeConfigError("Another profile/runtime sync is running; no changes made.") from error
        metadata = path.stat()
        original = path.read_bytes()
        candidate, network = build_candidate(original.decode(), request, conf_dir)
        if candidate.encode() == original:
            result = {"changed": False, "reason": "Managed configuration already matches; no restart."}
            print(json.dumps(result))
            return result
        runtime.preflight(conf_dir, network)
        backups = conf_dir / "runtime-config-backups"
        backups.mkdir(mode=0o700, exist_ok=True)
        if stat.S_IMODE(backups.stat().st_mode) & 0o077:
            raise RuntimeConfigError("Backup directory permissions must be 0700.")
        fd, backup_name = tempfile.mkstemp(prefix=datetime.datetime.now(datetime.timezone.utc).strftime("openvpn.conf.%Y%m%dT%H%M%SZ."), dir=backups)
        with os.fdopen(fd, "wb") as backup:
            backup.write(original)
            backup.flush()
            os.fsync(backup.fileno())
        if path.read_bytes() != original:
            raise RuntimeConfigError("Configuration changed during preflight; refusing to overwrite it.")
        write_atomic(path, candidate.encode(), metadata)
        try:
            runtime.restart()
            runtime.wait_healthy(network)
            if path.read_bytes() != candidate.encode():
                raise RuntimeConfigError("Configuration was changed externally during restart.")
        except Exception as error:
            if path.read_bytes() != candidate.encode():
                raise RuntimeConfigError(f"Configuration changed externally; refusing to overwrite it during rollback. Backup: {backup_name}. Manual review required.") from error
            write_atomic(path, original, metadata)
            try:
                runtime.restart()
                runtime.wait_healthy(network)
            except Exception as rollback_error:
                raise RuntimeConfigError(f"Restart and rollback health checks failed. Original config restored; backup: {backup_name}. Manual recovery required.") from rollback_error
            raise RuntimeConfigError(f"New configuration failed; original configuration restored and restarted. Backup: {backup_name}.") from error
        result = {"changed": True, "restarted": True, "backup": backup_name,
                  "dynamic_pool": request["config"].get("dynamic_pool"),
                  "receive_buffer_bytes": request["config"].get("receive_buffer_bytes")}
        print(json.dumps(result))
        return result
