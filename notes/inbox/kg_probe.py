#!/usr/bin/env python3
"""Probe a kernel-graph sqlite DB (read-only)."""
import sqlite3
import sys

db = sys.argv[1]
con = sqlite3.connect("file:%s?mode=ro" % db, uri=True)
cur = con.cursor()

tables = [r[0] for r in cur.execute("SELECT name FROM sqlite_master WHERE type='table'")]
print("TABLES:", tables)

def q(sql, params=()):
    try:
        return cur.execute(sql, params).fetchall()
    except sqlite3.Error as e:
        return [("ERR", str(e))]

# counts
for t in tables:
    n = q("SELECT COUNT(*) FROM %s" % t)
    print("  count %-12s = %s" % (t, n[0] if n and n[0] != "ERR" else n))

if "functions" in tables:
    print("\nrt.c functions:")
    for r in q("SELECT name, file, line FROM functions WHERE file LIKE '%rt.c' ORDER BY line LIMIT 60"):
        print("  ", r)

    print("\nfind enqueue_task_rt:")
    for r in q("SELECT name, file, line FROM functions WHERE name IN ('enqueue_task_rt','enqueue_rt_entity','__enqueue_rt_entity','dequeue_rt_entity','__dequeue_rt_entity')"):
        print("  ", r)

if "structs" in tables:
    print("\nrt_prio_array struct fields:")
    for r in q("SELECT field, type, file, line FROM structs WHERE struct_name='rt_prio_array' ORDER BY line"):
        print("  ", r)

con.close()
