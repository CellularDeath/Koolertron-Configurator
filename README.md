# Koolertron Configurator

An independent macOS configurator for the Koolertron ps2avrGB keypad (USB 20A0:422D, firmware 1.5.0). Not affiliated with Koolertron.

**macOS 14 or later · Apple silicon · MIT license**

## Download

Get the source archive, checksum, and illustrated manual from the [v0.3.0 pre-release](https://github.com/CellularDeath/Koolertron-Configurator/releases/tag/v0.3.0). There is no signed or notarized app download; build from source on your Mac.

## Build

Install Apple's Command Line Tools, then clone this repository and run:

```sh
./script/build_and_run.sh
```

The app is ad-hoc signed and opens locally. It stores private drafts and recovery files under `~/Library/Application Support/Koolertron Configurator/`. Profiles can contain private macro data.

## What works

Version 0.3 supports ordinary key assignments and existing stored-macro references on the **Normal** layer. Upload reviews each change, saves recovery state, writes the configuration page, and compares readback. The app does not capture global keyboard input.

Only ps2avrGB USB ID 20A0:422D with firmware 1.5.0 is established as compatible. FN/FN2/FN3 are inspection-only. New macros, shortcut/modifier recording, multimedia assignments, and other-layer uploads are not implemented. Physical validation covered only the top-left key and the A output. An initial readback mismatch occurred; its cause remains unknown, and the writer stops on any mismatch.

See the release notes and manual for the recovery boundaries and feature details. Tests use simulated device I/O and do not program a keypad.
