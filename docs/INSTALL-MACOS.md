# Installing Innbo.dmg on macOS

The `.dmg` built by CI is unsigned and not notarized (no Apple Developer
account in use for v0 — see `docs/home-inventory-app-plan.md`, Client
distribution). macOS Gatekeeper blocks unsigned apps by default with
"Innbo can't be opened because Apple cannot check it for malicious
software."

To install anyway, after dragging `Innbo.app` to Applications:

1. Right-click (or Control-click) `Innbo.app` → **Open**.
2. Click **Open** again in the dialog that appears.

This only needs to be done once per install — subsequent launches work
normally via a regular double-click.

If that doesn't work, remove the quarantine attribute directly:

```
xattr -d com.apple.quarantine /Applications/Innbo.app
```
