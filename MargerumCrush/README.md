# Margerum Crush (iOS)

A harvest-and-blending game for iPhone. You run the winery for one vintage
at a time: watch the fruit ripen through a Santa Barbara County harvest,
send crews to pick, decide what each lot becomes on the crush pad, blend
Sybarite, rosé, M5 and ÜBER Syrah for the critic, and spend the profits on
more vineyard blocks and better gear. The goal is five stars and a
100-point M5.

It lives in this repo next to Raggio but is a separate app (bundle ID
`com.remymargerum.margerumcrush`, home-screen name **Margerum**) with its
own Xcode project spec, package, CI jobs and TestFlight workflow. The wine
names are real; the prices, scores and vineyard numbers are made up for
the game.

## How a vintage plays

1. **Harvest** (12 five-day weeks, Aug 25 to Oct 19). Each block shows its
   sugar (°Brix), acid and mold, and a gauge with the picking window: green
   for red or white wine, pink for rosé. Sun ripens, heat waves spike sugar
   and burn acid, fog slows things down, rain dilutes and spreads mold, and
   October gets wetter. The forecast is right about 3 times in 4. One crew
   picks one block a week; whatever is still hanging after Oct 19 is lost.
2. **Picking.** A 30-second tapping game on the trellis. Tap ripe bunches,
   leave green and moldy ones (they end up in the wine), grab the rare gold
   ones, and don't swat the wasps (−3 s). Picking about three bunches in
   four brings in the whole crop. Early picks have more green bunches; rain
   brings more mold.
3. **Crush pad.** Stainless steel, neutral oak or (once bought) new French
   oak. Red grapes can go all red or *saignée*, which bleeds 20% off as rosé
   and concentrates the red. Grapes picked for rosé go straight to steel.
4. **Blending lab.** Sliders for each lot, a live taste chart against the
   critic's style (gold bands), the blend's color, alcohol and an estimated
   score. Rules follow the labels: Sybarite and ÜBER need 75% of their
   grape, M5 needs all five (Syrah, Grenache, Mourvèdre, Counoise,
   Cinsault), and more grapes in a blend score a little higher.
5. **Release.** The critic scores each wine (±1 for mood) with a tasting
   note. Scores and reputation set prices; unbottled wine sells in bulk;
   the season's costs are paid.
6. **Winter.** Lease the Cinsault, Counoise and Mourvèdre blocks (needed for
   M5) and a cool-climate Syrah block; hire more crews; buy a sorting table,
   a weather station, new French oak and a tasting room.

## Layout

```
  MargerumCrush/
    project.yml                XcodeGen spec (generates MargerumCrush.xcodeproj)
    Config/Signing.xcconfig    signing for the app target (CI overrides it)
    CrushKit/                  Swift package, no iOS dependencies, unit-tested
      Basics                   seeded random numbers, colors, taste profiles
      Varietal                 the six grapes: windows, ripening, flavor
      Vineyard                 calendar, weather, vineyard blocks
      Picking                  the picking game (clock, spawns, taps, scoring)
      Cellar                   fruit quality, vessels, saignée, lots
      Wines                    the four wines, blend analysis, tasting notes
      Game                     the whole game state, upgrades, the money
    App/                       the iOS app (SwiftUI)
      GameStore                holds the game and saves it after every move
      Views/                   title, harvest, picking, crush pad, cellar,
                               blending lab, review, winter, library, drawings
      Art/                     optional artwork (see Art/README.md)
    UITests/TourTests          the screenshot tour (below)
```

All the rules are in CrushKit, so they're tested without a phone:

```
cd MargerumCrush/CrushKit && swift test
```

`BalanceTests` plays five vintages with a simulated casual player and an
expert, a dozen times each, and prints average scores and profits. Run it
after changing any numbers: windows and ripening in `Varietal.swift`,
quality in `Cellar.swift`, styles and scoring in `Wines.swift`, prices and
upgrade costs in `Game.swift`.

## Screenshots

`.github/workflows/screenshots-crush.yml` plays a short first vintage in the
iPhone simulator (`UITests/TourTests.swift`) on every push that touches the
game: it picks two blocks (the app picks for itself when launched with
`-autopick`, since UI tests can't keep up), bottles Sybarite and a rosé and
releases them. A
screenshot of each screen lands in the run's **screenshots** artifact
(GitHub → Actions → the run → Artifacts). It's a quick way to see a change
without a phone, and a check that the game still plays from start to finish.

## Artwork

Everything is drawn in code, so the game works with no image files. PNGs
with the names listed in [App/Art/README.md](App/Art/README.md) (title
screen, vineyard backdrop, grape bunches, wasp, bottle labels) replace the
drawn versions with no code changes.

## Getting it on the iPhone (TestFlight)

The same route as Raggio: GitHub Actions signs the app and uploads it, and
the TestFlight app installs it. `.github/workflows/testflight-crush.yml`
reuses Raggio's signing secrets (one distribution certificate and one App
Store Connect API key cover every app on the team), so the game needs only
three things set up once, plus one new secret.

- [ ] **App ID.** developer.apple.com → Certificates, Identifiers & Profiles
      → Identifiers → **+** → App IDs → App. Description `Margerum Crush`,
      Bundle ID **Explicit** `com.remymargerum.margerumcrush`. No
      capabilities needed. Register.
- [ ] **Provisioning profile.** Profiles → **+** → Distribution: **App
      Store Connect** → the new App ID → the same Apple Distribution
      certificate Raggio uses → name it `Margerum Crush App Store` →
      download it into `~/BikeComputerSigning`.
- [ ] **App record.** App Store Connect → Apps → **+** → New App: iOS, the
      bundle ID above, SKU `margerumcrush`, name **Margerum Crush** (it has
      to be unique on the App Store even though it's never published; add a
      word if it's taken).
- [ ] **GitHub secret** `CRUSH_PROVISIONING_PROFILE_BASE64`: the profile,
      base64-encoded. In Git Bash on Windows:

      ```sh
      base64 -w 0 ~/BikeComputerSigning/Margerum_Crush_App_Store.mobileprovision | clip
      ```

      On a Mac, `base64 -i <file> | pbcopy`. (Use the file's real name;
      Apple names the download after the profile.)
- [ ] **First upload.** After this branch is merged: GitHub → Actions →
      **TestFlight (Margerum Crush)** → **Run workflow**. After Apple's
      processing (~5–15 min): App Store Connect → the app → TestFlight →
      Internal Testing → **+** a group, add yourself (and anyone else on
      the team who wants to play), turn on automatic distribution. Install
      from the TestFlight app.

After that, every push to `main` that touches `MargerumCrush/` uploads a
new build. Until the secret exists, the workflow finishes early with a
notice instead of failing.

With a Mac and Xcode 26 instead: `brew install xcodegen`, run `xcodegen`
in `MargerumCrush/`, open `MargerumCrush.xcodeproj`, pick your team under
**Signing & Capabilities** and run it on the phone or the simulator.

## Ideas

- Sound: snips, the crusher, a cork.
- Real label artwork and photos (see `App/Art/`).
- More wines from the same grapes, such as a vineyard-designate Syrah.
- Events: a September heat spike, wildfire smoke, birds, frost-shortened
  crops.
- Game Center leaderboards for best M5 and pick points.
