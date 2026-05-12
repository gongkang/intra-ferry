# Intra Ferry

Intra Ferry is a macOS menu bar app for peer-to-peer file, folder, and clipboard transfer between two Macs on a trusted internal network.

## Development

Run tests:

```bash
swift test
```

Build:

```bash
swift build
```

## Packaging

Build a local macOS app bundle:

```bash
scripts/package-macos-app.sh
open build/IntraFerry.app
```

## Manual Testing

See `docs/manual-testing.md` for the two-Mac acceptance checklist.
