# Uninstall Bugbear

One command removes everything: the app, captures, the screen buffer, logs, settings, caches,
permissions (Screen Recording, Accessibility, Microphone, Camera), the login item, the signing
certificate and the source kept for updates. It shows what it will remove and asks first.

```bash
curl -fsSL https://raw.githubusercontent.com/MikeKiselyov/bugbear-app/main/scripts/uninstall.sh | bash
```

From a clone: `scripts/uninstall.sh` (add `--yes` to skip the question).

Screenshots and clips you saved or exported stay where you saved them (`~/Desktop/Bugbear` by default).

## Where Bugbear keeps things

| What | Where |
|---|---|
| The app | `/Applications/Bugbear.app` or `~/Applications/Bugbear.app` |
| Source used for updates | `~/.bugbear` |
| Captures | `~/Library/Application Support/Bugbear/Captures/` |
| Screen buffer | `~/Library/Application Support/Bugbear/Buffer/` (cleared on launch and quit) |
| Exports | the folder chosen in Settings (Desktop by default) |
| Logs | `~/Library/Logs/Bugbear/` |
| Signing certificate (Macs without Xcode) | `~/Library/Application Support/Bugbear/Signing/` |

[Back to the README](../README.md)
