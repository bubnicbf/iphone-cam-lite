-- Desired camera and microphone menu labels. Overridden at runtime via
-- the first two command-line arguments (camera name, then microphone
-- name) which scripts/start_teams.sh supplies from the CAMERA_NAME and
-- MICROPHONE_NAME environment variables. These property values remain
-- the defaults whenever an argument is missing or empty, so invoking
-- this script directly with osascript and no arguments still behaves
-- exactly as before.
property desiredCamera : "iPhone Camera"
property desiredMic : "iPhone Microphone"
property appName : "Microsoft Teams"

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
    if not (exists application process appName) then
      error "Teams is not running"
    end if
  end tell

  -- Open Settings → Devices, then pick camera/mic from popups
  tell application "System Events"
    tell process appName
      set frontmost to true
      delay 0.5
      -- Open Settings via menu
      try
        click menu item "Settings" of menu 1 of menu bar item "Microsoft Teams" of menu bar 1
      on error
        -- Fallback: Command+comma
        keystroke "," using command down
      end try
      delay 0.8

      -- Click "Devices" in Settings
      try
        click (first UI element whose title is "Devices" and role is "AXButton") of window 1
      on error
        -- In some builds it's a list item
        try
          click (first UI element whose title is "Devices") of window 1
        end try
      end try
      delay 0.5

      -- Select Microphone
      set micPicked to false
      try
        set micPopup to first pop up button of window 1 whose description contains "Microphone"
        click micPopup
        delay 0.2
        click (first menu item whose title is desiredMic) of menu 1 of micPopup
        set micPicked to true
      end try

      -- Select Camera
      set camPicked to false
      try
        set camPopup to first pop up button of window 1 whose description contains "Camera"
        click camPopup
        delay 0.2
        click (first menu item whose title is desiredCamera) of menu 1 of camPopup
        set camPicked to true
      end try
    end tell
  end tell

  -- Report a clear, nonzero failure naming the requested device if it was
  -- never found, instead of silently succeeding.
  if micPicked is false then
    error "Could not select microphone \"" & desiredMic & "\" -- check that this name matches a microphone listed in Teams' Devices settings."
  end if
  if camPicked is false then
    error "Could not select camera \"" & desiredCamera & "\" -- check that this name matches a camera listed in Teams' Devices settings."
  end if
end run
