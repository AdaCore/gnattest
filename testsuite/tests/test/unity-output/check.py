"""Check decoded JSON values, including bytes after embedded NULs."""

import json


def check(output):
    records = [json.loads(line) for line in output.splitlines()]
    assert len(records) == 14
    results = {record["path"][1]: record for record in records}
    expected = {
        "nul_bytes": "\0before\0\0after\0",
        "nul_only": "\0",
        "mixed_output": "info \\x00 \\x41 é\nbefore\0after\n",
        "literal_info": r"\x00after" + "\n",
        "plain_output": "plain é\n",
        "incomplete_utf8": "Ã\0â\u0082",
        "info_only": "info\n",
        "control_info": r"byte: \x01" + "\n",
        "invalid_info": "byte: Ã\n",
    }
    for name, value in expected.items():
        assert results[name]["stdout"] == value, (name, results[name])
    assert results["literal_failure"]["message"] == (
        r"literal \x00after \x41 \xC3 \n \r \\" + " é"
    ), results["literal_failure"]
    assert results["literal_failure"]["status"] == "failed"
    assert results["literal_failure"]["failure_at"]["file"] == "path\\to\\test-é.c"
    assert results["literal_skip"]["message"] == r"\x41after"
    assert results["literal_skip"]["status"] == "skipped"
    assert r"\x00" in results["compared_nul"]["message"]
    assert "stdout" not in results["empty_output"]
    assert r"\xC3\xA9" in results["bounded_failure"]["message"]
