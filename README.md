# Koolertron Configurator

## A community-made Mac replacement option for Koolertron's original programmer

If Koolertron's original Mac programming software no longer works on your Mac, Koolertron Configurator is a community-made replacement option for programming the Koolertron ps2avrGB keypad. It is independent and not affiliated with Koolertron. It does not require modifying the keypad.

## Version 0.7.0

Version 0.7.0 adds a full macro draft workflow: create and edit macro sequences, keep drafts in local profiles, review configuration changes, and use the configuration-only upload workflow to write supported configuration pages. No firmware replacement or device reset is part of this workflow.

This is a replacement option, not a claim of complete parity with Koolertron's original software. Compatibility work targets the ps2avrGB keypad (USB ID 20A0:422D) with firmware 1.5.0 on macOS 14 or later and Apple silicon. Physical testing verified one Normal-layer key mapping (top-left key to A), persistence after reconnect, and restoration of the prior configuration. Macro upload has not been physically validated. Treat macro upload as experimental and keep a backup before using it. Unsupported layers and firmware are not covered.

The final macro page includes 32 bytes that the normal macro read does not expose. Upload handling preserves the documented 0xFF padding behavior; this area has not been verified on physical hardware.

## Download

Get the versioned source archive, SHA-256 checksum, and illustrated user manual from the [v0.7.0 pre-release](https://github.com/CellularDeath/Koolertron-Configurator/releases/tag/v0.7.0). Use the attached Koolertron-Configurator-0.7.0-source.zip as the complete v0.7.0 source package. GitHub's automatically generated source links on the release page may reflect an earlier repository snapshot. There is no signed or notarized app download.

[Download the v0.7.0 user manual (PDF)](https://github.com/CellularDeath/Koolertron-Configurator/releases/download/v0.7.0/Koolertron-Configurator-User-Manual-v0.7.pdf)

## Build from source

Install Apple's Command Line Tools. Download and expand the v0.7.0 source archive, open the extracted project folder in Terminal, and run:

    ./script/build_and_run.sh

The app is ad-hoc signed and opens locally. It stores private drafts and recovery files under ~/Library/Application Support/Koolertron Configurator/. Profiles can contain private macro data; do not publish them. Automated tests use simulated device I/O and do not program a keypad.

## License

MIT. This community project is not affiliated with Koolertron.
