# 🌻 Missting — Never Miss a Meeting

A lightweight macOS menu bar app that connects to your Google Calendar and makes sure you actually join your meetings.

See what's coming up, auto-join at the right time, and get notified before it's too late — all from your menu bar.

## Beta Access

Missting is currently in private beta. Google requires me to manually whitelist each user while the app is in testing mode (up to 100 people).

If you want to try it, email **haosophareth070@gmail.com** with the subject **"Missting beta"** and I'll add your Google account. Once you're whitelisted, follow the steps below.

## Installation

1. Download `Missting.zip` from the [latest release](https://github.com/HaoSophareth/missting/releases/latest)
2. Double-click the zip to unzip it — you should see `Missting.app` in your Downloads folder
3. Run this in Terminal:

```bash
rm -rf /Applications/Missting.app && xattr -cr ~/Downloads/Missting.app && mv ~/Downloads/Missting.app /Applications/
```

4. Open **Missting** from `/Applications` — the 🌻 appears in your menu bar

> Requires macOS 13 or later

**Having trouble?** If the command says `No such file or directory`, your zip may have downloaded as `Missting (1).zip`. Rename it first by running:
```bash
mv ~/Downloads/Missting\ \(1\).zip ~/Downloads/Missting.zip
```
Then double-click to unzip and re-run the install command above.

## Features

**Menu bar countdown** — Always know what's next: `in 5m`, `in 2h 30m`, `· in progress`

**Auto-join** — Schedule Missting to open your meeting link automatically, up to 5 minutes before it starts

**Floating alerts** — Non-intrusive popups appear before meetings start, even when Missting isn't open

**Smart join tracking** — Once you've joined, the button flips to "Joined". If you open the app mid-meeting without having joined, it asks if you're already in

**Calendar filtering** — Choose exactly which Google Calendars show up in Missting, mirroring what you've selected in Google Calendar

**Minerva support** — Auto-detects class join links from Minerva Academic calendar (forum.minerva.edu → class.minerva.edu)

**Notification reminders** — Get notified 30m, 15m, 10m, or 5m before meetings start

**Wake from sleep alerts** — If your laptop was asleep during a meeting, Missting alerts you immediately on wake

## Setup

### Connect Google Calendar

Click the 🌻 in your menu bar → **Sign in with Google** → grant calendar access.

### Minerva Academic Calendar (optional)

To get auto-detected join links for Minerva classes:

1. On **Forum**, open your profile → **Edit Profile** → scroll to the bottom → **Copy Calendar Link**
2. Open **Google Calendar** → click **+** next to "Other calendars" → **From URL** → paste the link
3. Refresh Missting — the Minerva status in Settings will turn green

## Usage

| Action | How |
|---|---|
| See upcoming meetings | Click 🌻 in menu bar |
| Join a meeting | Click **Join now** on any card |
| Auto-join a meeting | Click **Auto-join** → Missting opens the link at the right time |
| Dismiss a card | Click **×** — it stays gone until you reopen the popover |
| Browse tomorrow | Use **›** arrow in the day picker |
| Filter calendars | Settings (⊟) → Calendars |
| Change notification timing | Settings → Notify me before meetings |
| Change auto-join offset | Settings → Auto-join before start |

## Building from Source

Requires Swift and Xcode Command Line Tools.

```bash
git clone https://github.com/HaoSophareth/missting.git
cd missting
bash build.sh
cp -r Missting.app /Applications/
```

## Privacy

Missting uses OAuth 2.0 PKCE to authenticate with Google — no passwords are stored. Your calendar data is fetched directly from Google's API and never leaves your machine.
