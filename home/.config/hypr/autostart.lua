-- Extra autostart processes.
-- o.launch_on_start("my-service")

-- Loading screen right after login; fades out once wallpaper, bar and
-- notifications are up (~/.config/xmilon/session-splash)
o.exec_on_start("quickshell -n -p " .. os.getenv("HOME") .. "/.config/xmilon/session-splash")

-- Digital vibrance (~73% on Windows' scale), restored at each login
o.launch_on_start("nvibrant 471 471 471 471")

-- Screensaver: hide the bar while it's up and dismiss it on mouse movement
o.launch_on_start(os.getenv("HOME") .. "/.local/bin/xmilon-screensaver-guard")
