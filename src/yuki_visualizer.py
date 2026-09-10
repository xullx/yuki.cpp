import argparse
import json
import os
import socket
import subprocess
import threading
import time
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

TWITCH_SCRIPT = r"C:\Yuki\src\yuki_twitch.py"
TWITCH_LOG = r"C:\Yuki\logs\twitch-out.log"
STATUS_CACHE_SECONDS = 2.0
_status_cache = None
_status_cache_time = 0.0
_status_lock = threading.Lock()

_activity_state = {
    "brain_processing": False,
    "voice_level": 0.0,
}
_activity_lock = threading.Lock()

_transcript_messages = []
_transcript_last_id = int(time.time() * 1000)
_transcript_lock = threading.Lock()

_explorer_state = {
    "revision": 0,
    "action": "hide",
    "view": "projects",
    "title": "Projects",
    "caption": "Provided by YUKI",
    "items": [],
}
_explorer_lock = threading.Lock()

_UI_LAYOUT_LIMITS = {
    "durationMs": (0.0, 2500.0),
    "butterflyX": (10.0, 90.0),
    "butterflyY": (10.0, 90.0),
    "butterflyScale": (0.25, 1.0),
    "explorerX": (10.0, 90.0),
    "explorerY": (10.0, 90.0),
}

_ui_state = {
    "revision": 0,
    "layout": {
        "durationMs": 700,
        "butterflyX": 28.0,
        "butterflyY": 48.0,
        "butterflyScale": 0.65,
        "explorerX": 73.0,
        "explorerY": 48.0,
    },
}
_ui_state_lock = threading.Lock()

def add_transcript_message(payload: dict) -> dict:
    global _transcript_last_id

    source = str(
        payload.get("source", "system")
    ).strip().lower()

    if source not in {"twitch", "brain", "system"}:
        source = "system"

    text = str(
        payload.get("text", "")
    ).strip()

    if not text:
        raise ValueError("Transcript text is empty.")

    author = str(
        payload.get("author", "")
    ).strip()

    if not author:
        author = (
            "YUKI"
            if source == "brain"
            else "Viewer"
            if source == "twitch"
            else "System"
        )

    author = author[:64]
    text = text[:2000]

    with _transcript_lock:
        now_id = int(time.time() * 1000)

        _transcript_last_id = max(
            _transcript_last_id + 1,
            now_id,
        )

        item = {
            "id": _transcript_last_id,
            "source": source,
            "author": author,
            "text": text,
        }

        _transcript_messages.append(item)

        if len(_transcript_messages) > 50:
            del _transcript_messages[:-50]

        return dict(item)


def read_transcript() -> dict:
    with _transcript_lock:
        return {
            "messages": [
                dict(item)
                for item in _transcript_messages
            ]
        }

def read_explorer() -> dict:
    with _explorer_lock:
        return {
            "revision": int(
                _explorer_state["revision"]
            ),
            "action": str(
                _explorer_state["action"]
            ),
            "view": str(
                _explorer_state["view"]
            ),
            "title": str(
                _explorer_state["title"]
            ),
            "caption": str(
                _explorer_state["caption"]
            ),
            "items": [
                dict(item)
                for item in _explorer_state["items"]
            ],
        }


def set_explorer(payload: dict) -> dict:
    action = str(
        payload.get("action", "show")
    ).strip().lower()

    if action not in {
        "show",
        "hide",
    }:
        raise ValueError(
            "Explorer action must be show or hide."
        )

    view = str(
        payload.get("view", "projects")
    ).strip().lower()

    if view not in {
        "projects",
        "files",
    }:
        raise ValueError(
            "Explorer view must be projects or files."
        )

    title = str(
        payload.get(
            "title",
            "Files"
            if view == "files"
            else "Projects",
        )
    ).strip()[:120]

    caption = str(
        payload.get(
            "caption",
            "Provided by YUKI",
        )
    ).strip()[:160]

    raw_items = payload.get(
        "items",
        [],
    )

    if not isinstance(
        raw_items,
        list,
    ):
        raise ValueError(
            "Explorer items must be a list."
        )

    items = []

    for raw_item in raw_items[:100]:
        if not isinstance(
            raw_item,
            dict,
        ):
            continue

        name = str(
            raw_item.get(
                "name",
                "",
            )
        ).strip()

        if not name:
            continue

        kind = str(
            raw_item.get(
                "kind",
                "folder",
            )
        ).strip().lower()

        if kind not in {
            "file",
            "folder",
        }:
            kind = "folder"

        path = str(
            raw_item.get(
                "path",
                "",
            )
        ).strip()

        items.append(
            {
                "name": name[:200],
                "kind": kind,
                "path": path[:500],
            }
        )

    with _explorer_lock:
        _explorer_state["revision"] = (
            int(
                _explorer_state[
                    "revision"
                ]
            )
            + 1
        )

        _explorer_state["action"] = (
            action
        )

        if action == "show":
            _explorer_state["view"] = (
                view
            )

            _explorer_state["title"] = (
                title
            )

            _explorer_state["caption"] = (
                caption
            )

            _explorer_state["items"] = (
                items
            )

        return {
            "revision": int(
                _explorer_state["revision"]
            ),
            "action": str(
                _explorer_state["action"]
            ),
            "view": str(
                _explorer_state["view"]
            ),
            "title": str(
                _explorer_state["title"]
            ),
            "caption": str(
                _explorer_state["caption"]
            ),
            "items": [
                dict(item)
                for item
                in _explorer_state["items"]
            ],
        }


def read_ui_state() -> dict:
    with _ui_state_lock:
        return {
            "revision": int(_ui_state["revision"]),
            "layout": dict(_ui_state["layout"]),
        }


def set_ui_state(payload: dict) -> dict:
    raw_layout = payload.get("layout", {})

    if raw_layout is None:
        raw_layout = {}

    if not isinstance(raw_layout, dict):
        raise ValueError("UI layout must be an object.")

    with _ui_state_lock:
        changed = False

        for key, (low, high) in _UI_LAYOUT_LIMITS.items():
            if key not in raw_layout:
                continue

            try:
                value = float(raw_layout[key])
            except (TypeError, ValueError):
                raise ValueError(f"Invalid UI layout value: {key}")

            value = max(low, min(high, value))

            if key == "durationMs":
                value = int(round(value))

            if _ui_state["layout"].get(key) != value:
                _ui_state["layout"][key] = value
                changed = True

        if changed:
            _ui_state["revision"] = int(_ui_state["revision"]) + 1

        return {
            "revision": int(_ui_state["revision"]),
            "layout": dict(_ui_state["layout"]),
        }


def port_ready(port: int) -> bool:
    try:
        with socket.create_connection(("127.0.0.1", port), timeout=0.20):
            return True
    except OSError:
        return False

def twitch_process_running() -> bool:
    escaped = TWITCH_SCRIPT.replace("'", "''")
    command = (
        "$p = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | "
        f"Where-Object {{ $_.CommandLine -and $_.CommandLine -like '*{escaped}*' }} | "
        "Select-Object -First 1; "
        "if ($p) { '1' } else { '0' }"
    )
    creationflags = getattr(subprocess, "CREATE_NO_WINDOW", 0)
    try:
        result = subprocess.run(
            ["powershell.exe", "-NoProfile", "-NonInteractive", "-Command", command],
            capture_output=True,
            text=True,
            timeout=2.0,
            creationflags=creationflags,
        )
        return result.returncode == 0 and result.stdout.strip().endswith("1")
    except (OSError, subprocess.SubprocessError):
        return False

def twitch_state() -> str:
    if not twitch_process_running():
        return "disconnected"
    try:
        if os.path.exists(TWITCH_LOG):
            with open(TWITCH_LOG, "r", encoding="utf-8", errors="replace") as handle:
                if "Connected. Chat messages:" in handle.read():
                    return "connected"
    except OSError:
        pass
    return "connecting"

def read_activity() -> dict:
    with _activity_lock:
        return dict(_activity_state)


def set_activity(payload: dict) -> dict:
    with _activity_lock:

        if "brain_processing" in payload:
            _activity_state["brain_processing"] = bool(
                payload["brain_processing"]
            )

        if "voice_level" in payload:
            try:
                voice_level = float(
                    payload["voice_level"]
                )
            except (TypeError, ValueError):
                voice_level = 0.0

            _activity_state["voice_level"] = max(
                0.0,
                min(1.0, voice_level),
            )

        return dict(_activity_state)

def read_status() -> dict:
    global _status_cache, _status_cache_time
    now = time.monotonic()
    with _status_lock:
        if _status_cache is not None and now - _status_cache_time < STATUS_CACHE_SECONDS:
            return dict(_status_cache)
        status = {
            "brain": "ready" if port_ready(8084) else "disconnected",
            "audio": "ready" if port_ready(8083) else "disconnected",
            "twitch": twitch_state(),
        }
        _status_cache = status
        _status_cache_time = now
        return dict(status)

class YukiVisualizerHandler(SimpleHTTPRequestHandler):
    def log_message(self, fmt, *args):
        print("[VISUALIZER] " + (fmt % args), flush=True)

    def send_json(self, payload, status=200):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        parsed = urlparse(self.path)

        if parsed.path not in {
            "/api/activity",
            "/api/transcript",
            "/api/explorer",
            "/api/ui-state",
        }:
            self.send_json(
                {"error": "not found"},
                status=404,
            )
            return

        try:
            length = int(
                self.headers.get(
                    "Content-Length",
                    "0",
                )
            )

            if length > 65536:
                self.send_json(
                    {
                        "error":
                        "request too large"
                    },
                    status=413,
                )
                return

            raw = self.rfile.read(
                length
            )

            payload = (
                json.loads(
                    raw.decode("utf-8")
                )
                if raw
                else {}
            )

            if parsed.path == "/api/activity":
                result = set_activity(
                    payload
                )

            elif parsed.path == "/api/transcript":
                result = add_transcript_message(
                    payload
                )

            elif parsed.path == "/api/explorer":
                result = set_explorer(
                    payload
                )

            else:
                result = set_ui_state(
                    payload
                )

            self.send_json(
                result
            )

        except Exception as error:
            self.send_json(
                {
                    "error":
                    str(error)
                },
                status=400,
            )

    def do_GET(self):
        parsed = urlparse(self.path)

        if parsed.path == "/health":
            self.send_json(
                {
                    "service":
                    "yuki-visualizer",
                    "status":
                    "ready",
                }
            )
            return

        if parsed.path == "/api/status":
            self.send_json(
                read_status()
            )
            return

        if parsed.path == "/api/activity":
            self.send_json(
                read_activity()
            )
            return

        if parsed.path == "/api/transcript":
            self.send_json(
                read_transcript()
            )
            return

        if parsed.path == "/api/explorer":
            self.send_json(
                read_explorer()
            )
            return

        if parsed.path == "/api/ui-state":
            self.send_json(
                read_ui_state()
            )
            return

        super().do_GET()

def main():
    parser = argparse.ArgumentParser(description="YUKI local visualizer server")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8085)
    args = parser.parse_args()
    web_root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "visualizer")
    os.chdir(web_root)
    server = ThreadingHTTPServer((args.host, args.port), YukiVisualizerHandler)
    print(f"[VISUALIZER] serving http://{args.host}:{args.port}/", flush=True)
    print(f"[VISUALIZER] web root: {web_root}", flush=True)
    print("[VISUALIZER] status API: /api/status", flush=True)
    print("[VISUALIZER] explorer API: /api/explorer", flush=True)
    print("[VISUALIZER] UI sync API: /api/ui-state", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()

if __name__ == "__main__":
    main()
