# Koolertron Configurator

## A community-made Mac replacement option for Koolertron’s original programmer

If the original Mac programming software no longer works on your Mac, this independent app offers another way to program the Koolertron ps2avrGB keypad. It is not affiliated with Koolertron and does not require modifying the keypad.

## Version 0.8.0

Edit Normal, FN, FN2 and FN3 assignments, choose layer switches, draft macros, and review configuration-only uploads. A private recovery record and full readback help protect existing settings.

One FN hold combination was physically tested before and after reconnect and the original configuration restored. The first restoration attempt did not observe the bootloader; a separately approved restoration succeeded. FN2/FN3, multi-page layer uploads, and macro uploads have not been physically validated. The final macro page pads 32 unread bytes with 0xFF. Keep a private backup and treat these features as experimental.

Compatible target: ps2avrGB USB 20A0:422D, firmware 1.5.0; macOS 14 or later; Apple silicon. Other models and firmware are not established as compatible.

## Download

Get the complete source archive, checksum, and illustrated manual from the [0.8.0 pre-release](https://github.com/CellularDeath/Koolertron-Configurator/releases/tag/v0.8.0). Use the attached Koolertron-Configurator-0.8.0-source.zip. GitHub’s automatically generated Source code archives come from an older repository snapshot and do not include the complete 0.8.0 source.

[Download the 0.8 manual (PDF)](https://github.com/CellularDeath/Koolertron-Configurator/releases/download/v0.8.0/Koolertron-Configurator-User-Manual-v0.8.pdf)

## Build

Install Apple’s Command Line Tools, expand the attached source archive, open its project folder in Terminal, and run:

    ./script/build_and_run.sh

There is no prebuilt notarized app. The locally built app is ad-hoc signed. Profiles and backups may contain private macro data; do not publish them.

MIT license.
