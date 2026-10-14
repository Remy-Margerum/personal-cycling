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

## Phase 2 — Cloud compile check (Claude, done)

- [x] `.github/workflows/ci.yml`: on every push,
  - Ubuntu job runs the RideKit tests;
  - macOS job runs `xcodegen` and builds the app unsigned
    (`CODE_SIGNING_ALLOWED=NO`).
- [x] Fix whatever compile errors the first macOS build reports. None:
      the first build (Xcode 26.6, iOS 26 SDK) compiled cleanly.

## Phase 3 — Signing and TestFlight (Remy in the browser and on the Mac, ~45 min once)

Everything here happens on developer.apple.com, appstoreconnect.apple.com,
the GitHub repo settings and Terminal on the Mac. The private key is made
on the Mac and never leaves it except as an encrypted GitHub secret.

1. **App ID.** Certificates, Identifiers & Profiles → Identifiers → **+** →
   App IDs → App. Description `Bike Computer`, Bundle ID **Explicit**
   `com.remymargerum.bikecomputer`, tick **HealthKit**, Register.
2. **Distribution certificate.** In Terminal on the Mac:

   ```sh
   mkdir -p ~/BikeComputerSigning && cd ~/BikeComputerSigning
   /usr/bin/openssl genrsa -out distribution.key 2048
   /usr/bin/openssl req -new -key distribution.key -out distribution.csr \
     -subj "/CN=Bike Computer Distribution/C=US"
   open .
   ```

   Certificates → **+** → **Apple Distribution** → upload
   `distribution.csr` → download the certificate into the same folder as
   `distribution.cer`. Then:

   ```sh
   /usr/bin/openssl x509 -inform DER -in distribution.cer -out distribution.pem
   /usr/bin/openssl pkcs12 -export -inkey distribution.key -in distribution.pem \
     -out distribution.p12
   ```

   The last command asks for an export password: that's `P12_PASSWORD`.
   Use `/usr/bin/openssl` (macOS's own LibreSSL), not a Homebrew OpenSSL 3,
   whose `.p12` files macOS's keychain can't import without `-legacy`.
   Keep `~/BikeComputerSigning` private and out of any repo folder.

   **On Windows** (how it was done in 2026), use Git Bash from Git for
   Windows. Same commands without `/usr/bin/`, plus two differences:
   `MSYS_NO_PATHCONV=1` in front of the `openssl req` line (otherwise Git
   Bash turns `/CN=…` into a file path), and the `.p12` step needs
   `winpty` for its password prompt and 3DES/SHA-1 flags so macOS can
   import the file:

   ```sh
   winpty openssl pkcs12 -export -inkey distribution.key -in distribution.pem \
     -out distribution.p12 -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1
   ```
3. **Provisioning profile.** Profiles → **+** → Distribution: **App Store
   Connect** → the App ID above → the new certificate → name it
   `Bike Computer App Store` → download the `.mobileprovision` into
   `~/BikeComputerSigning`.
4. **App record.** App Store Connect → Apps → **+** → New App: iOS, the
   bundle ID from step 1, SKU `bikecomputer`, name **Raggio**. (The name
   must be unique across the whole App Store even though the app is never
   published. The home-screen name comes from `CFBundleDisplayName` in
   `project.yml`.)
5. **API key.** App Store Connect → Users and Access → Integrations →
   App Store Connect API (first time: Request Access) → Team Keys → **+**,
   name `GitHub Actions`, role **App Manager**. Download the `.p8` (only
   offered once) and note the Key ID and the Issuer ID.
6. **GitHub secrets** (repo → Settings → Secrets and variables → Actions →
   New repository secret). On the Mac, `pbcopy` puts each value on the
   clipboard, ready to paste:

   ```sh
   cd ~/BikeComputerSigning
   base64 -i distribution.p12 | pbcopy                # BUILD_CERTIFICATE_BASE64
   base64 -i *.mobileprovision | pbcopy               # PROVISIONING_PROFILE_BASE64
   pbcopy < ~/Downloads/AuthKey_*.p8                  # ASC_KEY_P8
   ```

   In Git Bash on Windows, `clip` does the same:

   ```sh
   cd ~/BikeComputerSigning
   base64 -w 0 distribution.p12 | clip                # BUILD_CERTIFICATE_BASE64
   base64 -w 0 *.mobileprovision | clip               # PROVISIONING_PROFILE_BASE64
   cat AuthKey_*.p8 | clip                            # ASC_KEY_P8
   ```

   Only one `.mobileprovision` may be in the folder. The TestFlight
   workflow's first step checks every secret and names any that's wrong,
   without printing values.

   | Secret | Contents |
   |---|---|
   | `APPLE_TEAM_ID` | from Phase 0 |
   | `BUILD_CERTIFICATE_BASE64` | the `.p12`, base64-encoded |
   | `P12_PASSWORD` | its password |
   | `PROVISIONING_PROFILE_BASE64` | the `.mobileprovision`, base64-encoded |
   | `ASC_KEY_ID` | Key ID from step 5 |
   | `ASC_ISSUER_ID` | Issuer ID from step 5 |
   | `ASC_KEY_P8` | contents of the `.p8` file |

7. **Workflow (done; first upload, build 4.1, on 12 Oct 2026).**
   `.github/workflows/testflight.yml`: on push to `main` (and on demand),
   check the secrets, archive, sign with the secrets above, upload with
   `xcrun altool` and the API key. Until every secret exists, runs finish
   early with a notice. The build number is the run number.
8. **First upload.** GitHub → Actions → TestFlight → **Run workflow**. The
   log prints the signing identity and the profile's App ID and expiry,
   which is where to look if signing fails. After Apple's processing
   (~5–15 min): App Store Connect → the app → TestFlight → Internal Testing
   → **+** a group, add yourself, turn on automatic distribution. Then
   install from the TestFlight app on the iPhone.

Secrets never go into the repo; they live only in GitHub's encrypted
secrets and on Remy's computer.

## Phase 4 — First hardware check (Remy with the phone, Claude on call)

The app has a **Debug log** (Settings → Debug log, done): raw power-meter
packets with their decoded fields, heart-rate samples with their lag, GPS
accuracy and speed (no coordinates), one line per recorded second, and
every Bluetooth, HealthKit and location state change. The share button
sends the log files (one per day, kept 7 days; also in the Files app under
Raggio → Logs).

- [ ] Install from TestFlight. Grant Bluetooth, Location and Health
      permissions when asked.
- [ ] Sensors → spin the cranks → Scan → pick the Assiomas. Power, cadence,
      L/R balance and battery show up.
- [ ] One AirPod Pro 3 in → Start. Heart rate appears within ~30 s.
- [ ] Lock the phone for two minutes, unlock: heart rate and GPS kept going.
- [ ] ActiveLook glasses on, ENGO app closed → Sensors → Scan for glasses →
      pick them. Power and heart rate on two big lines, speed and cadence
      below, updating every second; still updating with the phone locked.
- [ ] Anything wrong: Settings → Debug log → Share, send it to Claude, get
      a fix, next TestFlight build (~15 min per round).

## Phase 5 — Test rides and tuning (a few rides)

- [ ] Ride with the app and the current setup (Cadence app / head unit) in
      parallel. Compare distance, climbing, average power, NP, heart rate.
- [ ] Check the Apple Health workout: route on the map, power, cadence,
      distance present and not doubled.
- [ ] Add the Intervals.icu API key under Settings, save a ride: it uploads
      by itself (History shows a ✓ cloud and opens it in Intervals.icu) and
      appears on remymargerum.com/cycling after the next hourly sync. Also
      try finishing a ride in airplane mode: it should upload when you next
      open the app with signal.
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
