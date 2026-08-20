-- Selects the configured camera and microphone in Zoom's own UI.
--
-- Command-line arguments (all optional; a missing or empty argument uses
-- the English default noted below, so `osascript select_zoom_camera.scpt`
-- with no arguments still behaves as before):
--   1. camera name               (default: "iPhone Camera")
--   2. microphone name           (default: "iPhone Microphone")
--   3. meeting menu label        (default: "Meeting")
--   4. camera submenu label      (default: "Select Camera")
--   5. microphone submenu label  (default: "Select Microphone")
--   6. camera control label      (default: "Select a camera")
--   7. microphone control label  (default: "Select a microphone")
-- scripts/start_zoom.sh supplies these from CAMERA_NAME, MICROPHONE_NAME,
-- and the ZOOM_* environment variables documented in README.md.
--
-- Strategy: try the exact Meeting-menu route first (fast, precise, when
-- its labels match this Zoom build/locale). If either device is still
-- unresolved, fall back to a bounded semantic accessibility search across
-- Zoom's currently visible windows and their sheets -- never assumed to
-- be "window 1" -- matching camera/microphone controls by their
-- description or title rather than a fixed position. Camera and
-- microphone success are tracked independently; the script only succeeds
-- once both are confirmed selected, and raises one actionable error
-- naming the device(s) and strategies that failed otherwise.
--
-- Known limitation: this remains UI/accessibility scripting, not an
-- official Zoom automation API. A Zoom release that removes both the
-- Meeting menu route and the camera/microphone selector controls (or
-- requires an unlisted extra step, such as a permission sheet) is outside
-- what label overrides alone can fix.

property desiredCamera : "iPhone Camera"
property desiredMic : "iPhone Microphone"
property meetingMenuLabel : "Meeting"
property cameraMenuLabel : "Select Camera"
property microphoneMenuLabel : "Select Microphone"
property cameraControlLabel : "Select a camera"
property microphoneControlLabel : "Select a microphone"
property zoomProcessName : "zoom.us"

-- resolveArg returns argv's idx-th item if present and non-empty,
-- otherwise defaultValue. Centralizes the "missing/empty argument uses
-- the documented default" rule so every argument is handled identically.
on resolveArg(argv, idx, defaultValue)
  if (count of argv) >= idx then
    set candidateValue to item idx of argv
    if candidateValue is not "" then return candidateValue
  end if
  return defaultValue
end resolveArg

-- pickMenuItem attempts the exact menu-bar route:
--   Meeting menu > <submenuLabel> submenu > <itemName> item
-- Returns true only if the click genuinely succeeded (never silently).
on pickMenuItem(procName, menuTitle, submenuTitle, itemName)
  tell application "System Events"
    tell process procName
      try
        click menu item itemName of menu submenuTitle of menu menuTitle of menu bar 1
        return true
      on error
        return false
      end try
    end tell
  end tell
end pickMenuItem

-- relevantWindows returns a bounded, deterministic list of the process's
-- currently visible windows plus any sheets attached to them (not an
-- unbounded accessibility-tree walk, and never assumed to be "window 1").
on relevantWindows(procName)
  set foundWindows to {}
  tell application "System Events"
    tell process procName
      set allWindows to windows
      repeat with w in allWindows
        set end of foundWindows to w
        try
          set sheetList to sheets of w
          repeat with s in sheetList
            set end of foundWindows to s
          end repeat
        end try
      end repeat
    end tell
  end tell
  return foundWindows
end relevantWindows

-- boundedContainers returns win itself plus its direct groups, scroll
-- areas, and toolbars -- a bounded set of relevant containers, not a
-- recursive walk of the entire accessibility tree.
on boundedContainers(procName, win)
  set containerList to {win}
  tell application "System Events"
    tell process procName
      try
        set containerList to containerList & (groups of win)
      end try
      try
        set containerList to containerList & (scroll areas of win)
      end try
      try
        set containerList to containerList & (toolbars of win)
      end try
    end tell
  end tell
  return containerList
end boundedContainers

-- findControlCandidates searches the given bounded containers for
-- buttons or pop-up buttons whose description or title contains
-- controlLabel. Returns every match (not just the first) so the caller
-- can detect ambiguity instead of guessing which one is correct.
on findControlCandidates(procName, containerList, controlLabel)
  set matches to {}
  tell application "System Events"
    tell process procName
      repeat with c in containerList
        try
          repeat with b in (buttons of c)
            try
              if (description of b contains controlLabel) or (title of b contains controlLabel) then
                set end of matches to b
              end if
            end try
          end repeat
        end try
        try
          repeat with p in (pop up buttons of c)
            try
              if (description of p contains controlLabel) or (title of p contains controlLabel) then
                set end of matches to p
              end if
            end try
          end repeat
        end try
      end repeat
    end tell
  end tell
  return matches
end findControlCandidates

-- selectDeviceFromCandidates clicks the requested device item from
-- exactly one unambiguous candidate control. Returns {true, ""} on
-- success, or {false, reason} identifying why it could not proceed
-- (no candidate, ambiguous candidates, or the device item itself being
-- unavailable) -- never a silently swallowed failure.
on selectDeviceFromCandidates(procName, candidates, deviceName, controlLabel)
  if (count of candidates) is 0 then
    return {false, "no control found matching \"" & controlLabel & "\""}
  end if
  if (count of candidates) > 1 then
    return {false, "ambiguous match: " & (count of candidates) & " controls matched \"" & controlLabel & "\""}
  end if
  set theControl to item 1 of candidates
  tell application "System Events"
    tell process procName
      try
        click theControl
        delay 0.3
        click (first menu item whose title is deviceName) of menu 1 of theControl
        return {true, ""}
      on error errMsg
        return {false, "device item \"" & deviceName & "\" unavailable on the matched control (" & errMsg & ")"}
      end try
    end tell
  end tell
end selectDeviceFromCandidates

on run argv
  set desiredCamera to resolveArg(argv, 1, desiredCamera)
  set desiredMic to resolveArg(argv, 2, desiredMic)
  set meetingMenuLabel to resolveArg(argv, 3, meetingMenuLabel)
  set cameraMenuLabel to resolveArg(argv, 4, cameraMenuLabel)
  set microphoneMenuLabel to resolveArg(argv, 5, microphoneMenuLabel)
  set cameraControlLabel to resolveArg(argv, 6, cameraControlLabel)
  set microphoneControlLabel to resolveArg(argv, 7, microphoneControlLabel)

  tell application "System Events"
    if not (exists application process zoomProcessName) then
      error "Zoom is not running (process \"" & zoomProcessName & "\" not found)."
    end if
  end tell

  tell application "System Events"
    tell process zoomProcessName
      set frontmost to true
      delay 0.5
    end tell
  end tell

  set camPicked to false
  set camDiagnostic to "menu route (" & meetingMenuLabel & " > " & cameraMenuLabel & ") did not select the requested camera"
  set micPicked to false
  set micDiagnostic to "menu route (" & meetingMenuLabel & " > " & microphoneMenuLabel & ") did not select the requested microphone"

  -- Strategy 1: exact menu route (preferred when its labels match).
  if pickMenuItem(zoomProcessName, meetingMenuLabel, cameraMenuLabel, desiredCamera) then
    set camPicked to true
  end if
  if pickMenuItem(zoomProcessName, meetingMenuLabel, microphoneMenuLabel, desiredMic) then
    set micPicked to true
  end if

  -- Strategy 2: bounded semantic accessibility fallback, only for
  -- whichever device(s) the menu route did not already confirm.
  if not camPicked or not micPicked then
    set candidateWindows to relevantWindows(zoomProcessName)
    repeat with w in candidateWindows
      if not camPicked then
        set containerList to boundedContainers(zoomProcessName, w)
        set camCandidates to findControlCandidates(zoomProcessName, containerList, cameraControlLabel)
        set camResult to selectDeviceFromCandidates(zoomProcessName, camCandidates, desiredCamera, cameraControlLabel)
        if item 1 of camResult then
          set camPicked to true
        else
          set camDiagnostic to camDiagnostic & "; fallback: " & (item 2 of camResult)
        end if
      end if
      if not micPicked then
        set containerList to boundedContainers(zoomProcessName, w)
        set micCandidates to findControlCandidates(zoomProcessName, containerList, microphoneControlLabel)
        set micResult to selectDeviceFromCandidates(zoomProcessName, micCandidates, desiredMic, microphoneControlLabel)
        if item 1 of micResult then
          set micPicked to true
        else
          set micDiagnostic to micDiagnostic & "; fallback: " & (item 2 of micResult)
        end if
      end if
      if camPicked and micPicked then exit repeat
    end repeat
  end if

  if camPicked and micPicked then
    return
  end if

  set failureParts to {}
  if not camPicked then
    set end of failureParts to "camera \"" & desiredCamera & "\" was not selected (" & camDiagnostic & ")"
  end if
  if not micPicked then
    set end of failureParts to "microphone \"" & desiredMic & "\" was not selected (" & micDiagnostic & ")"
  end if
  set failureText to ""
  repeat with p in failureParts
    if failureText is "" then
      set failureText to p
    else
      set failureText to failureText & "; " & p
    end if
  end repeat
  error "Zoom device selection failed: " & failureText
end run
