# Subah

A Mac alarm that wakes you with a different song every morning. No AI, no accounts, no keys.
The song comes from a big verified playlist, chosen by that morning's Vedic sky (panchang, plus your natal chart, dasha and
transits) and the weather at your wake-up hour. A song only returns after nearly the whole playlist has played.

## Install
Open `dist/Subah-2.0.0.dmg`, drag **Subah** to Applications, launch it.
First launch of an unsigned app: `xattr -dr com.apple.quarantine /Applications/Subah.app`

## Set up
- Settings (sliders icon): your birth details, and "Use my current location" (on by default).
- Turn the alarm on, tick **Wake my Mac from sleep**, press **Update wake** (asks for your password once, runs `pmset repeat wakeorpoweron`).
- Settings, **Open Subah when I log in**. The app has to be running for the alarm to ring.

## How the song is chosen (`Catalog.swift`)
1. Weather at wake-up: rain, clear and warm, cold, overcast each pull different moods.
2. Moon nakshatra type (light, fierce, fixed, soft, sharp, moving), tithi (Ekadashi, Purnima and Amavasya bring in sacred music),
   weekday lord, and your Tara / Chandrabala / Sade Sati.
3. Songs that fit score higher, a small stable jitter breaks ties, and anything played in the last ~year is excluded.

`CatalogData.swift` is generated: every song was checked against a real music catalog (title, artist, length).

## Build
```
./scripts/build.sh                 # dist/Subah.app + dist/Subah-2.0.0.dmg (arm64 + x86_64, ad-hoc signed)
SUBAH_DAYS=540 .build/release/Subah --selftest   # simulates 540 mornings, reports repeats and variety
```
