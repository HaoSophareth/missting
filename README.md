<img src="Resources/sunflower.png" alt="Missting" width="64" />

# Missting

**[missting.vercel.app](https://missting.vercel.app)**

A tiny macOS menu bar app that keeps you on top of your meetings — without the noise.

See what's coming up, get a nudge before it starts, and auto-join at exactly the right moment.

---

## Get access

Missting is in private beta. To join, email **haosophareth070@gmail.com** with the subject **"Missting beta"** and I'll whitelist your Google account.

---

## Install

> Requires macOS 13 or later.

1. Download `Missting.zip` from the [latest release](https://github.com/HaoSophareth/missting/releases/latest)
2. Open Terminal and paste:

```bash
MZIP=$(ls -t ~/Downloads/Missting*.zip 2>/dev/null | head -1) && [ -n "$MZIP" ] && unzip -o "$MZIP" -d /tmp/_MisstingInstall && rm -rf /Applications/Missting.app && xattr -cr /tmp/_MisstingInstall/Missting.app && mv /tmp/_MisstingInstall/Missting.app /Applications/ && rm -rf /tmp/_MisstingInstall && echo "✅ Done!" || echo "❌ No Missting.zip found in ~/Downloads."
```

3. Open Missting from `/Applications` — the 🌻 appears in your menu bar
4. Click it → **Sign in with Google** → grant calendar access

---

## What it does

**Menu bar countdown** — Always know what's next: `in 5m`, `in 2h`, `· in progress`

**Auto-join** — Tell Missting to open your meeting link automatically, a few minutes before it starts

**Floating alerts** — A quiet popup appears before each meeting, even when the app isn't open

**Smart join tracking** — Once you've joined, Missting knows. If you missed it, it asks if you're already in

**Calendar filtering** — Show only the calendars you care about

**Minerva support** — Auto-detects class join links from your Minerva Academic calendar

---

## Minerva setup (optional)

1. On **Forum** → **Edit Profile** → scroll to the bottom → **Copy Calendar Link**
2. Open **Google Calendar** → **+** next to "Other calendars" → **From URL** → paste
3. Refresh Missting — the status in Settings turns green

---

## Privacy

Missting uses OAuth 2.0 PKCE — no passwords stored. Your calendar data is fetched directly from Google and never leaves your machine.
