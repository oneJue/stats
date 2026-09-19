# Releasing the custom build

The `build` workflow runs the unit tests and produces a universal unsigned app archive using Xcode 26.6. The `release` workflow repeats the tests, signs the app and its embedded components, notarizes the app and disk image, and publishes `Stats.dmg` plus its SHA-256 checksum.

Configure these repository Actions secrets before running `release`:

| Secret | Value |
| --- | --- |
| `MACOS_CERTIFICATE_P12_BASE64` | Base64-encoded Developer ID Application certificate and private key exported as a password-protected PKCS#12 file |
| `MACOS_CERTIFICATE_PASSWORD` | PKCS#12 export password |
| `MACOS_SIGNING_IDENTITY` | Full Developer ID Application signing identity name |
| `MACOS_TEAM_ID` | Apple Developer team identifier for that identity |
| `APPLE_ID` | Apple account used for notarization |
| `APPLE_APP_PASSWORD` | App-specific password for notarization |

Keep private keys and passwords in Actions secrets, never in the repository or release assets. The runner imports the identity into a temporary keychain and removes it after the job.

Before a release, update the app's `MARKETING_VERSION`, app and widget build numbers, and `RELEASE_NOTES.md`. Run the `release` workflow from the commit to publish, with the matching version (for example `3.1.0`). It creates the `v3.1.0` tag at that commit after verification succeeds. Existing release tags must not be moved.

The app, helper, and SMC tool must share a certificate. The signing team supplied to Xcode also configures the legacy helper authorization requirements and the app/widget preferences group. Do not disable these checks to make an unsigned build control privileged power settings.

After installation, verify screen-awake assertion creation and release, helper approval, and restoration of the original `SleepDisabled` value after disabling lid sleep prevention or quitting Stats. Unit tests use injected power state and do not replace this machine-level verification.
