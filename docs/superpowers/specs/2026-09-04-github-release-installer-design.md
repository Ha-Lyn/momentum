# GitHub Release Installer Design

## Goal

Provide a simple installation path for non-technical users while keeping
release publication under the maintainer's control. A maintainer should be
able to build and publish a signed Momentum application manually, and a
friend should be able to install the latest published application with one
`curl` command.

## Scope

This change applies to the native Swift macOS application. The Electron
prototype is not part of the release pipeline.

### Maintainer workflow

Add `native/scripts/publish-release.sh VERSION`.

The script will:

1. Validate a semantic version argument.
2. Require the GitHub CLI and an authenticated account.
3. Update the native bundle version for the build without permanently
   modifying the source metadata.
4. Build the native app in Release configuration.
5. Sign the app with an explicitly provided or auto-detected Apple
   Development/Developer ID identity.
6. Refuse to publish an unsigned app unless an explicit override is supplied.
7. Create a ZIP archive and SHA-256 checksum.
8. Create a GitHub Release tagged `vVERSION`.
9. Upload the archive and checksum as release assets.
10. Print the stable installer command.

The release script will support `CODESIGN_IDENTITY` for selecting a signing
identity and will preserve the existing bundle identifier
`com.momentum.native`, which is needed for macOS permission association.

### Friend workflow

Add a stable root-level `scripts/install.sh`, invoked with:

```bash
curl -fsSL https://raw.githubusercontent.com/Ha-Lyn/momentum/main/scripts/install.sh | bash
```

The installer will:

1. Verify that it is running on macOS 15 or newer.
2. Resolve the latest GitHub Release for the repository.
3. Download the release ZIP and checksum.
4. Verify the archive checksum before installation.
5. Refuse to remove a currently running Momentum instance.
6. Replace `/Applications/Momentum.app`.
7. Remove the download quarantine attribute from the installed app.
8. Launch Momentum so macOS can request microphone and system-audio access.
9. Print clear next steps if macOS requires manual approval.

The installer will use only standard macOS tools plus `curl`, `ditto`,
`shasum`, and `xattr`; it will not require Swift, Xcode, Node.js, or GitHub
CLI on the friend's machine.

### Documentation

Update the project README with:

- Maintainer prerequisites and authentication setup.
- Manual release publication instructions.
- Friend installation instructions.
- Upgrade and uninstall instructions.
- The limitations of Apple Development signing with a free Apple Developer
  account.
- Microphone and system-audio permission requirements.

## Error handling

Both scripts will use strict shell options and fail before destructive actions
when prerequisites, architecture, downloads, checksums, signing, or release
creation fail. The installer will download into a temporary directory and
clean it up on exit. Existing installations will remain untouched if a new
archive cannot be verified.

The installer will not silently grant privacy permissions or bypass macOS
security prompts beyond removing the quarantine attribute applied to the
downloaded archive. The user may still need to approve the app in System
Settings because a free Apple Developer account does not provide Developer ID
distribution or notarization.

## Verification

The implementation will verify:

- Release builds succeed from a clean native build state.
- The generated application has the expected bundle identifier, version, and
  executable.
- ZIP creation and checksum verification succeed.
- The release script performs prerequisite and signing checks before upload.
- The installer rejects unsupported macOS versions and checksum mismatches.
- The installer installs into `/Applications` and launches the app.
- Documentation commands match the actual script locations and options.

## Non-goals

- GitHub Actions or automatic publication.
- Developer ID certificate management or notarization.
- A DMG installer.
- Automatic granting of microphone or system-audio permissions.
- Building the application on the friend's machine.
