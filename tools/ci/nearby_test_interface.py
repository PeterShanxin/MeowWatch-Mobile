"""Select a real CI adapter for same-host TLS tests, never product network policy."""

import ipaddress
import json
import os
from pathlib import Path
import subprocess


def main() -> None:
    private_ranges = tuple(map(ipaddress.ip_network, (
        "10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "169.254.0.0/16",
    )))
    adapters = json.loads(subprocess.check_output(
        ["ip", "-json", "-4", "address", "show", "up"], text=True,
    ))
    for adapter in adapters:
        if "LOOPBACK" in adapter.get("flags", []):
            continue
        for value in adapter.get("addr_info", []):
            address = ipaddress.IPv4Address(value["local"])
            prefix = value["prefixlen"]
            if not 1 <= prefix <= 30 or not any(address in net for net in private_ranges):
                continue
            network = ipaddress.ip_network(f"{address}/{prefix}", strict=False)
            if address in (network.network_address, network.broadcast_address):
                continue
            with Path(os.environ["GITHUB_ENV"]).open("a", encoding="utf-8") as output:
                output.write(f"NEARBY_TEST_ADDRESS={address}\nNEARBY_TEST_PREFIX={prefix}\n")
            print("Actual private adapter selected for same-host TLS tests.")
            return
    raise SystemExit("No private IPv4 adapter: refusing to silently skip Nearby TLS tests.")


if __name__ == "__main__":
    main()
