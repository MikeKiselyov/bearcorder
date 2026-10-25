# Uninstall Bugbear

Quit Bugbear from the panel (power button), then:

```bash
rm -rf "/Applications/Bugbear.app" "$HOME/Applications/Bugbear.app"   # the app
rm -rf ~/.bugbear                                                     # the source used for updates
rm -rf "$HOME/Library/Application Support/Bugbear"                    # captures and buffer
rm -rf "$HOME/Library/Logs/Bugbear"                                   # logs
```

Permissions can be removed in System Settings → Privacy & Security.

## Where Bugbear keeps things

| What | Where |
|---|---|
| The app | `/Applications/Bugbear.app` or `~/Applications/Bugbear.app` |
| Source used for updates | `~/.bugbear` |
| Captures | `~/Library/Application Support/Bugbear/Captures/` |
| Screen buffer | `~/Library/Application Support/Bugbear/Buffer/` (cleared on launch and quit) |
| Exports | the folder chosen in Settings (Desktop by default) |
| Logs | `~/Library/Logs/Bugbear/` |

[Back to the README](../README.md)
