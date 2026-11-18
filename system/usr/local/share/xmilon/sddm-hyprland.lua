-- Login screen (SDDM greeter) compositor config.
-- Omarchy's greeter config, plus: when an external monitor is plugged in, the
-- laptop panel is switched off so the login screen only appears on the
-- external one (like Windows). Laptop alone: the panel stays on.
-- Used via CompositorCommand in /etc/sddm.conf.d/zz-thyx-login.conf.
dofile("/usr/share/sddm/hyprland.lua")

local function is_laptop(name)
  return tostring(name):match("^eDP") ~= nil or tostring(name):match("^LVDS") ~= nil
end

function XmilonGreeterMonitors()
  local monitors = hl.get_monitors()
  local external = false
  for _, m in ipairs(monitors) do
    if not is_laptop(m.name) then external = true end
  end
  for _, m in ipairs(monitors) do
    if is_laptop(m.name) then
      if external then
        hl.monitor({ output = m.name, disabled = true })
      else
        hl.monitor({ output = m.name, disabled = false, mode = "preferred", position = "auto", scale = "auto" })
      end
    end
  end
end

-- A disabled panel drops out of get_monitors, so remember it by name too.
function XmilonGreeterLaptopBack()
  local external = false
  for _, m in ipairs(hl.get_monitors()) do
    if not is_laptop(m.name) then external = true end
  end
  if not external then
    for _, name in ipairs({ "eDP-1", "eDP-2" }) do
      hl.monitor({ output = name, disabled = false, mode = "preferred", position = "auto", scale = "auto" })
    end
  end
end

hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })
XmilonGreeterMonitors()
hl.on("monitor.added", XmilonGreeterMonitors)
hl.on("monitor.removed", function()
  XmilonGreeterLaptopBack()
  hl.exec_cmd("sleep 1.5 && hyprctl eval 'XmilonGreeterLaptopBack()'")
end)
