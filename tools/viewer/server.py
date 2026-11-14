import http.server
import json
import os

ROOT = r"C:\myGames3D\three-skies"
TUNING = os.path.join(ROOT, "tools", "viewer", "tuning.json")
MARKS = os.path.join(ROOT, "tools", "viewer", "marks.json")
PORT = 8000


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=ROOT, **kwargs)

    def do_GET(self):
        if self.path.split("?")[0] == "/tuning":
            if os.path.exists(TUNING):
                with open(TUNING, "r", encoding="utf-8") as f:
                    data = f.read()
            else:
                data = "{}"
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(data.encode("utf-8"))
            return
        super().do_GET()

    def do_POST(self):
        path = self.path.split("?")[0]
        target = TUNING if path == "/save" else MARKS if path == "/save_marks" else None
        if target is not None:
            length = int(self.headers.get("Content-Length", "0"))
            body = self.rfile.read(length)
            try:
                data = json.loads(body.decode("utf-8"))
            except Exception:
                self.send_error(400, "Bad JSON")
                return
            os.makedirs(os.path.dirname(target), exist_ok=True)
            with open(target, "w", encoding="utf-8") as f:
                json.dump(data, f, ensure_ascii=False, indent=2)
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(b'{"success":true}')
            return
        self.send_error(404)

    def log_message(self, fmt, *args):
        pass


if __name__ == "__main__":
    os.chdir(ROOT)
    with http.server.ThreadingHTTPServer(("127.0.0.1", PORT), Handler) as httpd:
        print("Tuner server: http://127.0.0.1:%d/tools/viewer/index.html" % PORT)
        httpd.serve_forever()
