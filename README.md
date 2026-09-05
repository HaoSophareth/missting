# Missting

A menu bar app that notifies and auto-launches Google Calendar links so you're always early.

See what's coming up, get a nudge before it starts, and auto-join at exactly the right moment.

---

## Install

> Requires macOS 12 or later.

No download needed — press `⌘ Command + Space`, type **Terminal**, press Return, then paste this line and press Return:

```bash
curl -fsSL https://raw.githubusercontent.com/HaoSophareth/missting/main/install.sh | bash
```

It installs the latest version straight into `/Applications` and opens it. Then click the <img src="favicon.png" width="16" height="16" alt="Missting" align="absmiddle"> in your menu bar → **Sign in with Google** → grant calendar access.

Missting is a free beta and not yet notarized by Apple, which is why a normal double-click on the downloaded zip shows a false "damaged" warning — the line above avoids that entirely.

### Updates

Missting updates itself: it checks for new releases daily and installs them in the background (or right-click the <img src="favicon.png" width="16" height="16" alt="Missting" align="absmiddle"> → **Check for Updates…**). You only ever run the install line once.

---

## Privacy

Missting uses OAuth 2.0 PKCE — no passwords stored. Your calendar data is fetched directly from Google and never leaves your machine.
