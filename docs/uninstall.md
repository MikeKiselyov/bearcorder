# Uninstall Bearcorder

One command removes everything: the app, captures, the screen buffer, logs, settings, caches,
permissions (Screen Recording, Accessibility, Microphone, Camera), the login item, the signing
certificate and the source kept for updates. It shows what it will remove and asks first.
The source folder stays when it has changes or commits that are not pushed, or when git is not
installed (Command Line Tools or Xcode) to check that; the command says so.
An app that only shares Bearcorder's name is left alone.

```bash
curl -fsSL https://raw.githubusercontent.com/MikeKiselyov/bearcorder/main/scripts/uninstall.sh | bash
```

From a clone: `scripts/uninstall.sh` (add `--yes` to skip the question).

A copy installed before 0.15.0 has the app's old name, and this command does not find it. Remove it
with the uninstaller of that version, then install as usual:

```bash
curl -fsSL https://raw.githubusercontent.com/MikeKiselyov/bearcorder/v0.14.0/scripts/uninstall.sh | bash
```

Screenshots and clips you saved or exported stay where you saved them (`~/Desktop/Bearcorder` by default).

We are sorry to see you go. At the end the command links a short form,
[Why I uninstalled](https://github.com/MikeKiselyov/bearcorder/issues/new?template=uninstall_feedback.yml):
if you can, tell us what you did not like. In a terminal it offers to open the form for you.

## Where Bearcorder keeps things

| What | Where |
|---|---|
| The app | `/Applications/Bearcorder.app` or `~/Applications/Bearcorder.app` |
| Source used for updates | `~/.bearcorder` |
| Captures | `~/Library/Application Support/Bearcorder/Captures/` |
| Screen buffer | `~/Library/Application Support/Bearcorder/Buffer/` (cleared on launch and quit) |
| Exports | the folder chosen in Settings (Desktop by default) |
| Logs | `~/Library/Logs/Bearcorder/` |
| Signing certificate (Macs without Xcode) | `~/Library/Application Support/Bearcorder/Signing/` |

[Back to the README](../README.md)
