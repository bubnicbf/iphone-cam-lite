-- Adjust for your device names
property desiredCamera : "iPhone Camera"
property desiredMic : "iPhone Microphone"
property appName : "Microsoft Teams"

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
    try
      set micPopup to first pop up button of window 1 whose description contains "Microphone"
      click micPopup
      delay 0.2
      click (first menu item whose title is desiredMic) of menu 1 of micPopup
    end try

    -- Select Camera
    try
      set camPopup to first pop up button of window 1 whose description contains "Camera"
      click camPopup
      delay 0.2
      click (first menu item whose title is desiredCamera) of menu 1 of camPopup
    end try
  end tell
end tell
