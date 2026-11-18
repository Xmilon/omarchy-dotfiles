-- See https://wiki.hypr.land/Configuring/Basics/Monitors/
-- List current monitors and supported resolutions with: hyprctl monitors all

-- Monitor scale is Hyprland's scale for the output. It sizes everything
-- Wayland-native, accepts fractions (1.6, 1.75), and applies immediately.
-- "auto" lets Hyprland pick per display.
local omarchy_monitor_scale = "auto"
hl.monitor({ output = "", mode = "1920x1080@180", position = "auto", scale = omarchy_monitor_scale })
-- Laptop screen (eDP) only when no other monitor is plugged in: off while an
-- external monitor is connected, back on as soon as none is.
-- Decided from the kernel's connector status (/sys/class/drm) while the config
-- loads, before Hyprland lights any screen, so it never turns the laptop
-- screen on just to turn it off again (that reconfigure is a slow black flash
-- on NVIDIA). Like Windows applying the remembered layout at boot. Checked
-- again whenever a monitor is plugged in or unplugged. Output names aren't
-- fixed (eDP-1 or eDP-2 depending on driver load order), so none are hard-coded.
local function xmilon_is_laptop(name)
  return name:match("^eDP") ~= nil or name:match("^LVDS") ~= nil
end

local function xmilon_connectors()
  local list = {}
  local p = io.popen('for f in /sys/class/drm/card*-*/status; do [ -r "$f" ] && echo "$f $(cat "$f")"; done 2>/dev/null')
  if p then
    for line in p:lines() do
      local name, status = line:match("/card%d+%-([^/]+)/status (%S+)")
      if name and not name:match("^Writeback") then list[#list + 1] = { name = name, connected = status == "connected" } end
    end
    p:close()
  end
  return list
end

function XmilonUpdateLaptopScreen()
  local external, laptops = false, {}
  for _, c in ipairs(xmilon_connectors()) do
    if xmilon_is_laptop(c.name) then laptops[c.name] = true
    elseif c.connected then external = true end
  end
  for _, m in ipairs(hl.get_monitors()) do
    local name = tostring(m.name)
    if xmilon_is_laptop(name) then laptops[name] = true else external = true end
  end
  for name in pairs(laptops) do
    if external then
      hl.monitor({ output = name, disabled = true })
    else
      -- disabled = false has to be said outright, or the earlier "off" sticks.
      hl.monitor({ output = name, disabled = false, mode = "preferred", position = "auto", scale = omarchy_monitor_scale })
    end
  end
end
XmilonUpdateLaptopScreen()
hl.on("monitor.added", XmilonUpdateLaptopScreen)
hl.on("monitor.removed", function()
  XmilonUpdateLaptopScreen()
  -- Unplugging can take a moment to settle; look again so the laptop screen
  -- never stays dark with nothing else connected.
  hl.exec_cmd("sleep 1.5 && hyprctl eval 'XmilonUpdateLaptopScreen()'")
end)

-- Configure a specific onitor.
-- hl.monitor({ output = "DP-2", mode = "2560x1440@144", position = "0x0", scale = 1 })

-- Portrait/rotated secondary monitor (transform: 1 = 90°, 3 = 270°).
-- hl.monitor({ output = "DP-2", mode = "preferred", position = "auto", scale = 1, transform = 1 })

-- GDK scale is GDK_SCALE, the factor GTK draws its own UI at. It's what
-- sizes X11/XWayland windows, which Omarchy leaves unscaled so they stay
-- crisp instead of being stretched by the compositor. GTK only honors whole
-- numbers, so use the nearest integer to the monitor scale, and restart an
-- app for a change to reach it.
local omarchy_gdk_scale = 1
hl.env("GDK_SCALE", tostring(omarchy_gdk_scale))
