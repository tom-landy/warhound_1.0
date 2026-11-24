# Orbit: App Store pack

Everything to paste into App Store Connect, plus how to upload from Xcode.
Bracketed items are yours to fill in.

---

## 1. Upload a build from Xcode (no GitHub needed)

Do this once the paid account is approved.

1. **Xcode → Settings → Accounts**: your Apple ID should now show a team that is *not* "(Personal Team)". Select it to confirm the role is Admin/Account Holder.
2. Blue **Orbit** project icon → target **Orbit** → **Signing & Capabilities** → **Team** → the paid team (your name, *without* "Personal Team"). Bundle ID stays `com.warhound.orbit`.
3. Top of the window, device menu → **Any iOS Device (arm64)**.
4. **Product → Archive**. Takes a few minutes. The **Organizer** window opens when done.
5. Select the new archive → **Distribute App** → **App Store Connect** → **Upload** → keep the defaults (automatic signing, upload symbols) → **Upload**.
6. In 10–30 minutes it appears in App Store Connect → your app → **TestFlight** (status *Processing*, then ready).

If Archive is greyed out: the device menu must be *Any iOS Device*, not a simulator.

**Version numbers:** Settings → About shows e.g. 0.26; that's the version App Store Connect sees, and the build number is 26. Each upload needs a higher build number, so pull my latest before archiving again.

---

## 2. Create the app record (App Store Connect → Apps → +)

| Field | Value |
|---|---|
| Platform | iOS |
| Name | **Orbit** (if taken: **Orbit Podcasts**) |
| Primary language | English (U.K.) |
| Bundle ID | `com.warhound.orbit` (Xcode registers it on first archive; if not listed, developer.apple.com → Identifiers → +) |
| SKU | `orbit-ios` |
| User access | Full access |

---

## 3. TestFlight first

1. App Store Connect → app → **TestFlight** → **Internal Testing** → **+** → group "Me" → add yourself.
2. On the iPhone/iPad: install **TestFlight** from the App Store → accept the invite → **Install**.
3. Use it for a day. Export compliance is pre-answered in the app ("no non-exempt encryption"), so no question should appear.

---

## 4. Listing text

**Subtitle** (30 characters max)
> Podcasts that play offline

**Promotional text** (170 max, can change any time)
> Your shows download on Wi-Fi and play anywhere, even with no signal. Import from Overcast or any podcast app in seconds.

**Description**
> Orbit is a podcast player built for patchy signal.
>
> DOWNLOADS THAT JUST WORK
> • The latest episode of every show you follow downloads automatically on Wi-Fi
> • Downloads carry on in the background and resume after the signal drops
> • Played episodes clean themselves up
>
> BRING YOUR SHOWS
> • Import from Overcast, Pocket Casts, Castro or any app that exports OPML
> • Add private and members-only feeds by URL
> • Search the podcast directory
>
> LISTEN YOUR WAY
> • Up Next queue with automatic play-next
> • Sleep timer, from 15 minutes to end of episode
> • Speed from 0.8× to 2×, set per show
> • Skip intros per show
> • Chapters, with a chapter list you can jump around
>
> EVERYWHERE YOU ARE
> • Siri: "Play Cortex in Orbit", "Resume Orbit", "Set a sleep timer in Orbit"
> • Shortcuts actions and automations
> • Lock Screen and Control Centre controls, AirPlay
> • iPad layout with shows, chapters and notes side by side
> • Listening stats: time listened and time saved by speed
>
> YOURS
> • Light and dark mode, ten colour themes and matching app icons
> • No account, no ads, no tracking. Everything stays on your device.

**Keywords** (100 characters max, comma separated, no spaces needed)
> podcast,podcasts,player,offline,download,overcast,opml,chapters,sleep timer,up next,audio

**Support URL**: [a page or email link you control, e.g. a GitHub page or your website]
**Marketing URL** (optional): [leave blank]
**Copyright**: `2026 Warhound`

**Category**: there's no Podcasts category. Podcast players mostly list under **News** or **Entertainment**; either is fine. Suggest primary **Entertainment**, secondary **News**.

---

## 5. Privacy

**Privacy policy URL** (required): host this text somewhere public (a GitHub Gist, a GitHub Pages page, Notion public page, or your site) and paste the link.

> **Orbit privacy policy**
>
> Orbit does not collect, store or share any personal information.
>
> Your subscriptions, listening history, downloads and settings are stored only on your device. Orbit has no accounts and no analytics, advertising or tracking.
>
> To work, Orbit connects directly to the podcast feeds and audio files you choose, and to Apple's podcast directory when you search. Those services may see your device's IP address, as with any web request. Orbit sends them nothing else about you.
>
> If you have questions, contact [your email].
>
> Last updated: [date].

**App Privacy questionnaire** (App Store Connect → App Privacy → Get Started):
- "Do you or your third-party partners collect data from this app?" → **No, we do not collect data from this app.**
- Result shown on the store: **Data Not Collected**.

The privacy manifest inside the app (`Orbit/PrivacyInfo.xcprivacy`) says the same.

---

## 6. Age rating

Answer the questionnaire honestly. Key point: Orbit can open **any** podcast feed, so it gives access to content Apple can't review. Answer **"Unrestricted Web Access" / user-chosen content: Yes** if asked. Podcast players are commonly rated at the top age band for that reason. I'm not certain of the exact band Apple's current questionnaire will produce; accept what it calculates.

---

## 7. Screenshots

Required because the app supports iPhone and iPad:

| Device class | Size (portrait) | Simulator to use |
|---|---|---|
| iPhone 6.9" | 1320 × 2868 | iPhone 16 Pro Max (or newest Pro Max) |
| iPad 13" | 2064 × 2752 | iPad Pro 13-inch |

How:
1. Xcode → scheme **Orbit**, device → the simulator above.
2. Product → Scheme → Edit Scheme → Run → **Arguments** → add `-demo` (sample shows, so your private feeds aren't in the screenshots). For a specific screen add e.g. `-demoTab library`, `-demoPlayer YES`, `-demoTab settings`.
3. ⌘R. In the simulator: **File → Save Screen** (⌘S). Saves full-resolution PNGs to the Desktop.
4. Take 3–5 per device: Latest, the player, Library, Settings/themes, and on iPad the full layout.
5. **Untick `-demo` afterwards** so device builds use your real library.

---

## 8. Notes for the reviewer (App Review Information → Notes)

> Orbit is a podcast player. No account or login is needed.
>
> To try it: open Search, search for any podcast (e.g. "Cortex"), tap a result, tap Follow, then tap an episode's play button. Settings → Import from Another App accepts OPML subscription files.
>
> Background audio is used to keep episodes playing when the app is in the background or the screen is locked. Background fetch refreshes feeds so new episodes download on Wi-Fi.
>
> NSAllowsArbitraryLoads is enabled because podcast feeds, artwork and audio files are published by thousands of independent hosts, and many still serve them over plain HTTP. Orbit only loads the feeds and files the user chooses.
>
> CarPlay support is included but inactive until the CarPlay audio entitlement is granted.

Contact details: your name, phone, email. Sign-in required: **No**.

---

## 9. Before pressing Submit for Review

- [ ] TestFlight build installed and used on a real device
- [ ] Screenshots uploaded (iPhone 6.9" and iPad 13")
- [ ] Description, keywords, support URL, privacy policy URL filled in
- [ ] App Privacy → Data Not Collected, published
- [ ] Age rating done
- [ ] Price: Free (Pricing and Availability)
- [ ] Build selected under the version
- [ ] Review notes pasted
