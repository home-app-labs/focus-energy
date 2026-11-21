<p align="center">
  <img src="https://homeapplabs.com/assets/img/focus-energy-icon.png" width="128" alt="Focus Energy icon">
</p>

# Focus Energy

A focus timer for the Mac that also looks after your breaks.

Most timers count your work and forget your rest. Focus Energy tracks both and shows how much energy you have left for the day.

**[Download the installer](https://github.com/home-app-labs/focus-energy/releases/latest/download/Focus-Energy.pkg)** · [Website](https://homeapplabs.com/focus-energy/) · macOS 14 or later · free

<p align="center">
  <img src="https://homeapplabs.com/assets/img/focus-energy-running.png" width="360" alt="Focus Energy during a session">
</p>

## What it does

- **One session, not five.** When the timer ends, add 5, 15 or 60 minutes, or take a break. A 30 minute session extended by 15 stays one 45 minute session in the log.
- **Breaks count.** Coffee, a walk, lunch: breaks have their own buttons and a daily target.
- **Energy.** A bar that drops when you push through and recovers when you rest, with a verdict for each day of the week.
- **Three modes.** Light, Moderate and Hardcore, each with its own focus and rest targets. Moderate is 6 hours of focus and 2 hours of rest.
- **Everywhere you look.** Menu bar, Dock icon, a floating window when the timer ends, and desktop widgets in three sizes.
- **Phone notifications with answers.** Optional, through the free [ntfy](https://ntfy.sh) app: if you do not react on the Mac, the phone gets a notification with buttons, and the answer goes back to the Mac.
- **Your data stays yours.** Plain JSON files on your Mac, optionally in your own iCloud Drive. No account, no tracking.

## Install

1. Download [Focus-Energy.pkg](https://github.com/home-app-labs/focus-energy/releases/latest/download/Focus-Energy.pkg) and open it.
2. The app is not signed with a paid Apple developer certificate, so macOS blocks the installer the first time. Open **System Settings → Privacy & Security**, scroll down and click **Open Anyway**.
3. Follow the installer. It copies Focus Energy to your Applications folder and opens it.

There is a step by step guide with pictures on the [website](https://homeapplabs.com/focus-energy/#install).
Prefer to move the app yourself? Take `Focus-Energy.zip` from the [latest release](https://github.com/home-app-labs/focus-energy/releases/latest).

## Build from source

You need Xcode 15 or later.

    git clone https://github.com/home-app-labs/focus-energy.git
    cd focus-energy
    ./build.sh --install --run

`./build.sh` assembles `build/Focus Energy.app`, `--install` copies it to `/Applications`, `--run` opens it. Run the tests with `swift test`.

## Layout

| Path | What is there |
| --- | --- |
| `Sources/FocusPlus` | The app: timer engine, log, windows, settings, phone notifications |
| `Sources/WidgetUI` | Views and the data snapshot shared by the app and the widget |
| `Sources/FocusPlusWidget` | The desktop widget |
| `Tests` | Unit tests for the timer and the log |
| `Resources` | Info.plist files, entitlements, the icon |
| `scripts` | Icon drawing and the release script |
| `Mobile` | An unfinished iPhone and Apple Watch companion. Experimental, not part of the releases |

The app was first called Focus Plus. The code and the bundle identifier `local.focusplus` keep that name so that existing logs and settings carry over.

## Phone notifications

Optional and off by default. They use the free [ntfy](https://ntfy.sh) app, so no account is needed.

1. Open **Settings → Notifications** and click **Set up my phone**.
2. Scan the QR code to get the ntfy app.
3. In ntfy, subscribe to the topic shown in the window. Copy it on the Mac and paste it on the phone.
4. Click **Send a test** and press **It works** in the notification.

When a timer ends and you do not react on the Mac within the delay you set, the phone gets one notification with three buttons: more focus, more break, or stop. The answer comes back to the Mac.
Only short texts leave the Mac. The topic name works like a password, so keep it private.

## Where your data lives

| What | Where |
| --- | --- |
| Sessions, breaks, day ratings | `~/Library/Application Support/FocusPlus/` as plain JSON |
| The same, with iCloud storage switched on | `Focus Energy` folder in your iCloud Drive |
| Settings | the `local.focusplus` defaults domain |

Deleting the app does not delete these. Remove the folder to start from scratch.

## Development aids

Environment variables that make the app easier to test. Run the built binary directly, for example `FOCUSPLUS_SHOW=panel .build/debug/FocusPlus`.

| Variable | Effect |
| --- | --- |
| `FOCUSPLUS_DATA_DIR=/path` | Keep the log in another folder, so tests do not touch real data |
| `FOCUSPLUS_DEMO_SECONDS=5` | Start a focus session that many seconds long |
| `FOCUSPLUS_DEMO_ACTION=extend15` or `break` | Apply that action two seconds after launch |
| `FOCUSPLUS_SHOW=panel,stats,log,settings,widgets,phone` | Open these windows at launch |
| `FOCUSPLUS_SHOW_LATER=widgets` | The same list, opened four seconds after launch, to see the state after a short demo timer has ended |
| `FOCUSPLUS_SETTINGS_TAB=0`, `1` or `2` | Which settings tab to show first |
| `FOCUSPLUS_SNAPSHOT_DIR=/path` | After eight seconds save a PNG of every open window there and quit |
| `FOCUSPLUS_PUSH_TOPIC=name` | Use a throwaway ntfy topic instead of the saved one |

The screenshots on the website are made with `FOCUSPLUS_DATA_DIR` pointing at sample data and `FOCUSPLUS_SNAPSHOT_DIR`.

## Releasing

1. Put the new version number into `VERSION` and describe the changes in `release-notes/<version>.md`.
2. Commit.
3. Run `./scripts/release.sh --publish`. It builds a universal app, the installer and the zip, tags the commit and creates the GitHub release with the files attached.

The download links above always point at the latest release.

## Made with AI

Focus Energy is built by [Home App Labs](https://homeapplabs.com): one person with an idea, and an AI coding assistant doing the typing. Every line is here to read. Fork it and make it yours.

## License

[MIT](LICENSE)
