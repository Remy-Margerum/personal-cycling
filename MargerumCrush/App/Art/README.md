# Artwork

The game draws everything itself, so none of these files are needed. Drop a
PNG with one of these exact names into this folder and push, and the game
uses it instead of the drawn version. Nothing else to change: `xcodegen`
picks up whatever is here.

| File | Size (px) | What |
|---|---|---|
| `Title.png` | 1290×2796, portrait | Title screen. Keep the top third fairly plain: the title sits there |
| `Vineyard.png` | 1290×2796, portrait | Picking game backdrop: sky and hills. Trellis wires and leaves are drawn on top |
| `ClusterRed.png` | ~360×480, transparent | Ripe red grape bunch, stem at the top center |
| `ClusterRedUnripe.png` | ~360×480, transparent | Red grapes before they color (green with a blush of pink) |
| `ClusterWhite.png` | ~360×480, transparent | Ripe Sauvignon Blanc bunch (golden green) |
| `ClusterWhiteUnripe.png` | ~360×480, transparent | Hard, bright-green unripe bunch |
| `ClusterRotten.png` | ~360×480, transparent | Gray, fuzzy, moldy bunch |
| `ClusterGolden.png` | ~360×480, transparent | Shiny gold "perfect" bunch |
| `Wasp.png` | ~240×240, transparent, facing right | The pest (flipped when it flies left) |
| `LabelSybarite.png` | ~600×900, portrait | Front label on the Sybarite bottle |
| `LabelRose.png` | ~600×900, portrait | Front label on the rosé bottle |
| `LabelM5.png` | ~600×900, portrait | Front label on the M5 bottle |
| `LabelUber.png` | ~600×900, portrait | Front label on the ÜBER Syrah bottle |

Clusters are shown about 66×88 points (so 200×264 pixels on a 3× screen is
the minimum); keep the bunch's proportions close to 3:4 and leave a little
transparent margin. Labels are cropped to fill the label area, which is
about 2:3.

The app icon is separate: replace `../Assets.xcassets/AppIcon.appiconset/AppIcon.png`
(1024×1024, no transparency, square corners; iOS rounds them).
