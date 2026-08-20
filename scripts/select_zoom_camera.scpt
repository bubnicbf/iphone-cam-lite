-- Selects the configured camera and microphone in Zoom's own UI, and does
-- not report success until the resulting selected state has actually been
-- read back and confirmed to exactly match the requested device name.
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
-- unconfirmed, fall back to a bounded semantic accessibility search across
-- Zoom's currently visible windows and their sheets -- never assumed to
-- be "window 1" -- matching camera/microphone controls by their
-- description or title rather than a fixed position.
--
-- A click is never treated as success by itself. Every strategy reads the
-- resulting semantic accessibility state back (a menu item's mark/selected
-- state for the menu route, a control's resulting value/title for the
-- accessibility fallback) and compares it against the requested device
-- name with exact text equality before counting the device as confirmed.
-- If the requested device is already selected before any click, that is
-- treated as confirmed success and no click is issued. Confirmation polls
-- a small, bounded number of times (see confirmationTimeoutSeconds /
-- confirmationPollInterval below) rather than waiting indefinitely; if the
-- timeout is reached, or the relevant state cannot be read at all, the
-- device is treated as unconfirmed, never as successful. Camera and
-- microphone confirmation are tracked independently; the script only
-- succeeds once both are confirmed, and raises one actionable error
-- naming the device(s) and strategies that failed otherwise.
--
-- Known limitation: this remains UI/accessibility scripting, not an
-- official Zoom automation API. Confirmation relies on Zoom exposing
-- AXMenuItemMarkChar (or a "selected" attribute) on its device menu items,
-- and a readable value/title on its accessibility-fallback controls; a
-- Zoom release that stops exposing either, removes both the Meeting menu
-- route and the camera/microphone selector controls, or requires an
-- unlisted extra step (such as a permission sheet), is outside what label
-- overrides alone can fix -- confirmation will correctly report itself as
-- unavailable rather than assume success in that case.

property desiredCamera : "iPhone Camera"
property desiredMic : "iPhone Microphone"
property meetingMenuLabel : "Meeting"
property cameraMenuLabel : "Select Camera"
property microphoneMenuLabel : "Select Microphone"
property cameraControlLabel : "Select a camera"
property microphoneControlLabel : "Select a microphone"
property zoomProcessName : "zoom.us"

-- Bounded, documented confirmation polling: at most ~12 reads spread over
-- 3 seconds, never an indefinite wait. Small enough to keep a failed
-- launch fast, large enough to absorb Zoom's own UI update latency after
-- a click.
property confirmationTimeoutSeconds : 3.0
property confirmationPollInterval : 0.25

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

-- trimWhitespace strips only leading/trailing spaces, tabs, and newlines
-- -- the one "insignificant representation difference" this script
-- normalizes. Everything else (case, punctuation, apostrophes, internal
-- spacing, non-English characters) is left completely untouched, so
-- namesMatch below never treats two genuinely different device names as
-- equivalent.
on trimWhitespace(s)
  set n to count of s
  set startIdx to 1
  repeat while startIdx <= n and (character startIdx of s is " " or character startIdx of s is tab or character startIdx of s is return or character startIdx of s is linefeed)
    set startIdx to startIdx + 1
  end repeat
  if startIdx > n then return ""
  set endIdx to n
  repeat while endIdx >= startIdx and (character endIdx of s is " " or character endIdx of s is tab or character endIdx of s is return or character endIdx of s is linefeed)
    set endIdx to endIdx - 1
  end repeat
  if startIdx > endIdx then return ""
  return text startIdx thru endIdx of s
end trimWhitespace

-- namesMatch is the single source of truth for "is this the requested
-- device": exact, case-sensitive Unicode text equality after trimming
-- surrounding whitespace -- never substring/contains matching, so
-- "iPhone Camera" never matches "iPhone Camera Pro" or vice versa. Pure
-- string logic with no System Events dependency, so it can be exercised
-- with synthetic values independent of any live accessibility state.
on namesMatch(actualValue, requestedValue)
  considering case
    return (trimWhitespace(actualValue) is (trimWhitespace(requestedValue)))
  end considering
end namesMatch

-- markIndicatesSelected interprets the value read back from a menu item's
-- AXMenuItemMarkChar (a non-empty mark character, typically a checkmark,
-- means selected; an empty string means not selected) or, when that
-- attribute is unavailable, the boolean "selected" attribute rendered as
-- the text "true"/"false" by readItemMarkOrSelected below. Pure logic,
-- no System Events dependency.
on markIndicatesSelected(markValue)
  if markValue is "" then return false
  if markValue is "false" then return false
  return true
end markIndicatesSelected

-- pickMenuItem attempts the exact menu-bar route:
--   Meeting menu > <submenuLabel> submenu > <itemName> item
-- Returns {true, ""} only if the click genuinely succeeded, or
-- {false, diagnostic} carrying the underlying AppleScript error message
-- and number -- never a silently discarded failure. Checks the item's
-- existence before attempting the click, so a missing item is reported
-- as "item not found" rather than being folded into the same message as
-- a click that failed for some other reason. This is a click-only
-- helper; it does not by itself confirm the resulting selection state --
-- see confirmMenuSelection below, which is what "on run argv" actually
-- calls.
on pickMenuItem(procName, menuTitle, submenuTitle, itemName)
  tell application "System Events"
    tell process procName
      if not (exists menu item itemName of menu submenuTitle of menu menuTitle of menu bar 1) then
        return {false, "menu route (" & menuTitle & " > " & submenuTitle & " > " & itemName & "): item not found"}
      end if
      try
        click menu item itemName of menu submenuTitle of menu menuTitle of menu bar 1
        return {true, ""}
      on error errMsg number errNum
        return {false, "menu route (" & menuTitle & " > " & submenuTitle & " > " & itemName & "): click failed: " & errMsg & " (error " & errNum & ")"}
      end try
    end tell
  end tell
end pickMenuItem

-- readItemMarkOrSelected reads a menu item's checked/selected state,
-- preferring AXMenuItemMarkChar and falling back to the "selected"
-- attribute when the mark character isn't exposed. Returns {true, value}
-- on a successful read, or {false, diagnostic} if neither attribute could
-- be read -- never assumed to be selected when unreadable.
on readItemMarkOrSelected(theItem)
  tell application "System Events"
    try
      return {true, (value of attribute "AXMenuItemMarkChar" of theItem)}
    on error markErrMsg number markErrNum
      try
        return {true, ((selected of theItem) as string)}
      on error selErrMsg number selErrNum
        return {false, "AXMenuItemMarkChar unreadable: " & markErrMsg & " (error " & markErrNum & "); selected attribute unreadable: " & selErrMsg & " (error " & selErrNum & ")"}
      end try
    end try
  end tell
end readItemMarkOrSelected

-- readMenuItemMarkChar locates the target menu item and reads its
-- checked/selected state via readItemMarkOrSelected. Many apps expose a
-- menu item's accessibility state without the menu being visibly open;
-- when that direct reference fails, this deliberately reopens the menu
-- (Zoom-specific requirement: "if necessary, reopen the configured menu
-- to inspect the requested item"), reads the item, and closes the menu
-- again with Escape so this confirmation step leaves no menu open behind
-- it. Returns {true, value} or {false, diagnostic} -- never silently
-- assumes success.
on readMenuItemMarkChar(procName, menuTitle, submenuTitle, itemName)
  tell application "System Events"
    tell process procName
      try
        set theItem to menu item itemName of menu submenuTitle of menu menuTitle of menu bar 1
        return readItemMarkOrSelected(theItem)
      end try
      try
        click menu bar item menuTitle of menu bar 1
        delay 0.15
        click menu submenuTitle of menu menuTitle of menu bar 1
        delay 0.15
        set theItem to menu item itemName of menu submenuTitle of menu menuTitle of menu bar 1
        set readResult to readItemMarkOrSelected(theItem)
        key code 53
        return readResult
      on error errMsg number errNum
        try
          key code 53
        end try
        return {false, "menu item \"" & itemName & "\" mark/selected state unreadable even after reopening the menu: " & errMsg & " (error " & errNum & ")"}
      end try
    end tell
  end tell
end readMenuItemMarkChar

-- confirmMenuSelection is Strategy 1's full click-and-verify pipeline:
-- if the requested item is already marked/selected, it reports confirmed
-- success without clicking anything; otherwise it clicks via pickMenuItem
-- and then polls readMenuItemMarkChar (bounded by confirmationTimeoutSeconds
-- / confirmationPollInterval) until the mark indicates selection, a click
-- failure is observed, or the timeout expires. Returns {true, ""} only
-- once the selected state has actually been read back and matched --
-- never merely because the click did not throw.
on confirmMenuSelection(procName, menuTitle, submenuTitle, itemName)
  set preCheck to readMenuItemMarkChar(procName, menuTitle, submenuTitle, itemName)
  if item 1 of preCheck and markIndicatesSelected(item 2 of preCheck) then
    return {true, ""}
  end if

  set clickResult to pickMenuItem(procName, menuTitle, submenuTitle, itemName)
  if not item 1 of clickResult then
    return {false, item 2 of clickResult}
  end if

  set elapsed to 0
  set lastReadable to false
  set lastValue to "(unread)"
  repeat
    set readResult to readMenuItemMarkChar(procName, menuTitle, submenuTitle, itemName)
    if item 1 of readResult then
      set lastReadable to true
      set lastValue to item 2 of readResult
      if markIndicatesSelected(lastValue) then
        return {true, ""}
      end if
    end if
    if elapsed >= confirmationTimeoutSeconds then exit repeat
    delay confirmationPollInterval
    set elapsed to elapsed + confirmationPollInterval
  end repeat
  if lastReadable then
    return {false, "menu route (" & menuTitle & " > " & submenuTitle & " > " & itemName & "): clicked but its mark/selected state never confirmed the change within " & confirmationTimeoutSeconds & "s (last observed mark: \"" & lastValue & "\")"}
  else
    return {false, "menu route (" & menuTitle & " > " & submenuTitle & " > " & itemName & "): clicked but its mark/selected state could not be read to confirm the change"}
  end if
end confirmMenuSelection

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
        -- Optional, genuinely harmless: many windows have no sheets at
        -- all, which is normal, not a failure worth reporting. Skipping
        -- sheet discovery for such a window never drops the window
        -- itself from foundWindows.
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
  -- Each lookup below is optional and genuinely harmless: a window
  -- missing a given container class (no groups, no scroll areas, no
  -- toolbars) is normal, not a failure -- win itself is always still
  -- returned, so callers always have at least one container to search.
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
  -- Every try below is optional and genuinely harmless: a container
  -- lacking buttons/pop-up buttons, or a single element lacking a
  -- description/title, simply does not contribute a match -- it never
  -- hides a required failure, since the caller (selectDeviceFromCandidates)
  -- explicitly reports "no control found" when matches ends up empty.
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

-- readControlSelectionValue reads the control's resulting selected value
-- -- preferring its "value" attribute (how pop-up buttons typically
-- expose the current selection) and falling back to "title". Returns
-- {true, value} on a successful read, or {false, diagnostic} if neither
-- could be read -- never assumed to match when unreadable.
on readControlSelectionValue(procName, control)
  tell application "System Events"
    tell process procName
      try
        return {true, ((value of control) as string)}
      on error valueErrMsg number valueErrNum
        try
          return {true, (title of control)}
        on error titleErrMsg number titleErrNum
          return {false, "control's resulting value unreadable: " & valueErrMsg & " (error " & valueErrNum & "); title unreadable: " & titleErrMsg & " (error " & titleErrNum & ")"}
        end try
      end try
    end tell
  end tell
end readControlSelectionValue

-- selectDeviceFromCandidates is Strategy 2's full click-and-verify
-- pipeline for exactly one unambiguous candidate control: if the control
-- already reads back the requested device name, it reports confirmed
-- success without clicking anything; otherwise it clicks the control and
-- the requested device item, then polls readControlSelectionValue
-- (bounded by confirmationTimeoutSeconds / confirmationPollInterval)
-- until the resulting value exactly matches (via namesMatch), a click
-- failure is observed, or the timeout expires. Returns {true, ""} only
-- once the resulting value has actually been read back and matched, or
-- {false, reason} identifying why it could not be confirmed (no
-- candidate, ambiguous candidates, the device item itself being
-- unavailable, or the resulting value never matching/being unreadable)
-- -- never a silently swallowed failure or a click-only success.
on selectDeviceFromCandidates(procName, candidates, deviceName, controlLabel)
  if (count of candidates) is 0 then
    return {false, "no control found matching \"" & controlLabel & "\""}
  end if
  if (count of candidates) > 1 then
    return {false, "ambiguous match: " & (count of candidates) & " controls matched \"" & controlLabel & "\""}
  end if
  set theControl to item 1 of candidates

  set preCheck to readControlSelectionValue(procName, theControl)
  set baselineReadable to item 1 of preCheck
  if baselineReadable then
    set baselineValue to item 2 of preCheck
  else
    set baselineValue to "(unread)"
  end if
  if baselineReadable and namesMatch(baselineValue, deviceName) then
    return {true, ""}
  end if

  tell application "System Events"
    tell process procName
      try
        click theControl
        delay 0.3
      on error errMsg number errNum
        return {false, "clicking the matched control for \"" & deviceName & "\" failed: " & errMsg & " (error " & errNum & ")"}
      end try
      if not (exists (first menu item whose title is deviceName) of menu 1 of theControl) then
        return {false, "device item \"" & deviceName & "\" not found in the matched control's menu"}
      end if
      try
        click (first menu item whose title is deviceName) of menu 1 of theControl
      on error errMsg number errNum
        return {false, "clicking device item \"" & deviceName & "\" failed: " & errMsg & " (error " & errNum & ")"}
      end try
    end tell
  end tell

  set elapsed to 0
  set lastReadable to false
  set lastValue to "(unread)"
  repeat
    set readResult to readControlSelectionValue(procName, theControl)
    if item 1 of readResult then
      set lastReadable to true
      set lastValue to item 2 of readResult
      if namesMatch(lastValue, deviceName) then
        return {true, ""}
      end if
    end if
    if elapsed >= confirmationTimeoutSeconds then exit repeat
    delay confirmationPollInterval
    set elapsed to elapsed + confirmationPollInterval
  end repeat
  if lastReadable then
    if baselineReadable and namesMatch(lastValue, baselineValue) then
      return {false, "clicked \"" & deviceName & "\" on the matched control but the selection remained unchanged within " & confirmationTimeoutSeconds & "s (still \"" & lastValue & "\")"}
    else
      return {false, "clicked \"" & deviceName & "\" on the matched control but a different device became selected within " & confirmationTimeoutSeconds & "s (observed \"" & lastValue & "\", expected \"" & deviceName & "\")"}
    end if
  else
    return {false, "clicked \"" & deviceName & "\" on the matched control but its resulting value could not be read to confirm the change"}
  end if
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
  set camDiagnostic to "no strategy has been attempted yet"
  set micPicked to false
  set micDiagnostic to "no strategy has been attempted yet"

  -- Strategy 1: exact menu route (preferred when its labels match).
  -- confirmMenuSelection's captured diagnostic becomes the starting
  -- camDiagnostic/micDiagnostic value, so a menu-route failure is never
  -- replaced by a generic placeholder -- if Strategy 2 also fails below,
  -- both the menu route's real error and the fallback's real error are
  -- preserved.
  set camMenuResult to confirmMenuSelection(zoomProcessName, meetingMenuLabel, cameraMenuLabel, desiredCamera)
  if item 1 of camMenuResult then
    set camPicked to true
  else
    set camDiagnostic to item 2 of camMenuResult
  end if
  set micMenuResult to confirmMenuSelection(zoomProcessName, meetingMenuLabel, microphoneMenuLabel, desiredMic)
  if item 1 of micMenuResult then
    set micPicked to true
  else
    set micDiagnostic to item 2 of micMenuResult
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
    set end of failureParts to "camera \"" & desiredCamera & "\" was not confirmed selected (" & camDiagnostic & ")"
  end if
  if not micPicked then
    set end of failureParts to "microphone \"" & desiredMic & "\" was not confirmed selected (" & micDiagnostic & ")"
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
