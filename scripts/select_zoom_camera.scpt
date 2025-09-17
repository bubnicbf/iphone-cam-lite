-- Adjust these if you renamed your device
property desiredCamera : "iPhone Camera"
property desiredMic : "iPhone Microphone"

on pickFromMenu(appName, menuTitle, submenuTitle, itemName)
  tell application "System Events"
    tell process appName
      try
        click menu item itemName of menu submenuTitle of menu menuTitle of menu bar 1
        return true
      on error
        return false
      end try
    end tell
  end tell
end pickFromMenu

tell application "System Events"
  if not (exists application process "zoom.us") then
    error "Zoom is not running"
  end if
end tell

-- Zoom exposes camera/mic under the "Meeting" menu in some versions, or via the caret next to the camera/mic buttons.
-- We'll try menu paths first; if that fails, try UI buttons.

set appName to "zoom.us"
tell application "System Events"
  tell process appName
    set frontmost to true
    delay 0.5
  end tell
end tell

-- Try menu route
set camPicked to my pickFromMenu(appName, "Meeting", "Select Camera", desiredCamera)
set micPicked to my pickFromMenu(appName, "Meeting", "Select Microphone", desiredMic)

-- If either failed, try clicking the caret buttons (UI scripting heuristic)
if camPicked is false then
  tell application "System Events"
    tell process appName
      try
        click (first button whose description contains "Select a camera") of window 1
        delay 0.3
        click (first menu item whose title is desiredCamera) of menu 1
      end try
    end tell
  end tell
end if

if micPicked is false then
  tell application "System Events"
    tell process appName
      try
        click (first button whose description contains "Select a microphone") of window 1
        delay 0.3
        click (first menu item whose title is desiredMic) of menu 1
      end try
    end tell
  end tell
end if
