# FightMilk privacy

FightMilk is a free weight-lifting log for Android. It has no account, no ads, no tracking and no analytics. Nothing about you is collected, sold or shared.

## What is stored, and where

- Your workouts, plans, weigh-ins, notes, goals and settings are stored only on your phone, in the app's private storage. Android's cloud backup is switched off for this app.
- Progress photos are kept inside the app only. They are never in a backup, an export, a share, an AI request or a log.
- API keys and server passwords are kept in Android's secure storage. They are never in a backup.
- The app keeps a short local log of its last few errors (the kind of error and where in the app it happened, never your data). It stays on the phone; you can read it in Settings → About → Debug info and copy it yourself.

## When the app goes online

Only when you tap something that needs it, or when you switch one of these on yourself:

1. **Ask AI** (off until you set it up): the text shown to you before sending goes to the AI service you picked, with your own key. The on-phone model sends nothing.
2. **App updates and icon packs**: the app asks GitHub for the newest release. Like visiting any web page, GitHub sees your phone's internet address. You can let the app check by itself on start (off by default).
3. **The on-phone AI model**: downloaded from Hugging Face once, when you ask.
4. **Send a backup to your own server**: only when you tap Send, only to the WebDAV or Nextcloud address you typed, and only over https.

Nothing else is sent, ever. Automatic backups go to a folder you picked (on the phone, or a cloud app's folder you chose yourself).

## Your data is yours

- Export everything (CSV, JSON, PDF and more) or make a backup at any time, in Settings.
- Settings → Data & privacy → Delete all data removes everything from the phone. Backups you saved elsewhere are not touched.

## The app itself

- The code is open: https://github.com/Balderding/FightMilk
- Release APKs are signed with one key. Its certificate's SHA-256 fingerprint is
  `f4f3906d08e2413d1c0175011d4ee29e7ebabce019df8a429eaa5f8e51c28989`.
  Android only installs an update signed with that same key.

Questions or problems: open an issue on GitHub.
