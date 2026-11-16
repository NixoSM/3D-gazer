# Building for iPhone

This repository was written on Linux, which can produce Godot's Xcode
project but cannot compile, sign or install an iOS app. Those steps need a
Mac. Budget about 30 minutes the first time.

## Quickest way to play: sideload the CI build (no Mac needed)

Every push to `main` builds an **unsigned** `.ipa` on a GitHub macOS runner
(`.github/workflows/ios-ipa.yml`; it can also be started by hand from the
Actions tab).

1. GitHub → **Actions** → **iOS ipa** → the latest green run → **Artifacts**
   → download **Gazer-ipa** and unzip it to get `Gazer-unsigned.ipa`.
2. Open it in [Sideloadly](https://sideloadly.io) (or AltStore), plug in the
   iPhone, enter your Apple ID and press Start. Sideloadly signs it with
   your account.
3. On the phone: Settings → General → VPN & Device Management → trust your
   Apple ID, and turn on **Developer Mode** (Settings → Privacy & Security)
   if iOS asks.

With a free Apple ID the install expires after 7 days; just sideload again.

## Building it yourself: what you need

- A Mac with **Xcode** (current version from the App Store), opened once to
  accept the licence and install the iOS platform.
- **Godot 4.5.x** for macOS (standard, not .NET), same minor version as `project.godot`.
- An **Apple ID**. A free one can install on your own phone for 7 days at a
  time; TestFlight and the App Store need the paid Apple Developer Program.
- An iPhone with a cable (or on the same network for wireless debugging),
  with **Developer Mode** on: Settings → Privacy & Security → Developer Mode.

## One-time setup

1. Open the project in Godot. Let it import.
2. **Editor → Manage Export Templates → Download and Install** (matching your Godot version).
3. **Project → Export**, select the **iOS** preset (already in `export_presets.cfg`) and set:
   - **App Store Team ID**: from developer.apple.com → Membership, or in
     Xcode → Settings → Accounts → your team (a 10-character code).
   - **Bundle Identifier**: replace `com.example.gazer` with something you
     own, e.g. `com.yourname.gazer`. It must be unique in Apple's system.
   - Leave **Export Project Only** on: Godot writes an Xcode project and you
     build it in Xcode, which gives the clearest signing errors.
4. Export to `build/ios/` (ignored by git). Godot produces `Gazer.xcodeproj`
   and the game data next to it.

## Run on your phone

1. Open `build/ios/Gazer.xcodeproj` in Xcode.
2. Select the **Gazer** target → **Signing & Capabilities** → tick
   *Automatically manage signing* and pick your team.
3. Choose your iPhone as the run destination and press **Run** (⌘R).
4. First launch with a free account: on the phone, Settings → General → VPN &
   Device Management → trust your developer certificate.

## First things to check on the device

These could not be tested without hardware:

- **Tilt direction.** Tilting right should roll the ball right. If it is
  reversed, open pause → *Tilt: inverted*, and please report it so the
  default can be fixed for everyone (`TiltReader`).
- **Tilt strength.** Pause → sensitivity −/+. The default treats 28° of
  tilt as full tilt; tell us what feels right.
- **Haptics** on landing and echo (needs a phone with a Taptic Engine and
  system haptics enabled).
- **120 Hz** on ProMotion iPhones: the preset adds
  `CADisableMinimumFrameDurationOnPhone` to Info.plist for this.
- **Notch and home indicator**: the pause button and texts must stay clear.
- **Audio**: the game uses the *Ambient* session, so your own music keeps
  playing and the mute switch silences the game.

## TestFlight / App Store

1. In Godot's iOS preset set *Export Method Release* to **App Store**.
2. In Xcode: **Product → Archive**, then **Distribute App → App Store
   Connect**. Create the app record in App Store Connect first, with the same
   bundle id.
3. Before submitting you will also need: a 1024×1024 app icon (replace
   `icon.svg` and set the icon fields in the preset), screenshots, a privacy
   declaration (the game collects nothing), and a licence decision for the code.

## Troubleshooting

- *"No profiles for … were found"*: the bundle id is taken or your team is
  not selected. Change the id, re-select the team.
- *Black screen on launch*: check that the export templates' version matches the editor's.
- *Levels missing*: the preset's include filter must contain `levels/*.json`
  (it does). JSON files are not Godot resources and are skipped otherwise.
