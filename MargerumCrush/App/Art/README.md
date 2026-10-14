# Artwork

The game can draw everything itself, so none of these files is required.
A file with one of these exact names in this folder replaces the drawn
version; push it and that's all (`xcodegen` bundles whatever is here). The
art in the repo now came from OpenRouter (Gemini 3 Pro Image), cut out onto
transparent backgrounds, except the bottle labels, which are Margerum's
real front labels.

Big backdrops can be JPEG: the game looks for `Name.png` first, then
`Name.jpg`. Everything with a transparent background has to be PNG.

## Backdrops

| File | Size (px) | What |
|---|---|---|
| `Title.jpg` | 1290×2796, portrait | Title screen. Keep the top third fairly plain: the title sits there |
| `Vineyard.jpg` | 1290×2796, portrait | Picking game backdrop: sky and hills. Trellis wires are drawn on top |
| `WineryFloor.jpg` | 1180×1759 (9 by 13.4 m) | The winery floor, seen from above at an angle: back wall at the top, roll-up door at the bottom. No machines: they're separate sprites |

## The picking game

Bunches are shown about 66×88 points: 360×480 pixels, transparent, stem at
the top center, a little margin all round. Red and white versions where the
grape color matters.

| File | What |
|---|---|
| `ClusterRed.png`, `ClusterWhite.png` | Ripe, sunny bunch on a brown, woody stem |
| `ClusterRedGreenStem.png`, `ClusterWhiteGreenStem.png` | Colored berries on a bright green stem: not really ripe |
| `ClusterRedShaded.png`, `ClusterWhiteShaded.png` | From inside the canopy: paler, greener berries |
| `ClusterSecondCrop.png` | A small, hard second-crop bunch from a side shoot |
| `ClusterRedShot.png`, `ClusterWhiteShot.png` | "Hens and chicks": big and tiny berries mixed |
| `ClusterRedRaisin.png`, `ClusterWhiteRaisin.png` | Sunburned and shriveled |
| `ClusterRotten.png` | Gray, fuzzy mold (botrytis) |
| `ClusterSour.png` | Sour rot: brown, split and leaking |
| `ClusterGolden.png` | Doug's perfect bunch, with a gold shine |
| `Leaf.png`, `Cane.png` | A vine leaf and a piece of cane, 320×320 |
| `Wasp.png` | 240×240, facing right (flipped when it flies left) |

## The winery floor

Each machine is drawn as wide as its footprint on the floor (2 to 3.6 m,
which is about 85 to 155 points on a phone), standing on the footprint's
front edge; its height follows from the picture. Shoot them from the same
three-quarter view as the floor, about 560 px wide, transparent.

| File | What |
|---|---|
| `Bins.png` | Picking bins full of grapes |
| `Destemmer.png` | Destemmer-crusher with its hopper |
| `Press.png` | Bladder press |
| `Fermenter.png` | Open-top red fermenter, with the cap of skins showing |
| `SteelTank.png` | Jacketed stainless steel tank |
| `Barrels.png` | Neutral oak barrels on racks |
| `NewBarrels.png` | New French oak barrels, pale wood |
| `Chiller.png` | Glycol chiller |
| `LabBench.png` | Lab bench with glassware and a yeast jar |

Doug is about 2 m tall on the floor (about 88 points). Every pose is
300×440, transparent, feet at the same spot near the bottom, the same size
in every file so the frames line up.

| File | What |
|---|---|
| `DougFront.png`, `DougFrontWalk1.png`, `DougFrontWalk2.png` | Walking down the screen, standing and two strides |
| `DougBack.png`, `DougBackWalk1.png`, `DougBackWalk2.png` | Walking up the screen |
| `DougSide.png`, `DougSideWalk1.png`, `DougSideWalk2.png` | Walking right (flipped for left) |
| `DougPunch.png` | Punching down the cap with a plunger |
| `DougValve.png` | Working a valve or a machine |
| `DougTaste.png` | Tasting from a glass |

## Bottles

| File | Size (px) | What |
|---|---|---|
| `LabelSybarite.png` | 640×810 | Sybarite front label |
| `LabelRose.png` | 640×810 | Riviera Rosé front label |
| `LabelM5.png` | 640×810 | M5 front label |
| `LabelUber.png` | 640×810 | ÜBER Syrah front label |

Labels are cropped to fill the label area on the bottle (about 0.79 wide
for 1 tall). The game prints the vintage in words across the top (TWO
THOUSAND AND ONE), so leave the label's own year off or covered.

## App icon

Separate from this folder: replace
`../Assets.xcassets/AppIcon.appiconset/AppIcon.png` (1024×1024, no
transparency, square corners; iOS rounds them).
