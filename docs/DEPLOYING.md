# Getting Orbit onto your devices

Version 0.17 · bundle ID `com.warhound.orbit` · branch `claude/eloquent-davinci-jay3rl`

This covers a **free Apple ID** (works tonight) and what changes once the **paid Developer
Program** account is active (TestFlight, widgets, CarPlay).

---

## 0. What you need

| Thing | Notes |
|---|---|
| Mac with **Xcode 16 or newer** | Mac App Store, free. Xcode → Settings → Components → make sure an **iOS** platform is installed (and **watchOS** if you want the watch app). |
| iPhone / iPad on **iOS/iPadOS 17 or later** | Settings → General → About → iOS Version. |
| Apple Watch on **watchOS 10 or later** (optional) | Paired with the iPhone. |
| USB-C or Lightning cable | Wi-Fi deployment works after the first cable connection. |
| GitHub Desktop (or git) | To pull the code. |
| Your Apple ID | Free is enough for tonight. |

---

## 1. Get the latest code

**GitHub Desktop**

1. Open GitHub Desktop. Top left, **Current repository** → `warhound_1.0`.
2. Top middle, **Current branch** → `claude/eloquent-davinci-jay3rl`.
3. Click **Fetch origin**, then **Pull origin** if it appears.
4. **Changes** tab (left) should be empty. If it lists `Orbit.xcodeproj/project.pbxproj`, that's Xcode
   remembering your Team. Right-click it → **Discard changes** before pulling, then set the Team again
   in step 3. (Send me your Team ID once and this stops happening.)
5. **History** tab: the top entry should be *“iPad portrait: shows, artwork, chapters, then controls at the bottom (0.17)”* or a later “Update screenshots” entry.

**Terminal alternative**

```
cd ~/path/to/warhound_1.0
git checkout claude/eloquent-davinci-jay3rl
git pull
```

---

## 2. Open the project

1. Quit Xcode if it's open (it can hold an old copy of the project).
2. In Finder, double-click `warhound_1.0/Orbit.xcodeproj`.
3. Wait until the top bar stops saying **Indexing** / **Processing files** (a minute or two the first time).
4. Optional clean start if anything looks odd later: **Product → Clean Build Folder** (⇧⌘K).

The project has four targets; you only touch the first two tonight:

| Target | What it is | Tonight |
|---|---|---|
| **Orbit** | iPhone + iPad app | Yes |
| **OrbitWatch** | Apple Watch app | Optional |
| **OrbitWidgets** | Widgets + Control Centre button | No: needs the paid account |
| (CarPlay) | Part of Orbit | Yes: approved, works in the car |

---

## 3. Signing (once per Mac, and again for each new bundle ID)

The bundle ID changed to `com.warhound.orbit`, so Xcode needs your Team for it once.

1. Xcode → **Settings…** (⌘,) → **Accounts**. If your Apple ID isn't listed: **+** → **Apple ID** → sign in. Close Settings.
2. In the left sidebar (Project navigator, ⌘1) click the blue **Orbit** project icon at the very top.
3. In the middle column, under **TARGETS**, select **Orbit**.
4. Tab **Signing & Capabilities**.
5. Tick **Automatically manage signing**.
6. **Team** → select the Apple Developer team that owns the Orbit CloudKit container. See [Configure CloudKit](#configure-cloudkit).
7. **Bundle Identifier** should read `com.warhound.orbit`. Leave it.
8. The status should go green within a few seconds. If you see a red error, see **Troubleshooting** below.
9. Watch app (optional): select target **OrbitWatch** → same tab → same Team. Bundle ID `com.warhound.orbit.watchkitapp`.
10. Do **not** sign **OrbitWidgets** yet; it isn't part of the app until the paid account.

---

## 4. Prepare each device (first time only)

**iPhone and iPad**

1. Plug it into the Mac and unlock it. Tap **Trust** and enter the passcode.
2. Settings → **Privacy & Security** → scroll to the bottom → **Developer Mode** → **On** → **Restart**. After restart, confirm **Turn On**.
   (If Developer Mode isn't listed, do step 5 first; it appears once Xcode has seen the device.)
3. In Xcode, **Window → Devices and Simulators** (⇧⌘2). Your device should appear, with “Preparing…” the first time (can take several minutes while Xcode copies debug symbols). Wait until that finishes.
4. Optional, for cable-free installs later: in that window tick **Connect via network**.

**Apple Watch** (optional)

1. The iPhone it's paired with must be set up as above and connected.
2. On the watch: Settings → Privacy & Security → **Developer Mode** → On → restart.
3. Keep the watch on its charger, unlocked, near the iPhone. Watch installs are slow (minutes).

---

## 5. Install on iPhone or iPad

1. Top of the Xcode window, the **scheme** menu (left of the device name) → **Orbit**.
2. Device menu (right of it) → your iPhone or iPad (under *iOS Device*).
3. Press **Run** (▶, ⌘R). First build takes a few minutes.
4. First launch on a free Apple ID: the phone says **“Untrusted Developer”**.
   Settings → General → **VPN & Device Management** → your Apple ID → **Trust** → **Trust**. Press ⌘R again.
5. Orbit opens and asks **System / Light / Dark**. Pick one.

Repeat steps 2–3 with the iPad selected for the iPad.

**Because the bundle ID changed, this installs as a new app beside the old Orbit.** Set it up, then
delete the old one (press and hold its icon → Remove App). The old one's library doesn't carry over.

---

## 6. First-run setup in Orbit

1. **Import your shows**: Settings (gear, top left of Latest; on iPad the ⋯ menu above the shows) →
   **Import from Another App** → **Choose OPML File** → pick your Overcast export (Files → wherever you saved it).
   Or in Files, long-press the `.opml` → Share → **Orbit**.
2. Wait for “Now Following 17”. On Wi-Fi the latest episode of each show starts downloading
   (Settings → Downloads → **Manage Downloads** shows progress).
3. Pull down on **Latest** once to refresh artwork for the private feeds.
4. Check Settings → About: **Version 0.17**, **Developer Warhound**, **Built** = tonight.

---

## 7. Install the watch app (optional)

1. Scheme menu → **OrbitWatch**.
2. Device menu → your Apple Watch (listed under the iPhone).
3. ⌘R. Expect several minutes; keep the watch awake.
4. Open Orbit on the iPhone once; the watch lists fill in.

---

## 8. Try CarPlay in the simulator (no car needed)

1. Scheme **Orbit**, device → any **iPhone simulator** (e.g. iPhone 16 Pro).
2. ⌘R. In the simulator, import a couple of shows (Search works) or run with `-demo`
   (Product → Scheme → Edit Scheme → Run → Arguments → **+** → `-demo`).
3. Simulator menu **I/O → External Displays → CarPlay**. A CarPlay window opens with Orbit.
4. Remove `-demo` afterwards (untick it) so the phone build uses your real library.

---

## 9. What to test tonight

| Area | Try |
|---|---|
| Siri (open Orbit once first) | “Play Cortex in Orbit” · “Resume Orbit” · “Add the latest ATP to Up Next in Orbit” · “Set a sleep timer in Orbit” · “Change the speed in Orbit” · “Download new episodes in Orbit” |
| Shortcuts app | Search “Orbit”: all actions listed; build “When CarPlay connects → Resume” |
| Downloads | Airplane Mode mid-download, then off: it resumes · Settings → Downloads options |
| Playback, phone locked | Up Next moves to the next episode · sleep timer fades and pauses · lock-screen controls |
| Appearance | Settings → Appearance; set System and flip the phone between light/dark |
| Quick actions | Press and hold the icon: Resume (names the episode), Up Next, Search |
| Spotlight | Swipe down on the Home Screen, type a show name |
| Sharing | Long-press an episode → Share Episode |
| VoiceOver | Settings → Accessibility → VoiceOver; swipe through Latest; rotor → Actions |
| iPad | Landscape and portrait layouts; tap a show on the left; chapters; ⋯ menu |
| Stats | Library → chart icon, after listening a while |

Send anything odd with a screenshot.

---

## 10. Updating to newer versions

1. GitHub Desktop → **Fetch origin** → **Pull origin**.
2. If `project.pbxproj` shows as changed before pulling, discard it (it's only your Team).
3. Xcode → ⌘R with the device selected. Your library and downloads stay.
4. Settings → About shows the new version number.

**Free Apple ID limits:** apps stop opening after **7 days** (re-run from Xcode to renew); at most
**3** of your own apps per device; no widgets, CarPlay or TestFlight.

---

## CarPlay on your phone (entitlement approved)

1. developer.apple.com → Certificates, Identifiers & Profiles → **Identifiers** → `com.warhound.orbit`.
2. Tab **Additional Capabilities** → tick **CarPlay Audio** → **Save**. (If the tab isn't there, the approval
   email names the steps; Apple sometimes attaches it to the team rather than the App ID.)
3. Xcode → Orbit target → Signing & Capabilities: automatic signing fetches a new profile. If it complains,
   untick and re-tick **Automatically manage signing**.
4. Build to the phone or let Xcode Cloud build for TestFlight, plug into the car (or pair wireless CarPlay):
   Orbit appears on the CarPlay home screen.

---

## 11. Once the paid Developer Program account is active

Tell me when it's approved; I'll make the code changes, you do the Apple-side steps.

**You, in a browser (developer.apple.com and appstoreconnect.apple.com):**

1. **Membership**: enrolled as an **Organisation** if you want “Warhound” shown as the seller
   (needs a legal entity + D-U-N-S number), otherwise Individual (shows your name).
2. **Team ID**: developer.apple.com → Account → Membership details → *Team ID* (10 characters). Send it to me.
3. **App Store Connect → Apps → + → New App**: Platform iOS · Name **Orbit** (or **Orbit Podcasts** if taken) ·
   Language English (UK) · Bundle ID `com.warhound.orbit` (pick from list; if missing, register it at
   developer.apple.com → Identifiers) · SKU `orbit-ios`.
4. **CarPlay**: developer.apple.com/contact/carplay → request **CarPlay audio** for Orbit. Approval takes days to weeks.
5. **App Store Connect API key** (for automatic TestFlight uploads): Users and Access → Integrations →
   App Store Connect API → **+** → name “GitHub”, access **App Manager** → download the `.p8` (once only), note **Key ID** and **Issuer ID**.
6. **GitHub repo secrets**: github.com/tom-landy/warhound_1.0 → Settings → Secrets and variables → Actions → New secret:
   `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` (the file's text), `TEAM_ID`.

**Me, in the code:**

- Put your Team ID in the project (no more re-picking the Team, no more pull clashes).
- Switch on the **App Group** so widgets work, and bundle the **widgets** and **watch app** into the iPhone app.
- Privacy manifest file (Apple requires it for uploads).
- A **TestFlight** workflow: one click in GitHub Actions builds, signs and uploads.
- CarPlay entitlement on device builds (done in 0.34).

**Then TestFlight:**

1. GitHub → Actions → **TestFlight** → Run workflow.
2. ~15–30 minutes later the build appears in App Store Connect → TestFlight (Apple processes it first;
   the first time it asks the export-compliance question, already answered “No” in the app).
3. Add yourself as an **internal tester** (App Store Connect → TestFlight → Internal Testing → +).
4. Install the **TestFlight** app on iPhone/iPad, accept the invite, tap **Install**.
   TestFlight builds last **90 days**, update automatically, and include the watch app and widgets.

---

## Troubleshooting

| Message | Fix |
|---|---|
| *Signing for "Orbit" requires a development team* | Step 3: pick the Team on the **Orbit** target. |
| *Failed to register bundle identifier* / *not available* | Another account owns that ID. Change `ORBIT_BUNDLE_ID` (blue project icon → **PROJECT Orbit** → Build Settings → search `ORBIT_BUNDLE_ID`) to e.g. `com.warhound.orbitpodcasts`, and tell me. |
| *Untrusted Developer* | Settings → General → VPN & Device Management → Trust. |
| *Developer Mode disabled* | Step 4.2, then restart. |
| *iOS 18.x is not installed* / device “not supported” | Xcode → Settings → Components → install that iOS version, or update Xcode. |
| *The maximum number of apps for free development profiles has been reached* | Delete one of your other self-built apps from the device (free accounts allow 3). |
| *Could not launch “Orbit”* (device locked) | Unlock the device, press ⌘R again. |
| Device stuck on “Preparing” | Leave it plugged in and unlocked; it can take 10+ minutes the first time. |
| Watch never installs | Keep watch on charger, unlocked, Bluetooth on; Window → Devices and Simulators → select the watch → wait for it to finish preparing. |
| Build errors in red after pulling | Product → Clean Build Folder (⇧⌘K), then ⌘R. Still failing: copy the first red error to me. |
| App opens to an empty library | Expected after the bundle ID change: import your OPML again. |
| Siri doesn't recognise “play X in Orbit” | Open Orbit once after installing, wait a minute, try again. Settings → Apps → Orbit → Siri → make sure it's allowed. |


## Smart playlists and iCloud Listening Sync

In the iPhone Library, tap the Smart Playlists toolbar button. On iPad, choose Smart Playlists from the More menu. Save a playlist with show, unplayed, downloaded, and duration filters. Play in Order starts the first result and puts the other matches ahead of the existing Up Next queue.

### Configure CloudKit

1. In Certificates, Identifiers & Profiles, enable iCloud with CloudKit for the Orbit App ID. Create or select `iCloud.com.warhound.orbit` and associate it with the App ID. Builds using a different `ORBIT_BUNDLE_ID` need their own matching container with the `iCloud.` prefix.
2. Push Notifications must be enabled for the Orbit App ID too (Listening Sync uses silent CloudKit pushes to sync in the background; users see no prompt). Xcode's automatic signing adds it from `Config/Orbit.entitlements`; if signing complains, tick **Push Notifications** on the App ID in Certificates, Identifiers & Profiles.
3. In Xcode, make sure the Orbit target uses the team that owns that container and refresh the signing profile. Install a development build and enable **Settings → Listening Sync → Sync with iCloud** on a device signed into iCloud.
4. Follow a show, play an episode, and create a playlist in the development build. Use CloudKit Console to confirm that the development schema contains the `ListeningState` record type with its encrypted `encryptedPayload` field. Deploy the schema to production before testing with TestFlight. Development and TestFlight builds use separate CloudKit environments.

### Two-device release check

- Use an iPhone and iPad signed into the same iCloud account. Enable sync on both. Follow and unfollow a show, pause an episode mid-playback, and mark it played and unplayed. Open the other app or tap **Sync Now** and confirm each state arrives.
- Disconnect one device, make an edit, relaunch while offline, then reconnect. Verify the edit reaches the other device. When both devices edit the same item, Orbit uses the later edit.
- Create, edit, and delete a smart playlist on one device. Verify the rules update on the other and that the Downloaded filter uses the audio present on that device. Check Play in Order with episodes already in Up Next.
- Try an unavailable or different iCloud account. Confirm that the status explains why sync is paused and the local library stays accessible.
