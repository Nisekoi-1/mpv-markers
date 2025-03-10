# MPV Auto Markers Script

This repository contains a Lua script for the MPV video player that automatically creates an ASS file to store markers set during playback. The markers are persistent and can be added, removed, or cleared during viewing. Useful if you are creating fansubs and watching the episode before starting work on it.

- **Add Markers:** Press `+` during playback to set a marker.
- **Remove Last Marker:** Press `Ctrl++` to remove the last marker.
- **Clear All Markers:** Press `Ctrl+Shift++` to clear all markers.
- **Persistent Storage:** Markers are stored in an ASS file specific to the video file.
- **Export Markers:** Option to export markers to a text file.
- **Jump Between Markers:** Functions to jump to the previous or next marker (by playback time).

## Installation

1. Place the `auto_markers.lua` file in your MPV scripts directory:
   - **Linux:** `~/.config/mpv/scripts/`
   - **Windows:** `%APPDATA%\mpv\scripts\`
2. Restart MPV or load the script manually.

## Customization

You can adjust the following settings within the script:
- `marker_display_duration`: Duration (in seconds) that a marker is displayed in the ASS file.
- `osd_duration`: Duration (in seconds) for on-screen messages.
- `marker_prefix`: Text prefix for markers.
