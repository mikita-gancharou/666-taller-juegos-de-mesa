# SeiSeiSeis!

Turn-based strategy game with cards and three dice. You play against two bots.
Godot 4.7 prototype for Windows and Android.

## Goal

Be the first to have all three of your dice showing 6 at the same time.

## How it plays

- Everyone starts with three dice on 3 and three cards.
- Each turn you have 2 actions (3 while you own a locked 6): draw a card from the market or play a card.
- A die that reaches 6 is locked. Only effect cards can change it.
- Cards raise your dice, lower a rival's dice, or roll the demonic die (-3 to +3).

Full rules: RULES button in the game.

## Android

[builds/SeiSeiSeis.apk](builds/SeiSeiSeis.apk): arm64, Android 7.0 or newer, signed with a debug key. A tap works as a click.

## Run from source

Open `666-godot/` in Godot 4.7.2 and press F5.

- Export presets: `Windows Desktop` and `Android` (no Gradle, arm64-v8a).
- Tests: `godot --headless --path 666-godot res://tests/run_tests.tscn`

## Other files

- `666-reglas.html`, `666-cartas.html`: rules and print-and-play cards of the tabletop version.
- `design/`: rules drafts, analysis and a simulator.
- `index.html`, `img/`, `actividad_componentes_arte.md`: earlier art and component work, in Spanish.
