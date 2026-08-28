#!/usr/bin/env python3
import http.client
import importlib.util
import json
import socket
import tempfile
import threading
from pathlib import Path


def load_server_module():
    server_path = Path(__file__).with_name("server.py")
    spec = importlib.util.spec_from_file_location("dashboard_server", server_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_save_quick_note_creates_daily_file_and_appends_entries():
    server = load_server_module()
    with tempfile.TemporaryDirectory() as tmpdir:
        server.NOTES_INBOX_DIR = Path(tmpdir)

        first = server.save_quick_note(
            {"type": "问题", "content": "first note", "source": "test"},
            now=server.datetime(2026, 8, 8, 9, 5),
        )
        second = server.save_quick_note(
            {"type": "待整理", "content": "second note", "source": "test"},
            now=server.datetime(2026, 8, 8, 10, 30),
        )

        daily_file = Path(tmpdir) / "2026-08-08.md"
        assert first == {"ok": True, "path": "notes/inbox/2026-08-08.md"}
        assert second == {"ok": True, "path": "notes/inbox/2026-08-08.md"}
        assert daily_file.read_text(encoding="utf-8") == (
            "### 09:05 问题\n\n"
            "- 来源：test\n"
            "- 状态：inbox\n\n"
            "first note\n\n"
            "### 10:30 待整理\n\n"
            "- 来源：test\n"
            "- 状态：inbox\n\n"
            "second note\n\n"
        )


def test_save_quick_note_rejects_empty_content():
    server = load_server_module()
    with tempfile.TemporaryDirectory() as tmpdir:
        server.NOTES_INBOX_DIR = Path(tmpdir)

        try:
            server.save_quick_note(
                {"type": "笔记", "content": "  \n\t  ", "source": "test"},
                now=server.datetime(2026, 8, 8, 11, 0),
            )
        except ValueError as exc:
            assert str(exc) == "随时记内容为空"
        else:
            raise AssertionError("expected ValueError")

        assert Path(tmpdir).exists()
        assert not (Path(tmpdir) / "2026-08-08.md").exists()


def test_save_quick_note_normalizes_type_and_source():
    server = load_server_module()
    with tempfile.TemporaryDirectory() as tmpdir:
        server.NOTES_INBOX_DIR = Path(tmpdir)

        server.save_quick_note(
            {"type": "unknown", "content": "needs sorting", "source": "   "},
            now=server.datetime(2026, 8, 8, 12, 45),
        )

        daily_file = Path(tmpdir) / "2026-08-08.md"
        assert daily_file.read_text(encoding="utf-8") == (
            "### 12:45 笔记\n\n"
            "- 来源：dashboard\n"
            "- 状态：inbox\n\n"
            "needs sorting\n\n"
        )


def test_load_quick_notes_parses_files_and_sorts_newest_first():
    server = load_server_module()
    with tempfile.TemporaryDirectory() as tmpdir:
        server.NOTES_INBOX_DIR = Path(tmpdir)
        Path(tmpdir, "2026-08-07.md").write_text(
            "### 09:10 问题\n\n"
            "- 来源：overview\n"
            "- 状态：inbox\n\n"
            "older question\n\n",
            encoding="utf-8",
        )
        Path(tmpdir, "2026-08-08.md").write_text(
            "### 15:39 笔记\n\n"
            "- 来源：graph\n"
            "- 状态：inbox\n\n"
            "newer note\n"
            "second line\n\n"
            "### 15:40 待整理\n\n"
            "- 来源：docs · sched/cfs_rq.md\n"
            "- 状态：inbox\n\n"
            "latest item\n\n",
            encoding="utf-8",
        )

        data = server.load_quick_notes()

        assert data["counts"] == {"total": 3, "问题": 1, "笔记": 1, "待整理": 1}
        assert [n["content"] for n in data["notes"]] == [
            "latest item",
            "newer note\nsecond line",
            "older question",
        ]
        assert data["notes"][0]["date"] == "2026-08-08"
        assert data["notes"][0]["time"] == "15:40"
        assert data["notes"][0]["type"] == "待整理"
        assert data["notes"][0]["source"] == "docs · sched/cfs_rq.md"
        assert data["notes"][0]["status"] == "inbox"
        assert data["notes"][0]["file"] == "notes/inbox/2026-08-08.md"


def test_load_quick_notes_sorts_same_minute_blocks_by_file_order_descending():
    server = load_server_module()
    with tempfile.TemporaryDirectory() as tmpdir:
        server.NOTES_INBOX_DIR = Path(tmpdir)
        blocks = []
        for index in range(12):
            blocks.append(
                "### 15:39 笔记\n\n"
                "- 来源：same-minute\n"
                "- 状态：inbox\n\n"
                f"same minute note {index}\n\n"
            )
        Path(tmpdir, "2026-08-08.md").write_text("".join(blocks), encoding="utf-8")

        data = server.load_quick_notes()

        assert [note["content"] for note in data["notes"][:3]] == [
            "same minute note 11",
            "same minute note 10",
            "same minute note 9",
        ]
        assert "_order" not in data["notes"][0]


def test_load_quick_notes_missing_inbox_returns_empty_data():
    server = load_server_module()
    with tempfile.TemporaryDirectory() as tmpdir:
        server.NOTES_INBOX_DIR = Path(tmpdir) / "missing"

        data = server.load_quick_notes()

        assert data == {
            "notes": [],
            "counts": {"total": 0, "问题": 0, "笔记": 0, "待整理": 0},
        }


def test_decode_json_body_rejects_invalid_json():
    server = load_server_module()
    try:
        server.decode_json_body(b"{not-json")
    except ValueError as exc:
        assert str(exc) == "请求体不是合法 JSON"
    else:
        raise AssertionError("expected ValueError")


def test_decode_json_body_decodes_object_json():
    server = load_server_module()
    assert server.decode_json_body(b'{"content":"x"}') == {"content": "x"}


def test_decode_json_body_rejects_non_object_json():
    server = load_server_module()
    try:
        server.decode_json_body(b"[]")
    except ValueError as exc:
        assert str(exc) == "请求体不是合法 JSON"
    else:
        raise AssertionError("expected ValueError")


def run_test_server(server, inbox_dir):
    server.NOTES_INBOX_DIR = Path(inbox_dir)
    httpd = server.ThreadingHTTPServer(("127.0.0.1", 0), server.Handler)
    thread = threading.Thread(target=httpd.serve_forever)
    thread.start()
    return httpd, thread


def stop_test_server(httpd, thread):
    httpd.shutdown()
    httpd.server_close()
    thread.join(timeout=2)


def post_json(port, path, raw_body):
    conn = http.client.HTTPConnection("127.0.0.1", port, timeout=2)
    try:
        conn.request(
            "POST",
            path,
            body=raw_body,
            headers={"Content-Type": "application/json"},
        )
        response = conn.getresponse()
        body = response.read()
        payload = json.loads(body.decode("utf-8")) if body else None
        return response.status, payload
    finally:
        conn.close()


def get_json(port, path):
    conn = http.client.HTTPConnection("127.0.0.1", port, timeout=2)
    try:
        conn.request("GET", path)
        response = conn.getresponse()
        body = response.read()
        payload = json.loads(body.decode("utf-8")) if body else None
        return response.status, payload
    finally:
        conn.close()


def post_raw(port, path, headers="", body=b""):
    with socket.create_connection(("127.0.0.1", port), timeout=2) as sock:
        request = (
            f"POST {path} HTTP/1.1\r\n"
            f"Host: 127.0.0.1:{port}\r\n"
            f"{headers}"
            "\r\n"
        ).encode("utf-8") + body
        sock.sendall(request)
        sock.shutdown(socket.SHUT_WR)
        chunks = []
        while True:
            chunk = sock.recv(4096)
            if not chunk:
                break
            chunks.append(chunk)

    raw_response = b"".join(chunks)
    raw_headers, _, raw_body = raw_response.partition(b"\r\n\r\n")
    status_line = raw_headers.splitlines()[0].decode("iso-8859-1")
    return status_line, raw_body.decode("utf-8")


def test_quick_notes_handler_success_writes_note_to_temp_inbox():
    server = load_server_module()
    with tempfile.TemporaryDirectory() as tmpdir:
        httpd, thread = run_test_server(server, tmpdir)
        try:
            status, payload = post_json(
                httpd.server_port,
                "/api/quick-notes",
                json.dumps({
                    "type": "问题",
                    "content": "handler note",
                    "source": "handler-test",
                }).encode("utf-8"),
            )
        finally:
            stop_test_server(httpd, thread)

        assert status == 200
        assert payload["ok"] is True
        assert payload["path"].startswith("notes/inbox/")
        assert payload["path"].endswith(".md")

        files = list(Path(tmpdir).glob("*.md"))
        assert len(files) == 1
        content = files[0].read_text(encoding="utf-8")
        assert "问题" in content
        assert "handler note" in content
        assert "handler-test" in content


def test_quick_notes_handler_rejects_invalid_json():
    server = load_server_module()
    with tempfile.TemporaryDirectory() as tmpdir:
        httpd, thread = run_test_server(server, tmpdir)
        try:
            status, payload = post_json(
                httpd.server_port,
                "/api/quick-notes",
                b"{not-json",
            )
        finally:
            stop_test_server(httpd, thread)

        assert status == 400
        assert payload == {"error": "请求体不是合法 JSON"}


def test_quick_notes_handler_rejects_empty_content():
    server = load_server_module()
    with tempfile.TemporaryDirectory() as tmpdir:
        httpd, thread = run_test_server(server, tmpdir)
        try:
            status, payload = post_json(
                httpd.server_port,
                "/api/quick-notes",
                b'{"content":"  "}',
            )
        finally:
            stop_test_server(httpd, thread)

        assert status == 400
        assert payload == {"error": "随时记内容为空"}


def test_unknown_post_path_returns_404_before_reading_malformed_length():
    server = load_server_module()
    with tempfile.TemporaryDirectory() as tmpdir:
        httpd, thread = run_test_server(server, tmpdir)
        try:
            status_line, _ = post_raw(
                httpd.server_port,
                "/api/not-found",
                headers="Content-Length: invalid\r\n",
            )
        finally:
            stop_test_server(httpd, thread)

        assert status_line.startswith("HTTP/1.0 404 ")


def test_known_post_path_rejects_malformed_content_length():
    server = load_server_module()
    with tempfile.TemporaryDirectory() as tmpdir:
        httpd, thread = run_test_server(server, tmpdir)
        try:
            status_line, body = post_raw(
                httpd.server_port,
                "/api/quick-notes",
                headers="Content-Length: invalid\r\n",
            )
        finally:
            stop_test_server(httpd, thread)

        assert status_line.startswith("HTTP/1.0 400 ")
        assert "请求体长度无效" in body


def test_quick_notes_get_handler_returns_notes_and_counts():
    server = load_server_module()
    with tempfile.TemporaryDirectory() as tmpdir:
        inbox_dir = Path(tmpdir)
        inbox_dir.mkdir(parents=True, exist_ok=True)
        (inbox_dir / "2026-08-08.md").write_text(
            "### 10:11 问题\n\n"
            "- 来源：docs\n"
            "- 状态：inbox\n\n"
            "api question\n\n",
            encoding="utf-8",
        )
        httpd, thread = run_test_server(server, inbox_dir)
        try:
            status, payload = get_json(httpd.server_port, "/api/quick-notes")
        finally:
            stop_test_server(httpd, thread)

        assert status == 200
        assert payload["counts"] == {"total": 1, "问题": 1, "笔记": 0, "待整理": 0}
        assert len(payload["notes"]) == 1
        assert payload["notes"][0]["content"] == "api question"
        assert payload["notes"][0]["source"] == "docs"


def test_manual_chain_handler_rejects_invalid_json():
    server = load_server_module()
    with tempfile.TemporaryDirectory() as tmpdir:
        httpd, thread = run_test_server(server, tmpdir)
        try:
            status, payload = post_json(
                httpd.server_port,
                "/api/manual-chain",
                b"{not-json",
            )
        finally:
            stop_test_server(httpd, thread)

        assert status == 400
        assert payload == {"error": "请求体不是合法 JSON"}


def test_manual_chain_handler_rejects_empty_text():
    server = load_server_module()
    with tempfile.TemporaryDirectory() as tmpdir:
        httpd, thread = run_test_server(server, tmpdir)
        try:
            status, payload = post_json(
                httpd.server_port,
                "/api/manual-chain",
                b'{"text":"  ","title":"empty"}',
            )
        finally:
            stop_test_server(httpd, thread)

        assert status == 400
        assert payload == {"error": "粘贴内容为空"}


if __name__ == "__main__":
    test_save_quick_note_creates_daily_file_and_appends_entries()
    test_save_quick_note_rejects_empty_content()
    test_save_quick_note_normalizes_type_and_source()
    test_load_quick_notes_parses_files_and_sorts_newest_first()
    test_load_quick_notes_sorts_same_minute_blocks_by_file_order_descending()
    test_load_quick_notes_missing_inbox_returns_empty_data()
    test_decode_json_body_rejects_invalid_json()
    test_decode_json_body_decodes_object_json()
    test_decode_json_body_rejects_non_object_json()
    test_quick_notes_handler_success_writes_note_to_temp_inbox()
    test_quick_notes_handler_rejects_invalid_json()
    test_quick_notes_handler_rejects_empty_content()
    test_unknown_post_path_returns_404_before_reading_malformed_length()
    test_known_post_path_rejects_malformed_content_length()
    test_quick_notes_get_handler_returns_notes_and_counts()
    test_manual_chain_handler_rejects_invalid_json()
    test_manual_chain_handler_rejects_empty_text()
    print("quick notes backend tests ok")
