
from flask import Flask, request, jsonify
import os, subprocess

API_KEY = os.environ.get("TBG_API_KEY", "")

app = Flask(__name__)

@app.get("/health")
def health():
    return jsonify(ok=True)

def authed(req):
    key = req.headers.get("X-API-Key", "")
    return API_KEY and key == API_KEY

@app.post("/deploy")
def deploy():
    if not authed(request):
        return jsonify(error="unauthorized"), 401
    script = "/opt/tbg-deploy/deploy.sh"
    if not os.path.exists(script):
        return jsonify(error="deploy.sh not found"), 500
    try:
        p = subprocess.run(["bash", script], capture_output=True, text=True, timeout=1800)
        return jsonify(code=p.returncode, stdout=p.stdout[-5000:], stderr=p.stderr[-5000:])
    except subprocess.TimeoutExpired:
        return jsonify(error="timeout"), 500
