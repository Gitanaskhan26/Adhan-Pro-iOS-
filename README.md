# Adhan Pro

Adhan Pro is a SwiftUI prayer companion app for Apple platforms. It provides daily prayer times, prayer progress tracking, Qibla direction, Hijri date display, a world clock map, and prayer reminders with Adhan audio.

## Features

- Prayer times calculated with the Adhan Swift package.
- Home dashboard with current prayer, next prayer countdown, sunrise, and Imsak.
- Prayer progress tracking for the five daily prayers.
- Qibla direction and heading support.
- Hijri date display.
- World Clock view with city data and map-based playback controls.
- Local notifications and optional Adhan audio for prayers.
- Support for both Apple mobile and desktop targets configured in the Xcode project.

## Requirements

- Xcode installed on macOS.
- A valid Apple development account if you want to run on a device or archive the app.
- Location access enabled, so the app can calculate accurate prayer times and Qibla direction.
- Notification permission if you want prayer alerts.

## Getting Started

1. Clone the repository.
2. Open `Adhan Pro.xcodeproj` in Xcode.
3. Let Xcode resolve the Swift Package Manager dependency automatically.
4. Select a simulator, device, or Mac destination.
5. Run the app and grant location and notification access when prompted.

## Project Structure

- `Adhan Pro/ContentView.swift` - Main tab-based interface.
- `Adhan Pro/AdhanHomeViewModel.swift` - Prayer time, location, and notification logic.
- `Adhan Pro/WorldClockView.swift` - World clock UI and map experience.
- `Adhan Pro/WorldClockViewModel.swift` - City and playback logic for the world clock.
- `Adhan Pro/WorldCities.json` - City dataset used by the world clock.
- `Adhan Pro/Audio/` - Adhan audio files used for prayer alerts.
- `Adhan Pro/Assets.xcassets/` - App icons, world map imagery, and visual assets.
- `Adhan Pro.xcodeproj/` - Xcode project configuration.

## Permissions Used

- Location: used to determine prayer times and Qibla direction.
- Notifications: used for prayer reminders.
- Audio playback: used for Adhan sounds.

## Notes

- The app is built around a SwiftUI tab layout with Home, World, Qibla, Calendar, and Settings sections.
- Prayer sound playback can be muted per prayer or globally from the app state.
- If you change the city dataset or audio files, keep the file names and references aligned with the Xcode project.

## License

No license has been added yet.