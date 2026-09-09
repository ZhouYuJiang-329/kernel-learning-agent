#!/usr/bin/env python3
"""Query the kernel-graph DB reusing mcp_server.py's exact dispatch logic.

Usage:
    python kg_query.py <db> <tool> [key=value ...]

Example:
    python kg_query.py linux7.2rc6.db find_callers function=enqueue_task_rt limit=30
    python kg_query.py linux7.2rc6.db get_code_snippet symbol=enqueue_task_rt
"""
import sqlite3
import sys

KG_DIR = r"D:\claude配置\kernel-graph"
sys.path.insert(0, KG_DIR)

import mcp_server  # noqa: E402

INT_KEYS = {"limit", "depth", "line", "max_lines", "max_depth"}


def main() -> None:
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(2)
    db_path = sys.argv[1]
    tool = sys.argv[2]
    args: dict = {}
    for kv in sys.argv[3:]:
        k, _, v = kv.partition("=")
        args[k] = int(v) if k in INT_KEYS else v

    mcp_server._db = sqlite3.connect(db_path, check_same_thread=False)
    result = mcp_server._dispatch(tool, args)
    print(mcp_server._fmt(result))


if __name__ == "__main__":
    main()
