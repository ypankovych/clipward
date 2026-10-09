# Contributing to Clipward

Thanks for helping out! Bug reports, ideas and pull requests are all welcome.

## Reporting bugs and suggesting features

Use the [issue templates](https://github.com/ypankovych/clipward/issues/new/choose). For bugs,
please include your macOS version, your Mac's chip (Apple silicon or Intel), the Clipward version,
and the steps that reproduce the problem.

Please **don't** report security issues in public issues; see [SECURITY.md](SECURITY.md).

## Development setup

You need the Xcode Command Line Tools (`xcode-select --install`). Xcode is optional; opening
`Package.swift` in Xcode works for editing and code completion.

```sh
Scripts/test.sh          # run the core tests
Scripts/build-app.sh     # build build/Clipward.app
open build/Clipward.app
```

Ad-hoc signed builds get a new signature every time, so macOS asks for Keychain access again after
each rebuild. Signing with a stable identity avoids this (see the README). Alternatively, turn off
*Save history to disk* while developing.

## Guidelines

- **Keep it small and native.** AppKit only, no third-party dependencies, no networking.
- **Keep compatibility.** The app targets macOS 10.13. Guard newer APIs with `#available` and
  provide a fallback. The build compiles the Intel slice for 10.13, so unguarded APIs fail the build.
- **Security comes first.** Nothing may be written to disk unencrypted, and confidential pasteboard
  types must stay ignored by default.
- **Structure.** UI-free logic goes in `Sources/ClipwardCore` and comes with tests in
  `Tests/ClipwardCoreTests`. AppKit views and controllers go in `Sources/Clipward`.
- **Style.** Match the surrounding code: small focused types, dependencies passed in, doc comments
  on non-private API.
- **UI changes.** Regenerate the screenshots with `Scripts/screenshots.sh` and include them in the
  pull request.

## Pull requests

1. Fork the repository and create a branch from `main`.
2. Make your change, with tests where it makes sense.
3. Run `Scripts/test.sh` and `Scripts/build-app.sh`.
4. Add an entry under an "Unreleased" heading in `CHANGELOG.md`.
5. Open the pull request and describe what changed and why.

## Releasing (maintainers)

1. Move the "Unreleased" changelog entries under the new version.
2. Tag the version and push the tag: `git tag v1.2.3 && git push origin v1.2.3`.
3. The *Release* workflow builds the app and DMG and publishes a GitHub release with the DMG and
   its SHA-256 checksum.
