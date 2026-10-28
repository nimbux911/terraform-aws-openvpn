#!/bin/bash
set -euo pipefail
umask 077

python3 - <<'PY_OPENVPN_RUNTIME'
${runtime_script}

if __name__ == "__main__":
    try:
        apply_runtime_config(json.loads(${jsonencode(jsonencode(request))}))
    except (RuntimeConfigError, ValueError, OSError) as error:
        import sys
        print("OpenVPN runtime configuration failed: " + str(error), file=sys.stderr)
        sys.exit(1)
PY_OPENVPN_RUNTIME
