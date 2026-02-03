#!/usr/bin/env python3
"""
One-way Roblox script export server.

- Listens on localhost:34873
- Accepts POST /export with JSON payload
- Writes Rojo-compatible .luau files under: ./MyGame/src/
"""

import http.server
import json
import os
from pathlib import Path

HOST = "127.0.0.1"
PORT = 34873
EXPORT_ROUTE = "/export"
PROJECT_ROOT = "MyGame"
BASE_DIR = Path(os.getcwd()).resolve()


def sanitize_segment(value, field_name):
    """Validate a single path segment to avoid invalid or unsafe paths."""
    if not isinstance(value, str):
        raise ValueError(f"{field_name} must be a string")
    segment = value.strip()
    if not segment:
        raise ValueError(f"{field_name} cannot be empty")
    if segment in {".", ".."} or "/" in segment or "\\" in segment:
        raise ValueError(f"{field_name} contains invalid path characters")
    return segment


def rojo_filename(script_name, script_type):
    """Map Roblox script types to Rojo-compatible file names."""
    name = sanitize_segment(script_name, "name")
    if script_type == "Script":
        return f"{name}.server.luau"
    if script_type == "LocalScript":
        return f"{name}.client.luau"
    if script_type == "ModuleScript":
        return f"{name}.luau"
    raise ValueError("type must be Script, LocalScript, or ModuleScript")


def build_target(record):
    """Build output file path and return (target_path, source_text)."""
    service = sanitize_segment(record.get("service"), "service")
    name = record.get("name")
    script_type = record.get("type")
    source = record.get("source")

    if not isinstance(source, str):
        raise ValueError("source must be a string")

    raw_path = record.get("path", [])
    if not isinstance(raw_path, list):
        raise ValueError("path must be an array")

    safe_path_parts = [sanitize_segment(part, "path[]") for part in raw_path]

    root = BASE_DIR / PROJECT_ROOT / "src"
    folder = root / service
    for part in safe_path_parts:
        folder = folder / part
    folder.mkdir(parents=True, exist_ok=True)

    filename = rojo_filename(name, script_type)
    return folder / filename, source


class ExportHandler(http.server.BaseHTTPRequestHandler):
    def _send_json(self, status_code, payload):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status_code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        if self.path != EXPORT_ROUTE:
            self._send_json(404, {"error": "Not found"})
            return

        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            self._send_json(400, {"error": "Invalid Content-Length"})
            return

        raw_body = self.rfile.read(length)

        try:
            payload = json.loads(raw_body.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            self._send_json(400, {"error": "Request body must be valid JSON"})
            return

        if not isinstance(payload, dict):
            self._send_json(400, {"error": "JSON body must be an object"})
            return

        scripts = payload.get("scripts")
        if not isinstance(scripts, list):
            self._send_json(400, {"error": "scripts must be an array"})
            return

        exported = 0
        errors = []

        for i, record in enumerate(scripts):
            if not isinstance(record, dict):
                errors.append(f"scripts[{i}] must be an object")
                continue
            try:
                target_file, source = build_target(record)
                with target_file.open("w", encoding="utf-8", newline="") as file_handle:
                    file_handle.write(source)
                exported += 1
            except ValueError as exc:
                errors.append(f"scripts[{i}]: {exc}")

        print(f"Exported {exported} scripts")
        if errors:
            print(f"Skipped {len(errors)} invalid entries")

        self._send_json(
            200,
            {
                "exported": exported,
                "skipped": len(errors),
                "errors": errors,
            },
        )

    def do_GET(self):
        self._send_json(405, {"error": "Use POST /export"})

    def log_message(self, fmt, *args):
        # Keep request logs visible in the terminal.
        print(f"{self.client_address[0]} - {fmt % args}")


def main():
    server = http.server.HTTPServer((HOST, PORT), ExportHandler)
    print(f"Listening on http://{HOST}:{PORT}{EXPORT_ROUTE}")
    print(f"Writing exports under: {BASE_DIR / PROJECT_ROOT}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down server...")
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
