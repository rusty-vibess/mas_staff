"""Manage leased routes to private networks behind a remote."""

import ipaddress
import json
import os
import signal
import socket
import subprocess
import time
import uuid

PORT = 45888
LEASE_SECONDS = 10


def ip(*args):
    return subprocess.check_output(["ip", *args], text=True)


class RouteManager:
    """
    Help a TurtleBot send packets to ROS running behind another device.

    Some network setups put ROS on a private subnet that the TurtleBot
    cannot reach directly. The remote device identifies that subnet and
    registers itself as the gateway, so the TurtleBot sends packets through
    the remote's local network address.
    
    The remote must forward those packets to the subnet. Ensure remote uses
    appropriate service.

    The gateway sends UDP announcements to keep the route active. The route
    is removed when the gateway releases it or stops sending announcements.

    Tested with Fast DDS; other ROS middleware has not been verified.
    """

    def __init__(self, networks, domain, command=ip, clock=time.monotonic):
        self.networks = networks
        self.domain = domain
        self.command = command
        self.clock = clock
        self.leases = {}

    def remove(self, network):
        """Remove a managed route and its lease."""
        lease = self.leases[network]
        try:
            self.command("route", "del", network, "via", lease["gateway"], "proto", "static")
        except subprocess.CalledProcessError:
            # discard the lease if the route was already removed
            if json.loads(self.command("-j", "route", "show", "to", "exact", network)):
                raise

        del self.leases[network]

    def expire(self):
        """Remove routes whose leases have expired."""
        for network, lease in list(self.leases.items()):
            if lease["until"] <= self.clock():
                self.remove(network)

    def request(self, message, source):
        """Renew or release a route requested by a remote."""
        self.expire()

        # validate the request and the remote's directly connected address
        if (
            not isinstance(message, dict)
            or message.get("protocol") != "pgta-route-v1"
            or message.get("domain") != self.domain
        ):
            raise ValueError("Different route protocol or ROS domain")

        if not isinstance(message.get("owner"), str) or not isinstance(
            message.get("network"), str
        ):
            raise ValueError("Expected remote identity and VM subnet strings")

        owner = str(uuid.UUID(message["owner"]))
        subnet = ipaddress.IPv4Network(message["network"], strict=True)
        gateway = ipaddress.IPv4Address(source)
        private = (
            ipaddress.IPv4Network(prefix)
            for prefix in ("10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16")
        )
        if subnet.prefixlen < 16 or not any(subnet.subnet_of(prefix) for prefix in private):
            raise ValueError("Expected a private VM subnet")

        if not any(gateway in network for network in self.networks):
            raise ValueError("Remote must be on a directly connected network")

        if any(subnet.overlaps(network) for network in self.networks):
            raise ValueError("VM subnet overlaps a robot network")

        action = message["action"]
        if action not in ("renew", "release"):
            raise ValueError("Unknown route action")

        network = str(subnet)
        current = self.leases.get(network)

        # refuse overlapping leases held by another remote
        if any(
            ipaddress.IPv4Network(prefix).overlaps(subnet) and lease["owner"] != owner
            for prefix, lease in self.leases.items()
        ):
            return {"status": "busy", "domain": self.domain}

        if action == "release":
            if current:
                self.remove(network)

            return {"status": "released", "domain": self.domain}

        # preserve unmanaged routes and update a lease only after the route succeeds
        if not current:
            if json.loads(self.command("-j", "route", "show", "to", "exact", network)):
                raise ValueError("An unmanaged route already exists for this VM subnet")

            self.command("route", "add", network, "via", str(gateway), "proto", "static")
        elif current["gateway"] != str(gateway):
            self.command("route", "replace", network, "via", str(gateway), "proto", "static")

        self.leases[network] = {
            "owner": owner,
            "gateway": str(gateway),
            "until": self.clock() + LEASE_SECONDS,
        }

        return {"status": "accepted", "domain": self.domain}


class RouteClient:
    """Request and release a route from a robot."""

    def __init__(self, network, domain):
        self.network = str(network)
        self.domain = domain
        self.owner = str(uuid.uuid4())
        self.server = None
        self.socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.socket.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        self.socket.settimeout(1)

    def request(self, target, action="renew"):
        """Send a request and return the responding robot's address."""
        message = {
            "protocol": "pgta-route-v1",
            "domain": self.domain,
            "network": self.network,
            "owner": self.owner,
            "action": action,
        }
        self.socket.sendto(json.dumps(message).encode(), (target, PORT))
        response, sender = self.socket.recvfrom(2048)
        reply = json.loads(response)
        if not isinstance(reply, dict) or reply.get("domain") != self.domain:
            raise ValueError("Reply came from another ROS domain")

        if reply.get("status") == "busy":
            raise RuntimeError("Another remote owns this VM subnet; stop it or wait for its lease")

        if reply.get("status") not in ("accepted", "released"):
            raise RuntimeError(reply.get("error", "Route registration failed"))

        self.server = sender[0]

        return self.server

    def discover(self, targets):
        """Find a robot that accepts the route request."""
        deadline = time.monotonic() + 20
        while time.monotonic() < deadline:
            for target in targets:
                try:
                    return self.request(target)
                except (socket.timeout, ValueError):
                    continue

        raise RuntimeError(
            "No robot route service replied; start robot bringup and check the firewall"
        )

    def close(self):
        """Release the route and close the socket."""
        try:
            if self.server:
                self.request(self.server, "release")
        except (OSError, ValueError, RuntimeError):
            pass
        finally:
            self.socket.close()


def main():
    """Serve route requests until shutdown."""
    addresses = json.loads(ip("-j", "-4", "address", "show"))
    networks = [
        ipaddress.IPv4Interface(f"{a['local']}/{a['prefixlen']}").network
        for item in addresses
        for a in item["addr_info"]
    ]

    routes = RouteManager(networks, int(os.environ.get("ROS_DOMAIN_ID", "0")))
    running = True

    def stop(*_):
        nonlocal running
        running = False

    signal.signal(signal.SIGINT, stop)
    signal.signal(signal.SIGTERM, stop)

    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.bind(("0.0.0.0", PORT))
        sock.settimeout(0.5)
        print("Route registration ready", flush=True)
        try:
            while running:
                routes.expire()
                try:
                    data, source = sock.recvfrom(2048)
                except socket.timeout:
                    continue

                try:
                    reply = routes.request(json.loads(data), source[0])
                except (ValueError, KeyError, TypeError, subprocess.CalledProcessError) as error:
                    reply = {"status": "invalid", "domain": routes.domain, "error": str(error)}

                sock.sendto(json.dumps(reply).encode(), source)
        finally:
            for network in list(routes.leases):
                routes.remove(network)


if __name__ == "__main__":
    main()
