"""Check detail isolation without discarding details from current failures."""

import json


def check(output):
    results = {tuple(r["path"]): r for r in map(json.loads, output.splitlines())}
    assert len(results) == 8
    for name, message in [
        ("first_failure", "first failure"),
        ("after_ignore", "after ignore"),
        ("TEAR_DOWN_SUITE", "Suite tear-down failed: teardown failure"),
    ]:
        r = results["tests", name]
        assert r["status"] == "failed", r
        assert r["message"] == message, r
    for name, status, markers in [
        ("own_failure", "failed", ("own first", "own second", "own failure")),
        ("own_ignore", "skipped", ("own ignore",)),
    ]:
        r = results["tests", name]
        assert r["status"] == status, r
        assert all(m in r["message"] for m in markers), r
    assert results["tests", "last_test"]["status"] == "passed"
    r = results["failed_setup", "not_run"]
    assert r["status"] == "failed", r
    assert all(m in r["message"] for m in ("setup first", "setup second")), r
    r = results["next_setup", "not_run"]
    assert r["status"] == "failed", r
    assert r["message"] == "Suite set-up failed: next setup failure", r
