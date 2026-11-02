# Koolertron Configurator

## A community-made Mac alternative to Koolertron's original programmer

If Koolertron's original Mac programming software no longer works on your Mac, this project offers another way to program the ps2avrGB keypad. It is independent and not affiliated with Koolertron.

**Version 0.3 is limited, not a full feature replacement.** It programs ordinary key assignments and references to macros already stored on the keypad, on the Normal layer only. It cannot create macros, program FN/FN2/FN3 layers, record shortcuts or modifiers, assign multimedia keys, or upload other layers.

Compatibility is established only for the ps2avrGB keypad with USB ID 20A0:422D and firmware 1.5.0. Physical validation covered only the top-left key producing A; an initial readback mismatch occurred and its cause remains unknown. The writer stops if readback does not match.

macOS 14 or later · Apple silicon · MIT license

## Download

Get the source archive, SHA-256 checksum, and illustrated manual from the [v0.3.0 pre-release](https://github.com/CellularDeath/Koolertron-Configurator/releases/tag/v0.3.0). There is no signed or notarized app download.

## Build

Install Apple's Command Line Tools, download and expand `Koolertron-Configurator-0.3.0-source.zip`, then open the extracted `Koolertron-public-source-v0.3.0` folder in Terminal and run:

```sh
./script/build_and_run.sh
```

The app is ad-hoc signed and opens locally. It stores private drafts and recovery files under `~/Library/Application Support/Koolertron Configurator/`. Profiles can contain private macro data. Tests use simulated device I/O and do not program a keypad.
