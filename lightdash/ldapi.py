import json, re, urllib.request, pathlib
cfg = (pathlib.Path.home()/".config/lightdash/config.yaml").read_text()
TOKEN = re.search(r"apiKey:\s*(\S+)", cfg).group(1)   # read at runtime, never printed
BASE = "http://localhost:8080"
def call(method, path, body=None):
    req = urllib.request.Request(BASE + path, method=method, data=None if body is None else json.dumps(body).encode(),
                                 headers={"Authorization": f"ApiKey {TOKEN}", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=60) as r: return json.loads(r.read())
    except urllib.error.HTTPError as e:
        return {"status": "error", "http": e.code, "body": e.read().decode()[:1500]}
