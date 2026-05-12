# Intra Ferry Manual Testing

## Local Build

```bash
swift test
swift build
scripts/package-macos-app.sh
```

## Two-Mac Acceptance

1. Install or run Intra Ferry on both Macs.
2. Configure each Mac with the other Mac's host, port, and shared token.
3. Add one authorized receive location on each Mac.
4. Verify the peer state changes from offline to online.
5. Send a small file to the selected remote path.
6. Send a nested folder to the selected remote path.
7. Send a multi-GB file and verify progress remains visible.
8. Disconnect network during transfer, reconnect, and retry.
9. Copy text on Mac A and paste it on Mac B.
10. Copy an image on Mac A and paste it on Mac B.
11. Copy a file in Finder on Mac A and paste the cached copy on Mac B.
12. Pause clipboard sync and verify Mac B's pasteboard does not change.
13. Send a request with an invalid token and verify directory listing, chunk upload, and clipboard write are rejected.
