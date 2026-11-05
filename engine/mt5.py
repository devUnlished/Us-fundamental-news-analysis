#!/usr/bin/env python3
"""MT5 MCP client library (terminal 127.0.0.1:22346).

Token: $MT5_MCP_TOKEN env var, else /tmp/mt5mcp_token.txt (chmod 600).
Session is negotiated per connect(); pass it through calls.
"""
import json
import os
import urllib.request
import urllib.error

URL = "http://127.0.0.1:22346/mcp"
TOKEN_FILE = "/tmp/mt5mcp_token.txt"


def _token():
    tok = os.environ.get("MT5_MCP_TOKEN")
    if tok:
        return tok.strip()
    with open(TOKEN_FILE) as f:
        return f.read().strip()


def rpc(key, session, method, params=None, req_id=1, timeout=25):
    body = json.dumps({"jsonrpc": "2.0", "id": req_id,
                       "method": method, "params": params or {}}).encode()
    req = urllib.request.Request(URL, data=body, headers={
        "Content-Type": "application/json",
        "Accept": "application/json, text/event-stream",
        "Authorization": f"Bearer {key}",
        "MCP-Protocol-Version": "2025-06-18",
        **({"Mcp-Session-Id": session} if session else {}),
    })
    with urllib.request.urlopen(req, timeout=timeout) as r:
        sess = r.headers.get("Mcp-Session-Id", session)
        ctype = r.headers.get("Content-Type", "")
        text = r.read().decode("utf-8", "replace")
    if "text/event-stream" in ctype:
        for line in text.splitlines():
            if line.startswith("data:"):
                text = line[5:].strip()
                break
    return sess, json.loads(text)


def connect():
    key = _token()
    sess, _ = rpc(key, None, "initialize", {
        "protocolVersion": "2025-06-18", "capabilities": {},
        "clientInfo": {"name": "mini-model", "version": "1.0"}})
    try:
        body = json.dumps({"jsonrpc": "2.0",
                           "method": "notifications/initialized"}).encode()
        req = urllib.request.Request(URL, data=body, headers={
            "Content-Type": "application/json",
            "Accept": "application/json, text/event-stream",
            "Authorization": f"Bearer {key}",
            "MCP-Protocol-Version": "2025-06-18",
            "Mcp-Session-Id": sess})
        urllib.request.urlopen(req, timeout=10).read()
    except Exception:
        pass
    return key, sess


class Client:
    """Thin wrapper keeping session + request ids."""

    def __init__(self):
        self.key, self.sess = connect()
        self._rid = 1

    def call_tool(self, name, args):
        self._rid += 1
        self.sess, res = rpc(self.key, self.sess, "tools/call",
                             {"name": name, "arguments": args}, self._rid)
        txt = "\n".join(b.get("text", "")
                        for b in res.get("result", {}).get("content", []))
        try:
            return json.loads(txt)
        except Exception:
            return {"_raw": txt[:500]}
