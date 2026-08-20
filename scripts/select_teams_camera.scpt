-- Selects the configured camera and microphone in Microsoft Teams' own UI,
-- and does not report success until the resulting selected value of each
-- pop-up control has actually been read back and confirmed to exactly
-- match the requested device name.
--
-- Command-line arguments (all optional; a missing or empty argument uses
-- the English default noted below, so `osascript select_teams_camera.scpt`
-- with no arguments still behaves as before):
--   1. camera name              (default: "iPhone Camera")
--   2. microphone name          (default: "iPhone Microphone")
--   3. settings menu label      (default: "Settings")
--   4. devices label            (default: "Devices")
--   5. camera control label     (default: "Camera")
--   6. microphone control label (default: "Microphone")
-- scripts/start_teams.sh supplies these from CAMERA_NAME, MICROPHONE_NAME,
-- and the TEAMS_* environment variables documented in README.md.
--
-- Strategy: open Settings via the configured menu label, falling back to
-- Command-comma (a layout-independent shortcut) if the menu route isn't
-- available. Locate the Devices entry point by semantic label match
-- against a bounded set of visible settings windows/sheets and their
-- direct containers -- never assumed to be "window 1" or a fixed AX
-- role -- accepting a button, row, or other selectable navigation
-- element. Locate the camera/microphone pop-up controls the same way.
--
-- A click on a camera/microphone pop-up item is never treated as success
-- by itself: after clicking, the control's resulting value/title is read
-- back and compared against the requested device name with exact text
-- equality (see namesMatch below) before the device counts as confirmed.
-- If the requested device is already selected before any click, that is
-- treated as confirmed success and no click is issued. Confirmation polls
-- a small, bounded number of times (see confirmationTimeoutSeconds /
-- confirmationPollInterval below) rather than waiting indefinitely; if the
-- timeout is reached, or the control's value cannot be read at all, the
-- device is treated as unconfirmed, never as successful. Camera and
-- microphone confirmation are tracked independently; the script only
-- succeeds once both are confirmed, and raises one actionable error
-- identifying the failed stage otherwise.
--
-- Known limitation: this remains UI/accessibility scripting, not an
-- official Teams automation API. Confirmation relies on Teams exposing a
-- readable value/title on its camera/microphone pop-up controls; a Teams
-- release that removes the Settings/Devices panel entirely, moves device
-- selection into a different surface (e.g. an in-meeting-only control),
-- stops exposing a readable control value, or requires an unlisted extra
-- step is outside what label overrides alone can fix -- confirmation will
-- correctly report itself as unavailable rather than assume success in
-- that case.

property desiredCamera : "iPhone Camera"
property desiredMic : "iPhone Microphone"
property appName : "Microsoft Teams"
property settingsMenuLabel : "Settings"
property devicesLabel : "Devices"
property cameraControlLabel : "Camera"
property microphoneControlLabel : "Microphone"

-- Bounded, documented confirmation polling: at most ~12 reads spread over
-- 3 seconds, never an indefinite wait. Small enough to keep a failed
-- launch fast, large enough to absorb Teams' own UI update latency after
-- a click.
property confirmationTimeoutSeconds : 3.0
property confirmationPollInterval : 0.25

-- resolveArg returns argv's idx-th item if present and non-empty,
-- otherwise defaultValue.
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
-- equivalent. Identical to select_zoom_camera.scpt's helper of the same
-- name.
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

-- openSettingsMenu tries the configured Settings menu label under the
-- app's own menu-bar item. Returns {true, ""} only if the click
-- succeeded, or {false, diagnostic} carrying the underlying AppleScript
-- error message and number -- never a silently discarded failure.
on openSettingsMenu(procName, menuLabel)
  tell application "System Events"
    tell process procName
      try
        click menu item menuLabel of menu 1 of menu bar item appName of menu bar 1
        return {true, ""}
      on error errMsg number errNum
        return {false, "Settings menu (" & menuLabel & ") failed: " & errMsg & " (error " & errNum & ")"}
      end try
    end tell
  end tell
end openSettingsMenu

-- openSettingsShortcut is the layout-independent Command-comma fallback.
-- Returns {true, ""} on success, or {false, diagnostic} -- never a
-- silently discarded failure.
on openSettingsShortcut(procName)
  tell application "System Events"
    tell process procName
      try
        keystroke "," using command down
        return {true, ""}
      on error errMsg number errNum
        return {false, "Command-, shortcut failed: " & errMsg & " (error " & errNum & ")"}
      end try
    end tell
  end tell
end openSettingsShortcut

-- relevantWindows: bounded to the process's currently visible windows and
-- their sheets, never assumed to be "window 1". See
-- select_zoom_camera.scpt for the identical rationale.
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

-- boundedContainers: win itself plus its direct groups, scroll areas,
-- tab groups, and toolbars -- a bounded set, not a full-tree walk.
on boundedContainers(procName, win)
  set containerList to {win}
  -- Each lookup below is optional and genuinely harmless: a window
  -- missing a given container class (no groups, no scroll areas, no tab
  -- groups, no toolbars) is normal, not a failure -- win itself is
  -- always still returned, so callers always have at least one
  -- container to search.
  tell application "System Events"
    tell process procName
      try
        set containerList to containerList & (groups of win)
      end try
      try
        set containerList to containerList & (scroll areas of win)
      end try
      try
        set containerList to containerList & (tab groups of win)
      end try
      try
        set containerList to containerList & (toolbars of win)
      end try
    end tell
  end tell
  return containerList
end boundedContainers

-- findNavigationCandidates looks for a Devices-style entry point --
-- accepted as a button, radio button, or row whose title or description
-- matches label -- across the given bounded containers.
on findNavigationCandidates(procName, containerList, label)
  -- Every try below is optional and genuinely harmless: a container
  -- lacking buttons/radio buttons/rows, or a single element lacking a
  -- title/description, simply does not contribute a match -- it never
  -- hides a required failure, since the caller in "on run argv"
  -- explicitly reports "no window exposed a control matching ..." when
  -- matches ends up empty.
  set matches to {}
  tell application "System Events"
    tell process procName
      repeat with c in containerList
        try
          repeat with b in (buttons of c)
            try
              if (title of b is label) or (title of b contains label) or (description of b contains label) then
                set end of matches to b
              end if
            end try
          end repeat
        end try
        try
          repeat with r in (radio buttons of c)
            try
              if (title of r is label) or (description of r contains label) then
                set end of matches to r
              end if
            end try
          end repeat
        end try
        try
          repeat with row_ in (rows of c)
            try
              if (title of row_ contains label) or (description of row_ contains label) then
                set end of matches to row_
              end if
            end try
          end repeat
        end try
      end repeat
    end tell
  end tell
  return matches
end findNavigationCandidates

-- activateCandidate clicks a matched element, falling back to an
-- explicit AXPress action for element kinds (such as static rows) that
-- don't always respond to a plain click. Returns {true, ""} on success,
-- or {false, diagnostic} capturing both the click failure and the
-- AXPress failure -- never a silently discarded failure, and never a
-- generic message that hides which of the two strategies was tried.
on activateCandidate(procName, target)
  tell application "System Events"
    tell process procName
      try
        click target
        return {true, ""}
      on error clickErrMsg number clickErrNum
        try
          perform action "AXPress" of target
          return {true, ""}
        on error pressErrMsg number pressErrNum
          return {false, "click failed: " & clickErrMsg & " (error " & clickErrNum & "); AXPress fallback failed: " & pressErrMsg & " (error " & pressErrNum & ")"}
        end try
      end try
    end tell
  end tell
end activateCandidate

-- findControlCandidates looks for camera/microphone pop-up controls by
-- description or title match across the given bounded containers.
on findControlCandidates(procName, containerList, controlLabel)
  -- Every try below is optional and genuinely harmless: a container
  -- lacking pop-up buttons, or a single element lacking a
  -- description/title, simply does not contribute a match -- it never
  -- hides a required failure, since the caller (selectDeviceFromCandidates)
  -- explicitly reports "no control found" when matches ends up empty.
  set matches to {}
  tell application "System Events"
    tell process procName
      repeat with c in containerList
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
-- could be read -- never assumed to match when unreadable. Identical to
-- select_zoom_camera.scpt's helper of the same name.
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

-- selectDeviceFromCandidates is the full click-and-verify pipeline for
-- exactly one unambiguous candidate control: if the control already reads
-- back the requested device name, it reports confirmed success without
-- clicking anything; otherwise it clicks the control and the requested
-- device item, then polls readControlSelectionValue (bounded by
-- confirmationTimeoutSeconds / confirmationPollInterval) until the
-- resulting value exactly matches (via namesMatch), a click failure is
-- observed, or the timeout expires. Returns {true, ""} only once the
-- resulting value has actually been read back and matched, or
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
        delay 0.2
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
  set settingsMenuLabel to resolveArg(argv, 3, settingsMenuLabel)
  set devicesLabel to resolveArg(argv, 4, devicesLabel)
  set cameraControlLabel to resolveArg(argv, 5, cameraControlLabel)
  set microphoneControlLabel to resolveArg(argv, 6, microphoneControlLabel)

  tell application "System Events"
    if not (exists application process appName) then
      error "Teams is not running (process \"" & appName & "\" not found)."
    end if
  end tell

  tell application "System Events"
    tell process appName
      set frontmost to true
      delay 0.5
    end tell
  end tell

  -- Stage 1: open Settings (configured menu label, then Command-comma).
  -- Each strategy's captured diagnostic is preserved; if both fail, the
  -- final error names both attempted strategies with their real
  -- underlying AppleScript error details rather than a generic message.
  set menuResult to openSettingsMenu(appName, settingsMenuLabel)
  set settingsOpened to item 1 of menuResult
  set settingsDiagnostic to item 2 of menuResult
  if not settingsOpened then
    set shortcutResult to openSettingsShortcut(appName)
    set settingsOpened to item 1 of shortcutResult
    if not settingsOpened then
      set settingsDiagnostic to settingsDiagnostic & "; " & (item 2 of shortcutResult)
    end if
  end if
  if not settingsOpened then
    error "Teams settings could not be opened (" & settingsDiagnostic & ")."
  end if
  delay 0.8

  -- Stage 2: locate and activate the Devices entry point across a
  -- bounded set of currently visible settings windows/sheets.
  set settingsWindows to relevantWindows(appName)
  set devicesActivated to false
  set devicesDiagnostic to "no window exposed a control matching \"" & devicesLabel & "\""
  repeat with w in settingsWindows
    set containerList to boundedContainers(appName, w)
    set navCandidates to findNavigationCandidates(appName, containerList, devicesLabel)
    if (count of navCandidates) > 1 then
      set devicesDiagnostic to "ambiguous match: " & (count of navCandidates) & " controls matched \"" & devicesLabel & "\""
    else if (count of navCandidates) is 1 then
      set activateResult to activateCandidate(appName, item 1 of navCandidates)
      if item 1 of activateResult then
        set devicesActivated to true
        exit repeat
      else
        set devicesDiagnostic to "found a control matching \"" & devicesLabel & "\" but could not activate it: " & (item 2 of activateResult)
      end if
    end if
  end repeat
  if not devicesActivated then
    error "Teams Devices panel could not be located (" & devicesDiagnostic & ")."
  end if
  delay 0.5

  -- Stage 3: select camera and microphone from a (possibly refreshed)
  -- bounded set of visible windows/sheets, tracked independently.
  set deviceWindows to relevantWindows(appName)
  set camPicked to false
  set camDiagnostic to "no control found matching \"" & cameraControlLabel & "\""
  set micPicked to false
  set micDiagnostic to "no control found matching \"" & microphoneControlLabel & "\""
  repeat with w in deviceWindows
    if not camPicked then
      set containerList to boundedContainers(appName, w)
      set camCandidates to findControlCandidates(appName, containerList, cameraControlLabel)
      set camResult to selectDeviceFromCandidates(appName, camCandidates, desiredCamera, cameraControlLabel)
      if item 1 of camResult then
        set camPicked to true
      else
        set camDiagnostic to item 2 of camResult
      end if
    end if
    if not micPicked then
      set containerList to boundedContainers(appName, w)
      set micCandidates to findControlCandidates(appName, containerList, microphoneControlLabel)
      set micResult to selectDeviceFromCandidates(appName, micCandidates, desiredMic, microphoneControlLabel)
      if item 1 of micResult then
        set micPicked to true
      else
        set micDiagnostic to item 2 of micResult
      end if
    end if
    if camPicked and micPicked then exit repeat
  end repeat

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
  error "Teams device selection failed: " & failureText
end run
