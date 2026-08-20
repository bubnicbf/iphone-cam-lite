-- Desired camera and microphone menu labels. Overridden at runtime via
-- the first two command-line arguments (camera name, then microphone
-- name) which scripts/start_zoom.sh supplies from the CAMERA_NAME and
-- MICROPHONE_NAME environment variables. These property values remain
-- the defaults whenever an argument is missing or empty, so invoking
-- this script directly with osascript and no arguments still behaves
-- exactly as before.
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

on run argv
  -- argv is data passed straight through by osascript (no shell involved
  -- and no dynamically generated AppleScript source), so a multi-word
  -- name, an apostrophe, parentheses, or Unicode characters arrive intact
  -- as a single list item each.
  if (count of argv) > 0 then
    set candidateCamera to item 1 of argv
    if candidateCamera is not "" then set desiredCamera to candidateCamera
  end if
  if (count of argv) > 1 then
    set candidateMic to item 2 of argv
    if candidateMic is not "" then set desiredMic to candidateMic
  end if

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
          set camPicked to true
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
          set micPicked to true
        end try
      end tell
    end tell
  end if

  -- Report a clear, nonzero failure naming the requested device if it was
  -- never found via either route, instead of silently succeeding.
  if camPicked is false then
    error "Could not select camera \"" & desiredCamera & "\" -- check that this name matches a camera listed in Zoom's camera menu."
  end if
  if micPicked is false then
    error "Could not select microphone \"" & desiredMic & "\" -- check that this name matches a microphone listed in Zoom's microphone menu."
  end if
end run
