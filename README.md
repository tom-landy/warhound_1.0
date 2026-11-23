# Warhound

iPhone app, SwiftUI, iOS 17+. Needs Xcode 16 or later.

## Run on your Mac

    git clone https://github.com/tom-landy/warhound_1.0.git
    cd warhound_1.0
    open Warhound.xcodeproj

Pick an iPhone simulator in the toolbar and press Cmd+R.

## Run on your iPhone

1. Plug the phone in (or pair it over Wi-Fi in Window → Devices and Simulators).
2. On the phone: Settings → Privacy & Security → Developer Mode → on, then restart.
3. In Xcode: select the Warhound target → Signing & Capabilities → Team → your Apple ID
   (add it under Xcode → Settings → Accounts if it isn't listed). A free Apple ID works;
   apps signed with one expire after 7 days and need re-running from Xcode.
4. If the bundle ID clashes, change `com.tomlandy.Warhound` to something unique.
5. Pick the phone as the run destination and press Cmd+R. First time, trust the developer
   on the phone under Settings → General → VPN & Device Management.

## Layout

- `Warhound/` holds all source and assets. The Xcode project uses a synchronised folder,
  so any file added here is picked up automatically, no project-file edits needed.
- `.github/workflows/ios.yml` builds the app for the simulator on every push.
