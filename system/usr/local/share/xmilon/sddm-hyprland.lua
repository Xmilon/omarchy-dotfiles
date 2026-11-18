-- Login screen (SDDM greeter) compositor config.
-- Omarchy's greeter config, plus: when an external monitor is plugged in, the
-- laptop panel is off so the login screen only appears on the external one
-- (like Windows). Laptop alone: the panel stays on.
-- Decided from the kernel's connector status before any screen is lit, so the
-- panel never flashes on first. Output names aren't hard-coded (eDP-1/eDP-2).
-- Used via CompositorCommand in /etc/sddm.conf.d/zz-thyx-login.conf.
dofile("/usr/share/sddm/hyprland.lua")

local function is_laptop(name)
  return name:match("^eDP") ~= nil or name:match("^LVDS") ~= nil
end

local function connectors()
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

function XmilonGreeterMonitors()
  local external, laptops = false, {}
  for _, c in ipairs(connectors()) do
    if is_laptop(c.name) then laptops[c.name] = true
    elseif c.connected then external = true end
  end
  for _, m in ipairs(hl.get_monitors()) do
    local name = tostring(m.name)
    if is_laptop(name) then laptops[name] = true else external = true end
  end
  for name in pairs(laptops) do
    if external then
      hl.monitor({ output = name, disabled = true })
    else
      hl.monitor({ output = name, disabled = false, mode = "preferred", position = "auto", scale = "auto" })
    end
  end
end

hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })
XmilonGreeterMonitors()
hl.on("monitor.added", XmilonGreeterMonitors)
hl.on("monitor.removed", function()
  XmilonGreeterMonitors()
  hl.exec_cmd("sleep 1.5 && hyprctl eval 'XmilonGreeterMonitors()'")
end)
