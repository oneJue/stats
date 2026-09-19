# Stats 3.1.0 (oneJue custom)

This release preserves the custom **Keep screen awake** and **Prevent sleep on lid close** controls and incorporates upstream changes through `aab2e1b55b1385665955a842635fe7654fc1e438` (v3.0.16 plus subsequent fixes).

- Fix chart crashes caused by invalid history or non-finite samples, repeated connectivity checks leaking sockets, and malformed GPU/network input handling.
- Correct battery health exceeding 100%, NVMe temperature overflow, sensor settings visibility, and remote popup sizing.
- Reduce repeated Bluetooth subprocesses, process icon lookups, formatter creation, widget text measurement, and synchronous redraws.
- Include the GPU text widget, newer platform sensors, and updated translations.
- Restore the original sleep setting before helper replacement and wait for unregistration to finish before reinstalling it.
- Check for future releases in `oneJue/stats`, preserving the custom functionality.
- Do not offer identical or older beta builds as updates.

The installer supports Apple Silicon and Intel Macs running macOS 12 or newer. On macOS 26, enable Stats in System Settings > Menu Bar if its icons are hidden. Lid sleep prevention requires approval of the Stats background helper under System Settings > General > Login Items & Extensions.

The unsigned CI archive is a build artifact, not the signed installer. Ad-hoc signatures do not satisfy the privileged helper's certificate checks. Only a successfully signed and notarized `Stats.dmg` is published by the release workflow.
