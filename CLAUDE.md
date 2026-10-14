# personal-cycling

Personal iPhone cycling app (SwiftUI, iOS 26+). See README.md for what it
records and how, and PLAN.md for the phased plan and what's next.

- `RideKit/` is a pure Swift package: `cd RideKit && swift test` works on
  Linux. Keep anything testable there.
- `BikeComputer/` is the iOS app. It can't be compiled on Linux (no iOS
  SDK); `swiftc -parse` catches syntax errors only. Real compile checks
  come from the macOS job in `.github/workflows/ci.yml`, which runs on
  every push.
- `project.yml` generates the Xcode project with `xcodegen`; the generated
  `.xcodeproj`, `Info.plist` and entitlements are gitignored.
- `MargerumCrush/` is a second, separate app (a winery game). It has its own
  `project.yml` (run `xcodegen` inside that folder), its own pure Swift
  package (`cd MargerumCrush/CrushKit && swift test` works on Linux; keep
  the game rules there) and `testflight-crush.yml`. See its README.
- Signing keys and API keys never go in the repo (GitHub secrets only).
- Update the checkboxes in PLAN.md as phases complete.
