#!/bin/bash
# The Wazuh agent's Docker listener needs the Python Docker library. Ubuntu blocks system-wide
# pip (PEP 668), so it goes in a venv and DockerListener's shebang points at it, as Wazuh's docs
# describe: https://documentation.wazuh.com/current/user-manual/capabilities/container-security/monitoring-docker.html
#   sudo server/provision/docker-listener.sh
#
# An agent upgrade rewrites DockerListener with the plain python3 shebang, so run this again
# after every upgrade. bootstrap.sh runs it on a new server. Safe to re-run; it restarts the
# agent only when the shebang changed and the agent is running.
set -euo pipefail

venv=/opt/wazuh-docker-venv
listener=/var/ossec/wodles/docker/DockerListener
req="$(cd "$(dirname "$0")" && pwd)/docker-listener-requirements.txt"

if [ "$(id -u)" -ne 0 ]; then
  echo "run as root (sudo)" >&2
  exit 1
fi
if [ ! -f "$listener" ]; then
  echo "$listener not found: install the Wazuh agent first" >&2
  exit 1
fi

if ! dpkg-query -W -f='${Status}' python3-venv 2>/dev/null | grep -q 'ok installed'; then
  apt-get install -y -q python3-venv
fi
if [ ! -x "$venv/bin/python3" ]; then
  python3 -m venv "$venv"
fi
# Every package is pinned by hash, so a changed or swapped file fails the install
"$venv/bin/pip" install -q --disable-pip-version-check --no-deps --require-hashes -r "$req"
"$venv/bin/python3" -c 'import docker'

shebang="#!$venv/bin/python3"
if [ "$(head -n 1 "$listener")" != "$shebang" ]; then
  sed -i "1s|.*|$shebang|" "$listener"
  echo "DockerListener now runs $venv/bin/python3"
  # The listener starts listening about 60 s after the agent starts
  systemctl try-restart wazuh-agent
fi
