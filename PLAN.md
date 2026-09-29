# Plan

A personal iPhone cycling app: AirPods Pro 3 heart rate, Favero Assioma
power and cadence, GPS speed/distance/route, barometric climbing. Rides go
to Apple Health and Intervals.icu (which feeds remymargerum.com/cycling).

Everything is built in the cloud. No Mac is required: GitHub's macOS
runners compile, sign and upload the app to TestFlight, and the phone
installs it from the TestFlight app. A Mac mini with Xcode is an optional
shortcut for live debugging, nothing more.

## Costs

| Item | Cost |
|---|---|
| Apple Developer Program (needed for HealthKit) | US$99/year |
| GitHub Actions on this public repo | $0 (macOS runners are free for public repos) |
| TestFlight | $0 |

## Phase 0 — Accounts (Remy, ~30 min plus Apple's approval time)

- [ ] Enroll in the Apple Developer Program at developer.apple.com (or the
      Apple Developer app on iPhone). Needs an Apple ID with two-factor
      authentication. Approval can take a day or two.
- [ ] Once approved, note the **Team ID** (developer.apple.com → Membership).

## Phase 1 — Code in this repo (done)

- [x] `RideKit` package with unit tests (`cd RideKit && swift test`, runs on
      Linux/macOS).
- [x] iOS app sources, XcodeGen `project.yml`, README.
- [ ] Delete the `claude/airpods-workout-app-integration-n41vw2` branch in
      `personalWebsite`; nothing there is needed any more.

## Phase 2 — Cloud compile check (Claude)

- [ ] `.github/workflows/ci.yml`: on every push,
  - Ubuntu job runs the RideKit tests;
  - macOS job runs `xcodegen` and builds the app unsigned
    (`CODE_SIGNING_ALLOWED=NO`).
- [ ] Fix whatever compile errors the first macOS build reports. The app
      code has only been syntax-checked so far, never compiled against the
      iOS SDK.

## Phase 3 — Signing and TestFlight (Remy in the browser, Claude on the CLI, ~45 min once)

Everything here happens on developer.apple.com, appstoreconnect.apple.com
and the GitHub repo settings. Claude gives step-by-step instructions and
runs the command-line parts.

1. **App ID.** Certificates, Identifiers & Profiles → Identifiers → new App
   ID `com.remymargerum.bikecomputer` with the **HealthKit** capability.
2. **Distribution certificate.** Claude generates a private key and
   certificate signing request (`openssl`); Remy uploads the CSR under
   Certificates → Apple Distribution, downloads the `.cer`; Claude bundles
   it into a password-protected `.p12`.
3. **Provisioning profile.** Profiles → App Store → the App ID above →
   the new certificate. Download the `.mobileprovision`.
4. **App record.** App Store Connect → Apps → new app, bundle ID from step
   1, name "Bike Computer". Under TestFlight, add Remy as an internal
   tester.
5. **API key.** App Store Connect → Users and Access → Integrations →
   App Store Connect API → new key with the **App Manager** role.
   Download the `.p8` (only offered once) and note the Key ID and Issuer ID.
6. **GitHub secrets** (repo → Settings → Secrets and variables → Actions):

   | Secret | Contents |
   |---|---|
   | `APPLE_TEAM_ID` | from Phase 0 |
   | `BUILD_CERTIFICATE_BASE64` | the `.p12`, base64-encoded |
   | `P12_PASSWORD` | its password |
   | `PROVISIONING_PROFILE_BASE64` | the `.mobileprovision`, base64-encoded |
   | `ASC_KEY_ID` | Key ID from step 5 |
   | `ASC_ISSUER_ID` | Issuer ID from step 5 |
   | `ASC_KEY_P8` | contents of the `.p8` file |

7. **Workflow.** Claude adds `.github/workflows/testflight.yml`: on push
   to `main` (and on demand), archive, sign with the secrets above, upload
   with `xcrun altool` / App Store Connect API. First successful run →
   the build appears in TestFlight on the phone within ~15 minutes.

Secrets never go into the repo; they live only in GitHub's encrypted
secrets and on Remy's computer.

## Phase 4 — First hardware check (Remy with the phone, Claude on call)

Before this, Claude adds a **Debug** screen to the app that logs raw
power-meter packets, heart-rate events and GPS fixes, with a share button,
so problems can be diagnosed from a log file.

- [ ] Install from TestFlight. Grant Bluetooth, Location and Health
      permissions when asked.
- [ ] Sensors → spin the cranks → Scan → pick the Assiomas. Power, cadence,
      L/R balance and battery show up.
- [ ] One AirPod Pro 3 in → Start. Heart rate appears within ~30 s.
- [ ] Lock the phone for two minutes, unlock: heart rate and GPS kept going.
- [ ] Anything wrong: share the debug log with Claude, get a fix, next
      TestFlight build (~15 min per round).

## Phase 5 — Test rides and tuning (a few rides)

- [ ] Ride with the app and the current setup (Cadence app / head unit) in
      parallel. Compare distance, climbing, average power, NP, heart rate.
- [ ] Check the Apple Health workout: route on the map, power, cadence,
      distance present and not doubled.
- [ ] Upload a TCX to Intervals.icu from the app (API key under Settings).
      It should appear on remymargerum.com/cycling after the next hourly sync.
- [ ] Tune the distance / elevation filters in `RideKit` from the results.

## Phase 6 — Hardening and features (after it works)

In rough order of value:

1. Crash recovery: checkpoint the in-progress ride to disk every minute;
   recover it and the HealthKit session on relaunch.
2. Assioma zero-offset calibration (Cycling Power Control Point, opcode 0x0C).
3. Auto-pause below ~1.5 m/s; laps.
4. Lock-screen Live Activity with power, HR and speed.
5. FIT export (keeps L/R balance; preferred by Intervals and Strava).
6. Direct Bluetooth HR strap and speed/cadence sensor support.
7. FTP / HR zones and interval targets.

## Ongoing

- TestFlight builds expire after **90 days**. Any push to `main` makes a
  new one; with nothing to push, re-run the TestFlight workflow by hand.
- The distribution certificate expires after a year: repeat Phase 3
  steps 2, 3 and 6 then.
- The Developer Program renews yearly. If it lapses, the installed app
  keeps working until its TestFlight build expires.

## Known limits

- AirPods Pro 3 provide heart rate only — no HRV or beat-to-beat data.
- California Vehicle Code 27400: no earbuds in both ears while cycling.
  One AirPod is enough for heart rate.
- If a head unit is also connected to the Assiomas over Bluetooth, the
  phone may not get a connection; pair the head unit over ANT+ instead.
