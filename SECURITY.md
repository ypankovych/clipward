# Security policy

Clipward handles some of the most sensitive data on a Mac, so security reports get priority.

## Supported versions

Only the latest release receives security fixes.

## Reporting a vulnerability

Please **do not open a public issue**. Report it privately through
[GitHub private vulnerability reporting](https://github.com/ypankovych/clipward/security/advisories/new).

Please include:

- what an attacker could do, and under what conditions;
- steps or a proof of concept to reproduce it;
- your macOS version and the Clipward version.

You will get a reply within a week. Once a fix is released, you'll be credited in the release
notes unless you'd rather stay anonymous.

## Security model

What Clipward protects against:

- **Other users and offline access to the disk.** History is encrypted with AES-256-CBC +
  HMAC-SHA256, using a random key stored in the login Keychain. Files are owner-only and excluded
  from Time Machine.
- **Secrets lingering on the clipboard.** Items pasted from the history are cleared after a
  configurable timeout.
- **Recording passwords.** Content marked with the nspasteboard.org concealed or transient types,
  and copies made in ignored apps, are never stored.

What it does not protect against:

- Malware already running as your user. It can read the clipboard directly, and it may be able to
  use the Keychain item.
- Copies from apps that don't mark sensitive content. Add those apps to *Ignored apps*, or pause
  recording.
