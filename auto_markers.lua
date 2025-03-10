-- auto_markers.lua
-- This script automatically creates an ASS file when markers are set during video playback
-- and updates it with every new marker. The ASS file itself is used as persistent storage.
-- Markers now preserve their insertion order (their assigned number) even if added at an earlier time.
--
-- Press "+" during playback to set a marker.
-- Press "Ctrl++" to delete the last marker.
-- Press "Ctrl+Shift++" to clear all markers.

local utils = require 'mp.utils'
local options = {
    marker_display_duration = 1,  -- Duration (in seconds) to display markers in the ASS file
    osd_duration = 1.5,           -- Duration (in seconds) for on-screen messages
    marker_prefix = "Marker",     -- Text prefix for markers
}

-- Each marker is stored as a table: { time = <seconds>, id = <insertion number> }
local markers = {}  
local next_marker_id = 1

-- Format a time value (in seconds) into ASS timestamp format: H:MM:SS.CS
local function format_time(t)
    local h = math.floor(t / 3600)
    local m = math.floor((t % 3600) / 60)
    local s = math.floor(t % 60)
    local cs = math.floor((t - math.floor(t)) * 100)
    return string.format("%d:%02d:%02d.%02d", h, m, s, cs)
end

-- Format time for displaying in OSD (with ms precision)
local function format_time_display(t)
    local h = math.floor(t / 3600)
    local m = math.floor((t % 3600) / 60)
    local s = math.floor(t % 60)
    local ms = math.floor((t - math.floor(t)) * 1000)
    if h > 0 then
        return string.format("%d:%02d:%02d.%03d", h, m, s, ms)
    else
        return string.format("%02d:%02d.%03d", m, s, ms)
    end
end

-- Parse an ASS time string (H:MM:SS.CS) into seconds
local function parse_ass_time(time_str)
    local h, m, s, cs = string.match(time_str, "(%d+):(%d%d):(%d%d)%.(%d%d)")
    h = tonumber(h) or 0
    m = tonumber(m) or 0
    s = tonumber(s) or 0
    cs = tonumber(cs) or 0
    return h * 3600 + m * 60 + s + cs / 100
end

-- Determine the marker filename based on the current video file
local function get_marker_filename()
    local path = mp.get_property("path")
    if not path then
        return "markers.ass"
    end
    local dir, filename = utils.split_path(path)
    return dir .. filename:gsub("%.%w+$", "") .. ".markers.ass"
end

-- Save (or update) the ASS file with all markers in insertion order.
local function update_ass_file()
    local filename = get_marker_filename()
    local file, err = io.open(filename, "w")
    if not file then
        mp.msg.error("Could not open file for writing: " .. err)
        mp.osd_message("Export failed: " .. err, options.osd_duration * 2)
        return
    end

    -- Write ASS header and style info.
    file:write("[Script Info]\n")
    file:write("Title: MPV Markers\n")
    file:write("ScriptType: v4.00+\n")
    file:write("Collisions: Normal\n")
    file:write("PlayResX: 1920\n")
    file:write("PlayResY: 1080\n")
    file:write("Timer: 100.0000\n")
    file:write("\n")
    file:write("[V4+ Styles]\n")
    file:write("Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding\n")
    file:write("Style: Default,Arial,28,&H00FFFFFF,&H000000FF,&H00000000,&H80000000,1,0,0,0,100,100,0,0,1,2,1,2,10,10,10,1\n")
    file:write("\n")
    file:write("[Events]\n")
    file:write("Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n")

    -- Write markers in insertion order (sorted by their id).
    table.sort(markers, function(a, b) return a.id < b.id end)
    for _, marker in ipairs(markers) do
        local start_time = format_time(marker.time)
        local end_time = format_time(marker.time + options.marker_display_duration)
        -- Use the stored marker id for the display text.
        local text = string.format("%s %02d", options.marker_prefix, marker.id)
        file:write(string.format("Comment: 0,%s,%s,Default,,0,0,0,,%s\n", start_time, end_time, text))
    end

    file:close()
    mp.msg.info(string.format("Markers updated (%d total) in %s", #markers, filename))
end

-- Load existing markers from the ASS file.
-- Extracts both the start time and the marker id (from the text field).
local function load_markers()
    local filename = get_marker_filename()
    local file = io.open(filename, "r")
    if not file then
        return
    end
    markers = {}
    local max_id = 0
    for line in file:lines() do
        if line:find(options.marker_prefix) then
            -- Expecting a line like:
            -- Comment: 0,Start,End,Default,,0,0,0,,Marker XX
            local start_time_str = line:match("^Comment:%s*%d+,%s*([^,]+),")
            local text_field = line:match(",,%s*(.-)%s*$")
            if start_time_str and text_field then
                local t = parse_ass_time(start_time_str)
                local id = tonumber(text_field:match(options.marker_prefix .. "%s*(%d+)"))
                if id then
                    table.insert(markers, { time = t, id = id })
                    if id > max_id then
                        max_id = id
                    end
                end
            end
        end
    end
    file:close()
    -- Sort markers by their insertion order (id)
    table.sort(markers, function(a, b) return a.id < b.id end)
    next_marker_id = max_id + 1
    mp.msg.info(string.format("Loaded %d previous marker(s) from %s", #markers, filename))
end

-- Helper: return markers sorted by time (used for jumping).
local function get_markers_by_time()
    local sorted = {}
    for _, m in ipairs(markers) do
        table.insert(sorted, m)
    end
    table.sort(sorted, function(a, b) return a.time < b.time end)
    return sorted
end

-- Add a marker at the current playback position.
-- The new marker gets the next sequential id, regardless of its time.
local function add_marker()
    local pos = mp.get_property_number("time-pos")
    if not pos then
        mp.osd_message("Cannot add marker: No playback position", options.osd_duration)
        return
    end
    table.insert(markers, { time = pos, id = next_marker_id })
    mp.osd_message(string.format("Marker %02d set at %s", next_marker_id, format_time_display(pos)), options.osd_duration)
    next_marker_id = next_marker_id + 1
    update_ass_file()
end

-- Remove the last added marker (by insertion order) and update the file.
local function remove_last_marker()
    if #markers == 0 then
        mp.osd_message("No markers to remove", options.osd_duration)
        return
    end
    -- Remove the marker with the highest id.
    table.sort(markers, function(a, b) return a.id < b.id end)
    local removed = table.remove(markers)
    mp.osd_message(string.format("Removed marker %02d at %s", removed.id, format_time_display(removed.time)), options.osd_duration)
    if #markers > 0 then
        update_ass_file()
    else
        local filename = get_marker_filename()
        os.remove(filename)
        mp.msg.info("All markers removed, deleted " .. filename)
    end
end

-- Clear all markers and delete the ASS file.
local function clear_markers()
    if #markers == 0 then
        mp.osd_message("No markers to clear", options.osd_duration)
        return
    end
    local count = #markers
    markers = {}
    local filename = get_marker_filename()
    os.remove(filename)
    mp.osd_message(string.format("Cleared %d markers", count), options.osd_duration)
    mp.msg.info(string.format("Cleared %d markers, deleted %s", count, filename))
end

-- Export markers to a simple text file.
local function export_markers_text()
    if #markers == 0 then
        mp.osd_message("No markers to export", options.osd_duration)
        return
    end
    local path = mp.get_property("path")
    if not path then
        mp.osd_message("No file is being played", options.osd_duration)
        return
    end
    local dir, filename = utils.split_path(path)
    local export_filename = dir .. filename:gsub("%.%w+$", "") .. ".markers.txt"
    local file, err = io.open(export_filename, "w")
    if not file then
        mp.msg.error("Could not open file for writing: " .. err)
        mp.osd_message("Text export failed: " .. err, options.osd_duration * 2)
        return
    end
    file:write("# Markers for " .. filename .. "\n")
    file:write("# Created by MPV auto_markers.lua\n\n")
    for _, marker in ipairs(markers) do
        file:write(string.format("%02d\t%s\t%s %02d\n", marker.id, format_time_display(marker.time), options.marker_prefix, marker.id))
    end
    file:close()
    mp.osd_message("Exported markers to " .. export_filename, options.osd_duration * 2)
end

-- Jump to the previous marker (based on time order).
local function goto_previous_marker()
    local sorted = get_markers_by_time()
    if #sorted == 0 then
        mp.osd_message("No markers set", options.osd_duration)
        return
    end
    local current_pos = mp.get_property_number("time-pos")
    local target = nil
    for i = #sorted, 1, -1 do
        if sorted[i].time < current_pos - 0.5 then
            target = sorted[i]
            break
        end
    end
    if not target then
        target = sorted[#sorted]
    end
    mp.set_property_number("time-pos", target.time)
    mp.osd_message(string.format("Jumped to marker %02d (%s)", target.id, format_time_display(target.time)), options.osd_duration)
end

-- Jump to the next marker (based on time order).
local function goto_next_marker()
    local sorted = get_markers_by_time()
    if #sorted == 0 then
        mp.osd_message("No markers set", options.osd_duration)
        return
    end
    local current_pos = mp.get_property_number("time-pos")
    local target = nil
    for i = 1, #sorted do
        if sorted[i].time > current_pos + 0.5 then
            target = sorted[i]
            break
        end
    end
    if not target then
        target = sorted[1]
    end
    mp.set_property_number("time-pos", target.time)
    mp.osd_message(string.format("Jumped to marker %02d (%s)", target.id, format_time_display(target.time)), options.osd_duration)
end

-- Display help text.
local function show_help()
    local help_text = [[
Auto Markers Script Help:
  +           : Add marker at current position
  Ctrl++      : Remove last marker
  Ctrl+Shift++: Clear all markers
]]
    mp.osd_message(help_text, 10)
end

-- Set key bindings.
mp.add_key_binding("+", "add_marker", add_marker)
mp.add_key_binding("Ctrl++", "remove_last_marker", remove_last_marker)
mp.add_key_binding("Ctrl+Shift++", "clear_markers", clear_markers)

-- On file load, load markers from the ASS file.
mp.register_event("file-loaded", function()
    load_markers()
end)
