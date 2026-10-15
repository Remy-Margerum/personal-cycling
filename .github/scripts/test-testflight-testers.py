#!/usr/bin/env python3
"""Runs testflight-testers.py against a stand-in App Store Connect API.

The stub keeps its state in memory, checks every request's ES256 token with
openssl against the public half of a key made for the test (so the script's
signature encoding is checked, not assumed), pages one of its lists, and
answers the way Apple's API does in the cases the script handles (a tester
already on the team is a 409). Needs python3 and openssl. Run:
  python3 .github/scripts/test-testflight-testers.py
"""

import base64
import json
import os
import subprocess
import sys
import tempfile
import threading
import time
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "testflight-testers.py")
KEY_ID, ISSUER = "KEY123", "issuer-abc"
failures = 0


def check(name, ok, detail=""):
    global failures
    print(("ok   " if ok else "FAIL ") + name + ("" if ok else f"  ({detail})"))
    if not ok:
        failures += 1


def unb64(text):
    return base64.urlsafe_b64decode(text + "=" * (-len(text) % 4))


def der(r, s):
    def integer(raw):
        raw = raw.lstrip(b"\x00") or b"\x00"
        if raw[0] & 0x80:
            raw = b"\x00" + raw
        return b"\x02" + bytes([len(raw)]) + raw
    body = integer(r) + integer(s)
    return b"\x30" + bytes([len(body)]) + body


class State:
    def __init__(self):
        self.apps = [{"id": "app1", "bundleId": "com.remymargerum.margerumcrush", "name": "Margerum"}]
        self.groups = [
            {"id": "g-team", "name": "Team", "isInternalGroup": True, "testers": ["t-remy"], "builds": ["b1"]},
            {"id": "g-other", "name": "Old Friends", "isInternalGroup": False, "testers": [], "builds": []},
        ]
        self.testers = {"t-remy": "owner@example.com", "t-old": "old@example.com"}
        self.builds = [
            {"id": "b2", "version": "5.1", "uploadedDate": "2026-10-15T18:06:00Z", "processingState": "PROCESSING",
             "expired": False, "external": "PROCESSING"},
            {"id": "b1", "version": "4.1", "uploadedDate": "2026-10-14T21:33:00Z", "processingState": "VALID",
             "expired": False, "external": "READY_FOR_BETA_SUBMISSION"},
        ]
        self.app_locs = []
        self.build_locs = {}
        self.review = {"contactFirstName": None, "contactLastName": None, "contactPhone": None,
                       "contactEmail": None, "demoAccountRequired": False}
        self.submissions = []
        self.writes = []
        self.ids = 0

    def new_id(self, prefix):
        self.ids += 1
        return f"{prefix}{self.ids}"


STATE = State()
PUBLIC_KEY = None


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def reply(self, status, payload=None):
        body = json.dumps(payload).encode() if payload is not None else b""
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def error(self, status, title, detail):
        self.reply(status, {"errors": [{"status": str(status), "title": title, "detail": detail}]})

    def authorized(self):
        header = self.headers.get("Authorization", "")
        if not header.startswith("Bearer "):
            return False
        parts = header[7:].split(".")
        if len(parts) != 3:
            return False
        head, claims = json.loads(unb64(parts[0])), json.loads(unb64(parts[1]))
        if head.get("alg") != "ES256" or head.get("kid") != KEY_ID:
            return False
        if claims.get("iss") != ISSUER or claims.get("aud") != "appstoreconnect-v1":
            return False
        if not (0 < claims["exp"] - claims["iat"] <= 1200 and claims["exp"] > time.time()):
            return False
        sig = unb64(parts[2])
        if len(sig) != 64:
            return False
        with tempfile.NamedTemporaryFile(delete=False) as f:
            f.write(der(sig[:32], sig[32:]))
            sig_file = f.name
        try:
            run = subprocess.run(["openssl", "dgst", "-sha256", "-verify", PUBLIC_KEY, "-signature", sig_file],
                                 input=f"{parts[0]}.{parts[1]}".encode(), capture_output=True)
        finally:
            os.unlink(sig_file)
        return run.returncode == 0

    def body(self):
        length = int(self.headers.get("Content-Length") or 0)
        return json.loads(self.rfile.read(length)) if length else None

    def do_GET(self):
        self.route("GET")

    def do_POST(self):
        self.route("POST")

    def do_PATCH(self):
        self.route("PATCH")

    def route(self, method):
        if not self.authorized():
            return self.error(401, "Authentication credentials are missing or invalid.",
                              "Provide a properly configured and signed bearer token.")
        url = urllib.parse.urlparse(self.path)
        q = {k: v[0] for k, v in urllib.parse.parse_qs(url.query).items()}
        p = url.path.rstrip("/").split("/")[1:]  # ['v1', ...]
        s = STATE
        payload = self.body() if method != "GET" else None
        if method != "GET":
            s.writes.append((method, url.path, payload))

        def group(gid):
            return next(g for g in s.groups if g["id"] == gid)

        def group_json(g):
            return {"type": "betaGroups", "id": g["id"],
                    "attributes": {"name": g["name"], "isInternalGroup": g["isInternalGroup"]}}

        def tester_json(tid):
            return {"type": "betaTesters", "id": tid, "attributes": {"email": s.testers[tid], "state": "INVITED"}}

        if method == "GET" and p == ["v1", "apps"]:
            return self.reply(200, {"data": [
                {"type": "apps", "id": a["id"], "attributes": {"name": a["name"], "bundleId": a["bundleId"]}}
                for a in s.apps if a["bundleId"] == q.get("filter[bundleId]")]})
        if method == "GET" and p == ["v1", "betaGroups"]:
            mine = [g for g in s.groups if q.get("filter[app]") == "app1"]
            start = int(q.get("cursor", 0))
            page = {"data": [group_json(g) for g in mine[start:start + 1]], "links": {}}
            if start + 1 < len(mine):  # one per page, so the script must follow links.next
                page["links"]["next"] = f"http://{self.headers['Host']}/v1/betaGroups?filter%5Bapp%5D=app1&cursor={start + 1}"
            return self.reply(200, page)
        if method == "POST" and p == ["v1", "betaGroups"]:
            g = {"id": s.new_id("g"), "name": payload["data"]["attributes"]["name"],
                 "isInternalGroup": False, "testers": [], "builds": []}
            s.groups.append(g)
            return self.reply(201, {"data": group_json(g)})
        if method == "GET" and len(p) == 4 and p[1] == "betaGroups" and p[3] == "betaTesters":
            return self.reply(200, {"data": [tester_json(t) for t in group(p[2])["testers"]], "links": {}})
        if method == "GET" and p == ["v1", "betaTesters"]:
            email = q.get("filter[email]")
            return self.reply(200, {"data": [tester_json(t) for t, e in s.testers.items() if e == email]})
        if method == "POST" and p == ["v1", "betaTesters"]:
            email = payload["data"]["attributes"]["email"]
            if email in s.testers.values():
                return self.error(409, "The provided entity includes a relationship with an invalid value",
                                  f"A tester with the email {email} already exists.")
            tid = s.new_id("t")
            s.testers[tid] = email
            for link in payload["data"]["relationships"]["betaGroups"]["data"]:
                group(link["id"])["testers"].append(tid)
            return self.reply(201, {"data": tester_json(tid)})
        if method == "POST" and len(p) == 5 and p[1] == "betaGroups" and p[3] == "relationships":
            g = group(p[2])
            key = "testers" if p[4] == "betaTesters" else "builds"
            for link in payload["data"]:
                if link["id"] not in g[key]:
                    g[key].append(link["id"])
            return self.reply(204)
        if method == "GET" and len(p) == 5 and p[1] == "betaGroups" and p[4] == "builds":
            return self.reply(200, {"data": [{"type": "builds", "id": b} for b in group(p[2])["builds"]], "links": {}})
        if method == "GET" and p == ["v1", "builds"]:
            data, included = [], []
            for b in s.builds:
                data.append({"type": "builds", "id": b["id"],
                             "attributes": {"version": b["version"].split(".")[0], "uploadedDate": b["uploadedDate"],
                                            "processingState": b["processingState"], "expired": b["expired"]},
                             "relationships": {"preReleaseVersion": {"data": {"type": "preReleaseVersions", "id": "v01"}},
                                               "buildBetaDetail": {"data": {"type": "buildBetaDetails", "id": "d" + b["id"]}}}})
                included.append({"type": "buildBetaDetails", "id": "d" + b["id"],
                                 "attributes": {"externalBuildState": b["external"]}})
            included.append({"type": "preReleaseVersions", "id": "v01", "attributes": {"version": "0.1"}})
            return self.reply(200, {"data": data, "included": included})
        if method == "GET" and p == ["v1", "apps", "app1", "betaAppLocalizations"]:
            return self.reply(200, {"data": s.app_locs, "links": {}})
        if method == "POST" and p == ["v1", "betaAppLocalizations"]:
            loc = {"type": "betaAppLocalizations", "id": s.new_id("l"),
                   "attributes": dict({"feedbackEmail": None}, **payload["data"]["attributes"])}
            s.app_locs.append(loc)
            return self.reply(201, {"data": loc})
        if method == "PATCH" and p[:2] == ["v1", "betaAppLocalizations"]:
            loc = next(x for x in s.app_locs if x["id"] == p[2])
            loc["attributes"].update(payload["data"]["attributes"])
            return self.reply(200, {"data": loc})
        if method == "GET" and len(p) == 4 and p[1] == "builds" and p[3] == "betaBuildLocalizations":
            return self.reply(200, {"data": s.build_locs.get(p[2], []), "links": {}})
        if method == "POST" and p == ["v1", "betaBuildLocalizations"]:
            build_id = payload["data"]["relationships"]["build"]["data"]["id"]
            loc = {"type": "betaBuildLocalizations", "id": s.new_id("bl"), "attributes": payload["data"]["attributes"]}
            s.build_locs.setdefault(build_id, []).append(loc)
            return self.reply(201, {"data": loc})
        if method == "GET" and p == ["v1", "apps", "app1", "betaAppReviewDetail"]:
            return self.reply(200, {"data": {"type": "betaAppReviewDetails", "id": "app1", "attributes": s.review}})
        if method == "POST" and p == ["v1", "betaAppReviewSubmissions"]:
            build_id = payload["data"]["relationships"]["build"]["data"]["id"]
            build = next(b for b in s.builds if b["id"] == build_id)
            if build["external"] != "READY_FOR_BETA_SUBMISSION":
                return self.error(409, "The request cannot be fulfilled", "The build is already submitted.")
            build["external"] = "WAITING_FOR_BETA_REVIEW"
            s.submissions.append(build_id)
            return self.reply(201, {"data": {"type": "betaAppReviewSubmissions", "id": s.new_id("sub")}})
        return self.error(404, "Not found", f"{method} {url.path}")


def run(folder, port, key, emails=None, key_id=KEY_ID, extra_args=(), env_emails=None):
    event = os.path.join(folder, "event.json")
    with open(event, "w") as f:
        json.dump({"inputs": {"app": "crush", "emails": emails or "", "group": "Friends & Family"}}, f)
    env = dict(os.environ, ASC_API=f"http://127.0.0.1:{port}", ASC_KEY_ID=key_id, ASC_ISSUER_ID=ISSUER,
               ASC_KEY_P8=key, GITHUB_ACTIONS="true", GITHUB_EVENT_PATH=event,
               GITHUB_STEP_SUMMARY=os.path.join(folder, "summary.md"))
    args = ["python3", SCRIPT, "--app", "crush", "--group", "Friends & Family", *extra_args]
    if env_emails is None:
        args.append("--from-event")
    else:
        args += ["--emails", env_emails]
    done = subprocess.run(args, env=env, capture_output=True, text=True, timeout=120)
    return done.returncode, done.stdout + done.stderr


def leaks(output, emails):
    """Full emails anywhere but an ::add-mask:: command (which GitHub swallows)."""
    shown = "\n".join(line for line in output.splitlines() if not line.startswith("::add-mask::"))
    return [e for e in emails if e in shown]


def main():
    global PUBLIC_KEY
    folder = tempfile.mkdtemp()
    pem, p8, PUBLIC_KEY = (os.path.join(folder, n) for n in ("k.pem", "k.p8", "pub.pem"))
    subprocess.run(["openssl", "ecparam", "-name", "prime256v1", "-genkey", "-noout", "-out", pem], check=True)
    subprocess.run(["openssl", "pkcs8", "-topk8", "-nocrypt", "-in", pem, "-out", p8], check=True)
    subprocess.run(["openssl", "ec", "-in", pem, "-pubout", "-out", PUBLIC_KEY], check=True,
                   capture_output=True)
    key = open(p8).read()
    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    port = server.server_address[1]
    threading.Thread(target=server.serve_forever, daemon=True).start()
    s = STATE
    invited = ["new.person@example.com", "old@example.com"]

    # 1. No emails: a report, no writes.
    code, out = run(folder, port, key)
    check("report-only run succeeds", code == 0, out)
    check("report-only run writes nothing", s.writes == [], s.writes)
    check("report-only run says so", "only reports" in out, out)
    check("report-only run follows links.next through every group", "Old Friends (external)" in out, out)
    check("report-only run names the processed build", "0.1 (4)" in out, out)

    # 2. Two testers (one new, one already on the team; one repeated and in
    #    another case), a key pasted with Windows line endings.
    code, out = run(folder, port, key.replace("\n", "\r\n"),
                    emails=" New.Person@Example.com, old@example.com\nnew.person@example.com ")
    group = next((g for g in s.groups if g["name"] == "Friends & Family"), None)
    check("invite run succeeds", code == 0, out)
    check("makes the external group", group is not None and not group["isInternalGroup"], s.groups)
    emails_in = sorted(s.testers[t] for t in (group or {"testers": []})["testers"])
    check("both testers are in the group, once each", emails_in == sorted(invited), emails_in)
    check("a new tester is created", any(w[:2] == ("POST", "/v1/betaTesters") for w in s.writes), s.writes)
    check("an existing tester is linked, not recreated",
          any(w[1].endswith("/relationships/betaTesters") for w in s.writes), s.writes)
    check("the processed build (not the one still processing) joins the group",
          group is not None and group["builds"] == ["b1"], group)
    check("the beta app description is written",
          s.app_locs and "Margerum Crush is a harvest-and-blending game" in s.app_locs[0]["attributes"]["description"],
          s.app_locs)
    check("What to Test is written on that build", bool(s.build_locs.get("b1")), s.build_locs)
    check("nothing is submitted while Apple's contact details are missing", s.submissions == [], s.submissions)
    check("names what is missing and where",
          "Feedback Email" in out and "phone number" in out and "Test Information" in out, out)
    check("the internal group is left alone",
          next(g for g in s.groups if g["id"] == "g-team")["testers"] == ["t-remy"], s.groups)
    check("no full email in the log", leaks(out, invited + ["owner@example.com"]) == [], leaks(out, invited))
    check("each email is masked", all(f"::add-mask::{e}" in out for e in invited), out)
    check("shortened emails are shown", "n•••n@example.com" in out and "o•••d@example.com" in out, out)
    summary = open(os.path.join(folder, "summary.md")).read()
    check("the step summary carries no full email", leaks(summary, invited) == [], summary)

    # 3. Remy fills in Test Information; the next run submits the build.
    s.app_locs[0]["attributes"]["feedbackEmail"] = "feedback@example.com"
    s.review.update(contactFirstName="Remy", contactLastName="M", contactPhone="555-0100",
                    contactEmail="feedback@example.com")
    writes_before = len(s.writes)
    code, out = run(folder, port, key, emails="new.person@example.com old@example.com")
    check("second run succeeds", code == 0, out)
    check("testers already in the group are left as they are", out.count("already in the group") == 2, out)
    check("submits the build for TestFlight App Review", s.submissions == ["b1"], s.submissions)
    check("says it was submitted", "Submitted build 0.1 (4)" in out, out)
    check("a description already there is not rewritten",
          not any(w[0] == "PATCH" for w in s.writes[writes_before:]), s.writes[writes_before:])

    # 4. Again: the build is waiting for review, so nothing is resubmitted.
    code, out = run(folder, port, key, emails="new.person@example.com")
    check("third run succeeds", code == 0, out)
    check("no second submission", s.submissions == ["b1"], s.submissions)
    check("says the build is waiting for review", "waiting for TestFlight App Review" in out, out)

    # 5. Mistakes.
    writes_before = len(s.writes)
    code, out = run(folder, port, key, emails="someone@example.com, not-an-email")
    check("a malformed email stops the run", code == 1 and "don't look like email addresses" in out, out)
    check("... before anything is written", len(s.writes) == writes_before, s.writes[writes_before:])
    check("... without printing it", "not-an-email" not in out.replace("::add-mask::not-an-email", ""), out)
    code, out = run(folder, port, key, key_id="WRONGKEY", emails="someone@example.com")
    check("a refused key fails with the reason", code == 1 and "App Manager or Admin" in out, out)
    code, out = run(folder, port, "not a key", emails="someone@example.com")
    check("an unreadable key fails with the reason", code == 1 and "AuthKey_" in out, out)
    env = {k: v for k, v in os.environ.items() if not k.startswith("ASC_")}
    done = subprocess.run(["python3", SCRIPT, "--emails", "a@example.com"], env=env, capture_output=True, text=True)
    check("missing secrets fail by name", done.returncode == 1 and "ASC_KEY_P8" in done.stdout, done.stdout)
    check("nothing was written by the failed runs", len(s.writes) == writes_before, s.writes[writes_before:])

    server.shutdown()
    print(f"\n{'all passed' if not failures else f'{failures} failed'}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
