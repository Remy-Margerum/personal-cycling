# personal-cycling

Personal iPhone cycling app (SwiftUI, iOS 26+). See README.md for what it
records and how, and PLAN.md for the phased plan and what's next.

- `RideKit/` is a pure Swift package: `cd RideKit && swift test` works on
  Linux. Keep anything testable there.
- `BikeComputer/` is the iOS app. It can't be compiled on Linux (no iOS
  SDK); `swiftc -parse` catches syntax errors only. Real compile checks
  come from the macOS GitHub Actions job once Phase 2 of PLAN.md is done.
- `project.yml` generates the Xcode project with `xcodegen`; the generated
  `.xcodeproj`, `Info.plist` and entitlements are gitignored.
- Signing keys and API keys never go in the repo (GitHub secrets only).
- Update the checkboxes in PLAN.md as phases complete.
