# Margerum Crush (iOS)

A harvest-and-blending game for iPhone. You run the winery one vintage
at a time, starting with Margerum's first, 2001: watch the fruit ripen
through a Santa Barbara County harvest, pick it bunch by bunch, make the
wine as Doug on the winery floor, age it through the winter, blend
Sybarite, rosé, M5 and ÜBER Syrah to Doug's range, and spend the profits
on more vineyard blocks and better gear. The goal is five stars and a
100-point M5.

It lives in this repo next to Raggio but is a separate app (bundle ID
`com.remymargerum.margerumcrush`, home-screen name **Margerum**) with its
own Xcode project spec, package, CI jobs and TestFlight workflow. The wine
names and labels are real; the prices, scores and vineyard numbers are
made up for the game.

## How a vintage plays

1. **Harvest** (12 five-day weeks, Aug 25 to Oct 19). Each block shows its
   sugar (°Brix), acid and mold, and a gauge with the picking window: green
   for red or white wine, pink for rosé. Sun ripens, heat waves spike sugar
   and burn acid, fog slows things down, rain dilutes and spreads mold, and
   October gets wetter. The forecast is right about 3 times in 4. One crew
   picks one block a week; whatever is still hanging after Oct 19 is lost.
2. **Picking.** A 30-second tapping game on the trellis, and every bunch
   changes the wine. Sunny bunches on brown stems bring sugar, color and
   ripe tannin; green-stemmed and shaded ones bring acid and green
   character (a little suits Sybarite); second-crop bunches from side
   shoots are weeks behind, sour and green; hens and chicks add color,
   tannin and complexity; raisined bunches push the sugar up and burn the
   color; gray mold and sour rot are faults (and vinegar); and Doug's
   perfect bunch is pure complexity. Leaves and canes get grabbed
   too, and make the wine bitter and stemmy. Meters show the bins' sugar
   and acid against what the wine needs, with tannin, green, complexity and
   leaves alongside. Early blocks have more green and wing bunches, late
   ones more raisins, and rain brings rot, so sorting is how you rescue a
   pick that's early or late. Picking about seven bunches in ten brings in
   the whole crop; skipping makes less wine, but better. Don't swat the
   wasps (−3 s). Or **let the crew pick it**: they bring in the whole crop
   and the odd bad bunch, and don't sort.
3. **Doug's crush.** A briefing says what this fruit needs and when, then
   you either **make it with Doug** or leave it to the cellar crew (decent,
   never inspired). With Doug, you tap a machine and he walks over and
   works it (or steer him with the thumb stick and the big button), doing
   each job at its moment, against a clock
   that runs slow at the press and fast through the fermentation:
   - white: whole clusters into the press, and stop it before the bitter
     press juice; settle the juice cold, add the yeast, keep it cool;
   - rosé: crush into the press and press at pale salmon, a few hours
     later (sooner for dark, ripe or warm grapes);
   - red: destem (or keep a third whole clusters: spice and structure if
     the stems are brown, stalky if they're green), cold soak, bleed off
     pink juice for saignée if you like, add the yeast, punch down the cap
     before it dries out (vinegar), run the chiller to stay under 32 °C,
     leave it on the skins after it's dry (days for ripe Syrah, hours for
     Grenache), press, and barrel down.

   Barrel-down has sliders to share the wine out between steel tanks,
   neutral barrels and new French oak; each becomes its own lot to blend
   later. Doug's notes say where to aim for each wine the grape might go
   into: a hunch at first, a range after a vintage of that wine is bottled,
   and close to exact after three, with word on whether last time's oak
   came up short or ran over.

   Every window moves with how ripe and how warm the fruit came in. The
   results screen lists what went right and wrong.
4. **The cellar** (November to July). Doug walks the barrel room month by
   month: top up the barrels every couple of months or they oxidize, and
   bottle each wine when it tastes best, in as many bottlings as you like.
   Whites and rosé want a couple of months to settle and fade by summer;
   reds want about five in barrel, softening as new oak builds. Bottled
   sooner, a wine tastes raw. The lab bench shows the blend now and a month
   from now.
5. **Blending.** Sliders for each lot, a live taste chart against Doug's
   range (gold bands), the blend's color, alcohol and an estimated score.
   Any lot in the cellar can go in, within the label rules: 85% the wine's
   color and 85% from one vintage (the year on the label). Sybarite and ÜBER
   need 75% of their grape, M5 needs all five (Syrah, Grenache, Mourvèdre,
   Counoise, Cinsault), and more grapes in a blend score a little higher.
6. **Release** in August. The critic scores each wine (±1 for mood) with a
   tasting note. Scores and reputation set prices, and the season's costs
   are paid. Unbottled wine stays in barrel for another year ($6 a case),
   aging on (reds soften, whites and rosé fade), unless you sell a lot off
   in bulk; wine that's had its extra year goes for bulk at the next
   release.
7. **Winter.** Lease the Cinsault, Counoise and Mourvèdre blocks (needed for
   M5) and a cool-climate Syrah block; hire more crews; buy a sorting table
   (pulls out rot, leaves and canes), a weather station, new French oak and
   a tasting room.

## Where the numbers come from

The rules are a game, but the numbers lean on research and on Margerum's
own records:

- **Bunches:** shaded fruit runs 1–2 °Brix lower and 1–2 g/L higher in
  acid; second crop sets 6–8 weeks behind; hens-and-chicks berries are
  sweeter with more skin; raisins concentrate sugar while heat burns color;
  gray mold adds sugar and earthy notes; sour rot carries vinegar (about
  2.4 g/L).
- **Leaves and stems:** wineries reject loads with about 3% leaves and
  canes. Brown, lignified stems fermented as whole clusters add tannin and
  spice (Syrah most), while green ones are stalky.
- **Crush timings:** pale salmon comes in an hour or two for Syrah and
  three or four for Grenache, twice as fast for every 10 °C warmer; cold
  settling takes most of a day; saignée bleeds about 20% right after the
  crush.
- **Doug's range and the picking windows** follow the Margerum tech
  sheets: Sybarite picked "just approaching ripeness" for about 12.5%
  alcohol; Riviera Rosé from Grenache picked earlier still; M5 mostly in
  neutral barrels; ÜBER Syrah as fresh in acid as M5.

One deliberate departure: real 1.5-ton open-top bins peak around
26–30 °C, but the game's fermenters run hotter so the chiller stays part
of Doug's job.

## Layout

```
  MargerumCrush/
    project.yml                XcodeGen spec (generates MargerumCrush.xcodeproj)
    Config/Signing.xcconfig    signing for the app target (CI overrides it)
    CrushKit/                  Swift package, no iOS dependencies, unit-tested
      Basics                   seeded random numbers, colors, taste profiles
      Varietal                 the six grapes: windows, ripening, flavor
      Vineyard                 calendar, weather, vineyard blocks
      Picking                  the picking game: bunch kinds, the bins, taps
      Cellar                   fruit quality, vessels, saignée, lots
      Floor                    the winery floor, Doug walking it, paths
      Winemaking               Doug's crush in real time, and its results
      CrushPlan                when to do what: the crew and the autopilot
      Aging                    the cellar months: oak, tannin, fruit
      Wines                    the four wines, Doug's range, tasting notes
      Game                     the whole game state, upgrades, the money
    App/                       the iOS app (SwiftUI)
      GameStore                holds the game and saves it after every move
      Views/                   title, harvest, picking, Doug's crush (floor,
                               briefing, results), barrel room, crush pad,
                               cellar, blending lab, review, winter, library
      Art/                     the artwork (see Art/README.md)
    UITests/TourTests          the screenshot tour (below)
```

All the rules are in CrushKit, so they're tested without a phone:

```
cd MargerumCrush/CrushKit && swift test
```

`BalanceTests` plays five vintages with two simulated players, a dozen
times each, and prints average scores, bottling months and profits: a
casual player (picks whatever's ripe, leaves the crush to the crew,
bottles everything in February) and an expert (waits for the middle of
the window, sorts the bunches, plays Doug's crush well, bottles each wine
in its best month). Run it after changing any numbers: windows and
ripening in `Varietal.swift`, bunches in `Picking.swift`, quality in
`Cellar.swift`, the crush in `Winemaking.swift`, aging in `Aging.swift`,
Doug's range and scoring in `Wines.swift`, prices and upgrade costs in
`Game.swift`.

## Screenshots

`.github/workflows/screenshots-crush.yml` plays a short first vintage in the
iPhone simulator (`UITests/TourTests.swift`) on every push that touches the
game: it picks the Sauvignon Blanc (the app plays the fast parts itself when
launched with `-autopick`, since UI tests can't keep up) and lets Doug make
it on the winery floor, has the crew pick and make a rosé, walks the barrel
room, bottles Sybarite and the rosé and releases them. A screenshot of each screen
lands in the run's **screenshots** artifact (GitHub → Actions → the run →
Artifacts). It's a quick way to see a change without a phone, and a check
that the game still plays from start to finish.

## Artwork

The title screen, vineyard, bunches, leaves, wasp, winery floor, machines
and Doug were made with OpenRouter (Gemini 3 Pro Image); the bottle labels
are Margerum's real front labels, with the game spelling out the vintage.
Every image is optional: the game draws its own version of anything
missing. [App/Art/README.md](App/Art/README.md) lists the files and sizes.

## Getting it on the iPhone (TestFlight)

The same route as Raggio: GitHub Actions signs the app and uploads it, and
the TestFlight app installs it. `.github/workflows/testflight-crush.yml`
reuses Raggio's signing secrets (one distribution certificate and one App
Store Connect API key cover every app on the team), so the game needs only
three things set up once, plus one new secret.

- [x] **App ID.** developer.apple.com → Certificates, Identifiers & Profiles
      → Identifiers → **+** → App IDs → App. Description `Margerum Crush`,
      Bundle ID **Explicit** `com.remymargerum.margerumcrush`. No
      capabilities needed. Register.
- [ ] **Provisioning profile.** Profiles → **+** → Distribution: **App
      Store Connect** → the new App ID → the same Apple Distribution
      certificate Raggio uses → name it `Margerum Crush App Store` →
      download it into `~/BikeComputerSigning`.
- [x] **App record** (done: name **Margerum**, SKU `margerum`). App Store
      Connect → Apps → **+** → New App: iOS, the bundle ID above, a SKU, and
      a name that's unique on the App Store (even though it's never
      published).
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
- More wines from the same grapes, such as a vineyard-designate Syrah.
- Events: a September heat spike, wildfire smoke, birds, frost-shortened
  crops.
- Game Center leaderboards for the best M5.
