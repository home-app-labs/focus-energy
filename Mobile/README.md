# Focus Energy for iPhone and Apple Watch

Experimental and unfinished. A companion that shows the timer, today's focus and the energy level from the Mac. Only the Mac controls the timer. It is not part of the releases.

## What is inside

| Target | What it is |
| --- | --- |
| `FocusPlusMobile` | iPhone app: countdown ring, details, the week |
| `FocusPlusMobileWidget` | iPhone widgets: small, medium, large and three for the Lock Screen |
| `FocusPlusWatch` | Apple Watch app |
| `FocusPlusWatchWidget` | Watch face complications: circular, rectangular, corner, inline |

The ring layout and the data model are shared with the Mac app and live in `../Sources/WidgetUI`.

## How the data reaches the phone and the watch

1. The Mac writes `widget-state.json` into the "Focus Energy" folder in iCloud Drive. Storage in iCloud Drive must be switched on in the Mac app's settings, General tab.
2. The iPhone reads that file. Pick the folder once in the app with "Choose the Focus Energy folder".
3. The iPhone passes the data on to the watch and schedules a notification for the moment the timer ends.

Limitation: the iPhone reads the file while the app is open and occasionally in the background, when iOS allows it. There is no instant sync while the app is closed. That would need CloudKit and a paid Apple developer account.

## Status

- The iPhone app has been run in the iOS simulator only.
- The watch app compiles but has never been run.

## Installing on your own devices

You need a Mac with Xcode, a cable and an Apple ID. A free Apple ID is enough, but the app then has to be reinstalled every 7 days.

1. Run `xcodegen` in this folder (the Xcode project is not kept in the repository) and open `FocusPlusMobile.xcodeproj`.
2. In Xcode, Settings, Accounts: sign in with your Apple ID.
3. For each of the four targets open Signing & Capabilities and choose your team.
4. If Xcode says the identifier is taken, replace `dev.focusplus` with your own prefix in `project.yml` and in the four `.entitlements` files (the group `group.dev.focusplus.shared`).
5. Connect the iPhone with a cable and trust the computer.
6. On the iPhone: Settings, Privacy & Security, Developer Mode, switch on, restart. The item appears after the first connection to Xcode.
7. The same on the watch: Settings, Privacy & Security, Developer Mode.
8. In Xcode choose the `FocusPlusMobile` scheme and your iPhone, then Run. The watch app is installed along with it.
9. On first launch on the iPhone: Settings, General, VPN & Device Management, trust your developer certificate.

## Building from the terminal

```bash
xcodegen                         # recreate the project after editing project.yml
xcodebuild -project FocusPlusMobile.xcodeproj -scheme FocusPlusMobile \
  -destination 'platform=iOS Simulator,name=iPhone 15' build
```
