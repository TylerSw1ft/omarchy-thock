-- Thock: typing sounds without reading the keyboard.
--
-- Hyprland already sees every key; nothing else needs to. These bindings are
-- non-consuming (the key still reaches the focused window) and ignore
-- modifiers, and each one fires a Hyprland global shortcut that the Thock
-- service in omarchy-shell listens for. The shell only learns "a key went
-- down" or "came back up" and which of four sound groups it belongs to, never
-- which key it was.
--
-- Keys are matched by physical position (XKB keycode), so any layout works.
-- Bindings are not `locked`, so nothing plays while the screen is locked.
-- Loaded from ~/.config/hypr/hyprland.lua.

local opts = { non_consuming = true, ignore_mods = true }

-- A global shortcut gets both edges of a key from one binding: "pressed" on
-- the way down and "released" on the way up, so the service can play the
-- downstroke and the softer upstroke.
local function thock(code, sound)
  hl.bind("code:" .. code, hl.dsp.global("thock:" .. sound), opts)
end

local function range(first, last)
  for code = first, last do
    thock(code, "key")
  end
end

thock(9, "key")    -- Escape
range(10, 21)      -- 1 .. =
thock(22, "backspace")
thock(23, "key")   -- Tab
range(24, 35)      -- q .. ]
thock(36, "enter")
range(38, 49)      -- a .. ` (and ')
range(51, 61)      -- \ z .. /
thock(65, "space")
thock(94, "key")   -- ISO <> key
range(79, 91)      -- keypad digits and operators
thock(63, "key")   -- keypad *
thock(106, "key")  -- keypad /
thock(104, "enter") -- keypad Enter
for _, code in ipairs({ 110, 111, 112, 113, 114, 115, 116, 117, 118, 119 }) do
  thock(code, "key") -- Home, arrows, Page Up/Down, End, Insert, Delete
end
