#!/usr/bin/env python3
"""Invites TestFlight testers to one of this repo's apps through the App
Store Connect API.

With tester emails it:
  1. finds or makes the EXTERNAL beta group (anyone with an email can be an
     external tester; internal testers must be on the App Store Connect team),
  2. adds each email to it,
  3. puts the newest processed build in the group,
  4. fills in the test information this repo can write (the beta app
     description, the build's "What to Test") without overwriting anything,
  5. submits the build for TestFlight App Review once Apple has everything it
     asks for, and otherwise names what is missing and where to add it.

Apple emails each tester once a build in their group is approved. The first
build of a version waits for review (usually within a day); later builds of
the same version are mostly approved at once.

With no emails it changes nothing: it reports the app's groups, the group's
testers, the newest builds and what test information is missing.

The repository is public and GitHub prints a step's env and command line in
the log, so tester emails never travel through either: in the workflow the
script reads them from the run's event payload (--from-event), masks each one
and only ever prints a shortened form (r•••0@gmail.com).

Credentials come from the environment: ASC_KEY_ID, ASC_ISSUER_ID and
ASC_KEY_P8 (the API key the TestFlight workflows upload with). ASC_API
points the script at another server (the tests' stub). Needs python3 and the
openssl command, nothing else.

Tested on Linux by .github/scripts/test-testflight-testers.py.
"""

import argparse
import base64
import json
import os
import re
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

APPS = {
    "crush": {
        "bundle": "com.remymargerum.margerumcrush",
        "name": "Margerum Crush",
        "description": (
            "Margerum Crush is a harvest-and-blending game. You run a Santa Barbara County "
            "winery one vintage at a time, starting with Margerum's first, 2001: watch the "
            "fruit ripen through harvest, pick it bunch by bunch, make the wine as Doug on the "
            "winery floor, age it through the winter, then blend Sybarite, rosé, M5 and ÜBER "
            "Syrah to Doug's range and bottle the rest as single varietals. The wine names and "
            "labels are Margerum's; the prices, scores and vineyard numbers are made up for "
            "the game."
        ),
        "what_to_test": (
            "Play a vintage or two, from harvest to release. Tell us where you got stuck or "
            "confused, anything that felt too easy or too hard, and any crash. To send "
            "feedback, take a screenshot while playing or use Send Beta Feedback in the "
            "TestFlight app."
        ),
    },
    "raggio": {
        "bundle": "com.remymargerum.bikecomputer",
        "name": "Raggio",
        "description": (
            "Raggio is a cycling app for iPhone. It records heart rate from AirPods Pro, power "
            "and cadence from Bluetooth power pedals, and speed, distance and climbing from the "
            "iPhone, shows them live (also on ActiveLook glasses), saves rides to Apple Health "
            "and can upload them to Intervals.icu."
        ),
        "what_to_test": (
            "Record a ride with your sensors paired. Tell us about dropouts, numbers that look "
            "wrong, and anything confusing. To send feedback, take a screenshot in the app or "
            "use Send Beta Feedback in the TestFlight app."
        ),
    },
}

API = os.environ.get("ASC_API", "https://api.appstoreconnect.apple.com").rstrip("/")
EMAIL = re.compile(r"^[^@\s,;]+@[^@\s,;]+\.[^@\s,;]+$")
IN_ACTIONS = os.environ.get("GITHUB_ACTIONS") == "true"


class AscError(Exception):
    pass


# --- Output -------------------------------------------------------------------

summary_lines = []


def say(line=""):
    print(line, flush=True)
    summary_lines.append(line)


def annotate(kind, message):
    """A GitHub notice/warning/error (a plain line outside Actions)."""
    if IN_ACTIONS:
        print(f"::{kind}::{message}", flush=True)
    else:
        print(f"{kind}: {message}", flush=True)
    summary_lines.append(f"**{kind}:** {message}")


def short(email):
    """r•••0@gmail.com: enough to tell testers apart, not enough to mail them."""
    local, _, domain = email.partition("@")
    if len(local) <= 2:
        return f"{local[:1]}•••@{domain}"
    return f"{local[0]}•••{local[-1]}@{domain}"


def mask(email):
    if IN_ACTIONS and email:
        print(f"::add-mask::{email}", flush=True)


def write_summary():
    path = os.environ.get("GITHUB_STEP_SUMMARY")
    if path:
        with open(path, "a", encoding="utf-8") as f:
            f.write("\n".join(summary_lines) + "\n")


# --- App Store Connect API ------------------------------------------------------

def b64url(raw):
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()


def der_ints(der):
    """(r, s) out of an ECDSA-Sig-Value: SEQUENCE { INTEGER r, INTEGER s }."""

    def length(i):
        n = der[i]
        if n < 0x80:
            return n, i + 1
        count = n & 0x7F
        return int.from_bytes(der[i + 1:i + 1 + count], "big"), i + 1 + count

    if der[0] != 0x30:
        raise AscError("openssl did not return an ECDSA signature")
    _, i = length(1)
    values = []
    for _ in range(2):
        if der[i] != 0x02:
            raise AscError("openssl did not return an ECDSA signature")
        n, i = length(i + 1)
        values.append(int.from_bytes(der[i:i + n], "big"))
        i += n
    return values


def make_token(key_id, issuer, p8):
    """An ES256 JWT for the API (Apple allows up to 20 minutes)."""
    now = int(time.time())
    header = b64url(json.dumps({"alg": "ES256", "kid": key_id, "typ": "JWT"}).encode())
    claims = b64url(json.dumps({"iss": issuer, "iat": now, "exp": now + 19 * 60,
                                "aud": "appstoreconnect-v1"}).encode())
    signing_input = f"{header}.{claims}".encode()
    with tempfile.TemporaryDirectory() as folder:
        key = os.path.join(folder, "key.p8")
        with open(os.open(key, os.O_WRONLY | os.O_CREAT, 0o600), "w") as f:
            f.write(p8.replace("\r", "").strip() + "\n")
        run = subprocess.run(["openssl", "dgst", "-sha256", "-sign", key],
                             input=signing_input, capture_output=True)
    if run.returncode != 0:
        raise AscError("openssl could not sign with ASC_KEY_P8. It should be the whole "
                       "AuthKey_<id>.p8 file, BEGIN and END lines included.")
    r, s = der_ints(run.stdout)
    return f"{header}.{claims}.{b64url(r.to_bytes(32, 'big') + s.to_bytes(32, 'big'))}"


class Asc:
    def __init__(self, key_id, issuer, p8):
        self.credentials = (key_id, issuer, p8)
        self.token, self.made = None, 0

    def call(self, method, path, body=None):
        if not self.token or time.time() - self.made > 15 * 60:
            self.token, self.made = make_token(*self.credentials), time.time()
        url = path if path.startswith("http") else API + path
        data = json.dumps(body).encode() if body is not None else None
        request = urllib.request.Request(url, data=data, method=method, headers={
            "Authorization": f"Bearer {self.token}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        })
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                raw = response.read()
                return response.status, json.loads(raw) if raw else None
        except urllib.error.HTTPError as error:
            raw = error.read()
            try:
                return error.code, json.loads(raw) if raw else None
            except ValueError:
                return error.code, None

    def checked(self, method, path, body=None, what=""):
        status, payload = self.call(method, path, body)
        if status >= 400:
            raise AscError(f"{what or method + ' ' + path.split('?')[0]}: {problem(status, payload)}")
        return payload

    def get(self, path, **query):
        if query:
            path += "?" + urllib.parse.urlencode(query)
        return self.checked("GET", path)

    def every(self, path, **query):
        """Every page of a list."""
        items, page = [], self.get(path, **query)
        while True:
            items += page.get("data") or []
            following = (page.get("links") or {}).get("next")
            if not following:
                return items
            page = self.checked("GET", following)


def problem(status, payload):
    errors = (payload or {}).get("errors") or []
    if not errors:
        return f"HTTP {status}"
    text = "; ".join(" ".join(x for x in (e.get("title"), e.get("detail")) if x) for e in errors)
    if status in (401, 403):
        text += (" (HTTP %d: check ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_P8, and that the key's "
                 "role is App Manager or Admin)" % status)
    return text


def ref(kind, ident):
    return {"type": kind, "id": ident}


# --- The steps --------------------------------------------------------------------

def find_app(asc, bundle):
    apps = asc.get("/v1/apps", **{"filter[bundleId]": bundle, "fields[apps]": "name,bundleId"})["data"]
    if not apps:
        raise AscError(f"No app with bundle ID {bundle} in App Store Connect. Make the app record first.")
    return apps[0]


def find_group(asc, app_id, name, create):
    groups = asc.every("/v1/betaGroups", **{"filter[app]": app_id, "limit": 200})
    say("Groups: " + (", ".join(
        f"{g['attributes']['name']} ({'internal' if g['attributes'].get('isInternalGroup') else 'external'})"
        for g in groups) or "none"))
    for group in groups:
        attributes = group["attributes"]
        if not attributes.get("isInternalGroup") and attributes["name"].strip().lower() == name.strip().lower():
            return group
    if not create:
        return None
    group = asc.checked("POST", "/v1/betaGroups", {"data": {
        "type": "betaGroups",
        "attributes": {"name": name},
        "relationships": {"app": {"data": ref("apps", app_id)}},
    }}, what=f"Making the group {name}")["data"]
    say(f"Made the external group {name}.")
    return group


def group_testers(asc, group_id):
    testers = asc.every(f"/v1/betaGroups/{group_id}/betaTesters", limit=200)
    for tester in testers:
        mask(tester["attributes"].get("email"))
    return testers


def add_tester(asc, group_id, email, in_group):
    if email in in_group:
        say(f"- {short(email)}: already in the group")
        return
    found = asc.get("/v1/betaTesters", **{"filter[email]": email, "limit": 1})["data"]
    if not found:
        status, payload = asc.call("POST", "/v1/betaTesters", {"data": {
            "type": "betaTesters",
            "attributes": {"email": email},
            "relationships": {"betaGroups": {"data": [ref("betaGroups", group_id)]}},
        }})
        if status < 400:
            say(f"- {short(email)}: added")
            return
        if status != 409:
            raise AscError(f"Adding {short(email)}: {problem(status, payload)}")
        found = asc.get("/v1/betaTesters", **{"filter[email]": email, "limit": 1})["data"]
        if not found:
            raise AscError(f"Adding {short(email)}: {problem(status, payload)}")
    asc.checked("POST", f"/v1/betaGroups/{group_id}/relationships/betaTesters",
                {"data": [ref("betaTesters", found[0]["id"])]}, what=f"Adding {short(email)}")
    say(f"- {short(email)}: added (already a tester of the team's apps)")


def newest_builds(asc, app_id):
    page = asc.get("/v1/builds", **{
        "filter[app]": app_id, "sort": "-uploadedDate", "limit": 5,
        "include": "preReleaseVersion,buildBetaDetail",
    })
    included = {(x["type"], x["id"]): x for x in page.get("included") or []}
    builds = []
    for build in page.get("data") or []:
        links = build.get("relationships") or {}

        def linked(name):
            data = (links.get(name) or {}).get("data")
            return included.get((data["type"], data["id"])) if data else None

        version = linked("preReleaseVersion")
        detail = linked("buildBetaDetail")
        attributes = build["attributes"]
        builds.append({
            "id": build["id"],
            "label": f"{(version or {}).get('attributes', {}).get('version', '?')} ({attributes.get('version')})",
            "uploaded": (attributes.get("uploadedDate") or "")[:10],
            "processing": attributes.get("processingState"),
            "expired": attributes.get("expired"),
            "external": (detail or {}).get("attributes", {}).get("externalBuildState"),
        })
    return builds


def fill_description(asc, app_id, text, write):
    """The beta app description (TestFlight's "Beta App Description"). Returns the feedback email."""
    localizations = asc.every(f"/v1/apps/{app_id}/betaAppLocalizations", limit=50)
    chosen = next((x for x in localizations if x["attributes"].get("locale") == "en-US"),
                  localizations[0] if localizations else None)
    if chosen is None:
        if not write:
            return None, False
        chosen = asc.checked("POST", "/v1/betaAppLocalizations", {"data": {
            "type": "betaAppLocalizations",
            "attributes": {"locale": "en-US", "description": text},
            "relationships": {"app": {"data": ref("apps", app_id)}},
        }}, what="Writing the beta app description")["data"]
        say("Wrote the beta app description.")
    elif not (chosen["attributes"].get("description") or "").strip():
        if not write:
            return chosen["attributes"].get("feedbackEmail"), False
        chosen = asc.checked("PATCH", f"/v1/betaAppLocalizations/{chosen['id']}", {"data": {
            "type": "betaAppLocalizations", "id": chosen["id"],
            "attributes": {"description": text},
        }}, what="Writing the beta app description")["data"]
        say("Wrote the beta app description.")
    feedback = chosen["attributes"].get("feedbackEmail")
    mask(feedback)
    return feedback, True


def fill_what_to_test(asc, build_id, text, write):
    localizations = asc.every(f"/v1/builds/{build_id}/betaBuildLocalizations", limit=50)
    chosen = next((x for x in localizations if x["attributes"].get("locale") == "en-US"),
                  localizations[0] if localizations else None)
    if chosen and (chosen["attributes"].get("whatsNew") or "").strip():
        return
    if not write:
        return
    if chosen is None:
        asc.checked("POST", "/v1/betaBuildLocalizations", {"data": {
            "type": "betaBuildLocalizations",
            "attributes": {"locale": "en-US", "whatsNew": text},
            "relationships": {"build": {"data": ref("builds", build_id)}},
        }}, what="Writing What to Test")
    else:
        asc.checked("PATCH", f"/v1/betaBuildLocalizations/{chosen['id']}", {"data": {
            "type": "betaBuildLocalizations", "id": chosen["id"],
            "attributes": {"whatsNew": text},
        }}, what="Writing What to Test")
    say("Wrote the build's What to Test.")


def missing_review_details(asc, app_id):
    detail = asc.get(f"/v1/apps/{app_id}/betaAppReviewDetail")["data"]["attributes"]
    mask(detail.get("contactEmail"))
    names = {
        "contactFirstName": "first name", "contactLastName": "last name",
        "contactPhone": "phone number", "contactEmail": "email",
    }
    return [label for key, label in names.items() if not (detail.get(key) or "").strip()]


STATES = {
    "WAITING_FOR_BETA_REVIEW": "waiting for TestFlight App Review: testers get Apple's email once it's approved (usually within a day)",
    "IN_BETA_REVIEW": "in TestFlight App Review: testers get Apple's email once it's approved",
    "BETA_APPROVED": "approved: Apple emails the testers now",
    "IN_BETA_TESTING": "approved and in testing: Apple emails new testers now",
    "BETA_REJECTED": "rejected by TestFlight App Review: App Store Connect → the app → TestFlight says why",
    "MISSING_EXPORT_COMPLIANCE": "missing its export compliance answer (set ITSAppUsesNonExemptEncryption in the app's Info.plist)",
    "PROCESSING": "still processing at Apple",
    "EXPIRED": "expired",
}


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--app", choices=sorted(APPS), default="crush")
    parser.add_argument("--group", default="Friends & Family")
    parser.add_argument("--emails", default="", help="comma- or space-separated (not in the workflow: see --from-event)")
    parser.add_argument("--from-event", action="store_true",
                        help="read the emails from the workflow_dispatch input 'emails' in $GITHUB_EVENT_PATH")
    args = parser.parse_args()

    raw = args.emails
    if args.from_event and os.environ.get("GITHUB_EVENT_PATH"):
        with open(os.environ["GITHUB_EVENT_PATH"], encoding="utf-8") as f:
            raw = ((json.load(f).get("inputs") or {}).get("emails") or "")
    emails, bad = [], []
    for item in re.split(r"[\s,;]+", raw.strip()):
        if not item:
            continue
        item = item.strip("<>\"'").lower()
        mask(item)
        if not EMAIL.match(item):
            bad.append(item)
        elif item not in emails:
            emails.append(item)
    if bad:
        annotate("error", f"{len(bad)} of the emails don't look like email addresses. Nothing was changed.")
        write_summary()
        return 1

    missing = [n for n in ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_KEY_P8") if not os.environ.get(n)]
    if missing:
        annotate("error", "Missing " + ", ".join(missing) + " (the App Store Connect API key secrets).")
        write_summary()
        return 1

    app = APPS[args.app]
    write = bool(emails)
    say(f"## TestFlight testers: {app['name']}")
    say("" if write else "No emails given, so this run only reports and changes nothing.")
    try:
        asc = Asc(os.environ["ASC_KEY_ID"], os.environ["ASC_ISSUER_ID"], os.environ["ASC_KEY_P8"])
        app_record = find_app(asc, app["bundle"])
        app_id = app_record["id"]
        say(f"App: {app_record['attributes'].get('name')} ({app['bundle']})")

        group = find_group(asc, app_id, args.group, create=write)
        if group is None:
            say(f"No external group called {args.group} yet; the first run with emails makes it.")
            in_group = []
        else:
            in_group = group_testers(asc, group["id"])
            emails_in = {(t["attributes"].get("email") or "").lower(): t for t in in_group}
            if write:
                say(f"Testers for {group['attributes']['name']}:")
                for email in emails:
                    add_tester(asc, group["id"], email, emails_in)
                in_group = group_testers(asc, group["id"])
            say(f"{group['attributes']['name']} now has {len(in_group)} tester(s): " + (", ".join(
                f"{short((t['attributes'].get('email') or '').lower())} ({(t['attributes'].get('state') or t['attributes'].get('inviteType') or '').lower().replace('_', ' ')})"
                for t in in_group) or "none"))

        builds = newest_builds(asc, app_id)
        say("Newest builds: " + (", ".join(
            f"{b['label']} uploaded {b['uploaded']}, {(b['processing'] or '').lower()}"
            + (f", external {b['external'].lower().replace('_', ' ')}" if b["external"] else "")
            for b in builds) or "none"))
        build = next((b for b in builds if b["processing"] == "VALID" and not b["expired"]), None)
        if build is None:
            annotate("warning", "No processed build yet. The testers are in the group; Apple invites them "
                     "once a build is added to it and approved. Run this again after the next upload.")
            write_summary()
            return 0

        if group is not None:
            in_builds = {x["id"] for x in asc.every(f"/v1/betaGroups/{group['id']}/relationships/builds", limit=200)}
            if build["id"] not in in_builds and write:
                asc.checked("POST", f"/v1/betaGroups/{group['id']}/relationships/builds",
                            {"data": [ref("builds", build["id"])]}, what="Adding the build to the group")
                say(f"Added build {build['label']} to {group['attributes']['name']}.")
            elif build["id"] in in_builds:
                say(f"Build {build['label']} is in {group['attributes']['name']}.")

        feedback, has_description = fill_description(asc, app_id, app["description"], write)
        fill_what_to_test(asc, build["id"], app["what_to_test"], write)
        needed = []
        if not has_description:
            needed.append("Beta App Description")
        if not (feedback or "").strip():
            needed.append("Feedback Email")
        review = missing_review_details(asc, app_id)
        if review:
            needed.append("Beta App Review contact " + ", ".join(review))

        state = build["external"]
        if state == "READY_FOR_BETA_SUBMISSION":
            if needed:
                annotate("warning", f"Build {build['label']} can't go to TestFlight App Review yet: Apple needs "
                         + "; ".join(needed) + ". Add them in App Store Connect → Apps → " + app["name"]
                         + " → TestFlight → Test Information, then run this workflow again (or press "
                         "Submit for Review on the build in the group). The testers are in the group "
                         "already; Apple emails them once the build is approved.")
            elif write:
                status, payload = asc.call("POST", "/v1/betaAppReviewSubmissions", {"data": {
                    "type": "betaAppReviewSubmissions",
                    "relationships": {"build": {"data": ref("builds", build["id"])}},
                }})
                if status >= 400:
                    annotate("warning", f"Apple didn't take build {build['label']} for review: "
                             + problem(status, payload) + ". Fix that in App Store Connect → TestFlight → "
                             "Test Information and run this again.")
                else:
                    annotate("notice", f"Submitted build {build['label']} for TestFlight App Review. Apple emails "
                             "the testers once it's approved (usually within a day).")
            else:
                say(f"Build {build['label']} is ready to submit for TestFlight App Review.")
        elif state in STATES:
            annotate("notice", f"Build {build['label']} is {STATES[state]}.")
        elif state:
            say(f"Build {build['label']}: {state.lower().replace('_', ' ')}.")
        if needed and state != "READY_FOR_BETA_SUBMISSION":
            say("Test information still missing: " + "; ".join(needed) + ".")
    except AscError as error:
        annotate("error", str(error))
        write_summary()
        return 1
    write_summary()
    return 0


if __name__ == "__main__":
    sys.exit(main())
