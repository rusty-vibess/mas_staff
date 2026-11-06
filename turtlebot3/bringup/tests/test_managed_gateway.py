"""Exercise route ownership, handover and network discovery without changing routes."""

import ipaddress
import json
import subprocess
import uuid

import pytest

from workspace.services.managed_gateway import LEASE_SECONDS, RouteManager


@pytest.fixture
def registry():
    clock = [0]
    commands = []
    def command(*args):
        commands.append(args)
        return "[]"
    return RouteManager([ipaddress.IPv4Network("10.20.0.0/24")], 98,
                  command=command, clock=lambda: clock[0]), clock, commands


def message(owner, network="172.23.0.0/24", action="renew"):
    return {"protocol": "pgta-route-v1", "domain": 98, "owner": owner,
            "network": network, "action": action}


def test_registration_uses_actual_sender_and_renews_without_replacing_route(registry):
    routes, clock, commands = registry
    request = message(str(uuid.uuid4()))
    assert routes.request(request, "10.20.0.42")["status"] == "accepted"
    assert commands[-1] == ("route", "add", "172.23.0.0/24", "via", "10.20.0.42", "proto", "static")
    count = len(commands)
    clock[0] += 3
    routes.request(request, "10.20.0.42")
    assert len(commands) == count
    clock[0] = LEASE_SECONDS + 1
    routes.expire()
    assert routes.leases
    clock[0] += 3
    routes.expire()
    assert not routes.leases


@pytest.mark.parametrize("second_network", ["172.23.0.0/24", "172.23.0.2/32", "172.23.0.0/16"])
def test_overlap_is_busy_until_release_then_handover(registry, second_network):
    routes, clock, commands = registry
    first, second = str(uuid.uuid4()), str(uuid.uuid4())
    routes.request(message(first), "10.20.0.42")
    assert routes.request(message(second, second_network), "10.20.0.43")["status"] == "busy"
    routes.request(message(first, action="release"), "10.20.0.42")
    assert routes.request(message(second, second_network), "10.20.0.43")["status"] == "accepted"
    assert routes.leases[second_network]["gateway"] == "10.20.0.43"


def test_crash_expiry_allows_next_station_without_restart(registry):
    routes, clock, commands = registry
    routes.request(message(str(uuid.uuid4())), "10.20.0.42")
    clock[0] = LEASE_SECONDS + 1
    assert routes.request(message(str(uuid.uuid4())), "10.20.0.43")["status"] == "accepted"
    assert any(command[:2] == ("route", "del") for command in commands)


@pytest.mark.parametrize("remaining_route", [[], [{"dst": "172.23.0.0/24"}]])
def test_expiry_handles_route_already_removed(registry, remaining_route):
    routes, clock, commands = registry
    routes.request(message(str(uuid.uuid4())), "10.20.0.42")
    clock[0] = LEASE_SECONDS + 1

    def command(*args):
        if args[:2] == ("route", "del"):
            raise subprocess.CalledProcessError(2, args)

        return json.dumps(remaining_route)

    routes.command = command
    if remaining_route:
        with pytest.raises(subprocess.CalledProcessError):
            routes.expire()

        assert routes.leases
    else:
        routes.expire()
        assert not routes.leases


@pytest.mark.parametrize("announcement,source", [
    ([], "10.20.0.42"),
    (message(str(uuid.uuid4()), "0.0.0.0/0"), "10.20.0.42"),
    (message(str(uuid.uuid4()), "8.8.8.0/24"), "10.20.0.42"),
    (message(str(uuid.uuid4()), "10.20.0.0/24"), "10.20.0.42"),
    (message(str(uuid.uuid4())), "10.30.0.42"),
    ({**message(str(uuid.uuid4())), "domain": 99}, "10.20.0.42"),
])
def test_invalid_announcements_never_modify_routes(registry, announcement, source):
    routes, clock, commands = registry
    with pytest.raises(ValueError):
        routes.request(announcement, source)
    assert commands == []


def test_unmanaged_route_is_preserved(registry):
    routes, clock, commands = registry
    routes.command = lambda *args: json.dumps([{"dst": "172.23.0.0/24"}])
    with pytest.raises(ValueError, match="unmanaged"):
        routes.request(message(str(uuid.uuid4())), "10.20.0.42")
    assert not routes.leases
