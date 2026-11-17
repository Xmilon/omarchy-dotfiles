-- Change the default Omarchy look'n'feel.

-- Opt another application in to Omarchy's standard transparency.
-- Find its class with: hyprctl clients
-- o.transparent_window("my-app")
-- o.transparent_window("my-app", "0.9 0.85") -- Custom active/inactive opacity.

-- https://wiki.hypr.land/Configuring/Basics/Variables/#general
-- hl.config({
--   general = {
--     -- No gaps between windows or borders.
--     gaps_in = 0,
--     gaps_out = 0,
--     border_size = 0,
--
--     -- Change to niri-like side-scrolling layout.
--     layout = "scrolling",
--   },
-- })

-- https://wiki.hypr.land/Configuring/Basics/Variables/#decoration
-- hl.config({
--   decoration = {
--     -- Use round window corners.
--     rounding = 8,
--
--     -- Dim unfocused windows (0.0 = no dim, 1.0 = fully dimmed).
--     dim_inactive = true,
--     dim_strength = 0.15,
--   },
-- })

-- https://wiki.hypr.land/Configuring/Basics/Variables/#animations
-- hl.config({
--   animations = {
--     -- Disable all animations.
--     enabled = false,
--   },
-- })

-- https://wiki.hypr.land/Configuring/Basics/Variables/#layout
-- hl.config({
--   layout = {
--     -- Avoid overly wide single-window layouts on wide screens.
--     single_window_aspect_ratio = { 1, 1 },
--   },
-- })

-- https://wiki.hypr.land/Configuring/Layouts/Scrolling-Layout/
-- hl.config({
--   scrolling = {
--     -- See only one column per screen instead of two.
--     column_width = 0.97,
--   },
-- })

-- Blur what is behind translucent windows (Ghostty) so text stays readable.
-- Super+scroll workspaces: react to each wheel tick (default waits 300ms
-- between scroll binds) and slide between workspaces instead of jumping.
hl.config({ binds = { scroll_event_delay = 60 } })
hl.animation({ leaf = "workspaces", enabled = true, speed = 2.5, bezier = "easeOutQuint", style = "slide" })

-- Files: keep the window opaque to Hyprland; its see-through panels come from
-- ~/.config/gtk-4.0/gtk.css, so text stays sharp while the blur shows behind.
o.transparent_window("org\\.gnome\\.Nautilus", "1.0 0.95")

hl.config({
  decoration = {
    blur = { enabled = true, size = 8, passes = 3, noise = 0.02, brightness = 0.85 },
  },
})

-- Shared window title bar (floating windows): a slim glassy bar with the title
-- in Inter, centred, and round red / yellow / green buttons whose symbols show
-- on hover. Omarchy sets this bar up (hyprbars, in workspace-modes.lua) every
-- time a workspace starts floating, with a monospace font and plain − □ ×
-- buttons, so instead of setting options once we adjust its settings as it
-- applies them.
local TITLEBAR = {
  bar_height = 28,
  bar_color = "rgba(0d0d11d9)",
  bar_color_inactive = "rgba(0d0d11a6)",
  bar_blur = true,
  bar_text_font = "Inter Variable",
  bar_text_size = 12,
  bar_text_weight = "semibold",
  bar_text_align = "center",
  bar_padding = 12,
  bar_button_padding = 8,
  button_rounding = 7,
  icon_on_hover = true,
  inactive_button_color = "rgba(ffffff2e)",
  col = { text = "rgba(ffffffd1)" },
}
-- Omarchy's button icons → colour of the round button that replaces it.
local TITLEBAR_BUTTONS = {
  ["×"] = "rgb(ff5f57)", -- close
  ["□"] = "rgb(28c840)", -- maximize
  ["−"] = "rgb(febc2e)", -- minimize to the dock
}

local omarchy_config = hl.config
hl.config = function(tbl)
  local bars = type(tbl) == "table" and type(tbl.plugin) == "table" and tbl.plugin.hyprbars
  if type(bars) == "table" and bars.enabled then
    for key, value in pairs(TITLEBAR) do bars[key] = value end
  end
  return omarchy_config(tbl)
end

local omarchy_plugin_load = hl.plugin.load
hl.plugin.load = function(...)
  local result = omarchy_plugin_load(...)
  local bars = hl.plugin.hyprbars
  if bars and bars.add_button and not bars.__xmilon_styled then
    local add_button = bars.add_button
    bars.add_button = function(button)
      local colour = type(button) == "table" and TITLEBAR_BUTTONS[button.icon]
      if colour then
        button.bg_color = colour
        button.fg_color = "rgba(00000099)"
        button.size = 14
      end
      return add_button(button)
    end
    bars.__xmilon_styled = true
  end
  return result
end
