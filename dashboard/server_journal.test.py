#!/usr/bin/env python3
import importlib.util
from pathlib import Path


def load_server_module():
    server_path = Path(__file__).with_name("server.py")
    spec = importlib.util.spec_from_file_location("dashboard_server", server_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_parse_journal_returns_all_entries_newest_first_when_file_is_not_ordered():
    server = load_server_module()
    text = "\n\n".join(
        f"""## 2026-07-{day:02d}

**学习内容**：
- entry {day}
"""
        for day in range(1, 13)
    )

    entries = server.parse_journal(text)

    assert [entry["date"] for entry in entries] == [
        "2026-07-12",
        "2026-07-11",
        "2026-07-10",
        "2026-07-09",
        "2026-07-08",
        "2026-07-07",
        "2026-07-06",
        "2026-07-05",
        "2026-07-04",
        "2026-07-03",
        "2026-07-02",
        "2026-07-01",
    ]


if __name__ == "__main__":
    test_parse_journal_returns_all_entries_newest_first_when_file_is_not_ordered()
    print("server journal tests ok")
