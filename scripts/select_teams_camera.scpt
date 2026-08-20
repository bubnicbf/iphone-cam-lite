-- Selects the configured camera and microphone in Microsoft Teams' own UI.
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
-- Camera and microphone success are tracked independently; the script
-- only succeeds once both are confirmed selected, and raises one
-- actionable error identifying the failed stage otherwise.
--
-- Known limitation: this remains UI/accessibility scripting, not an
-- official Teams automation API. A Teams release that removes the
-- Settings/Devices panel entirely, moves device selection into a
-- different surface (e.g. an in-meeting-only control), or requires an
-- unlisted extra step is outside what label overrides alone can fix.

property desiredCamera : "iPhone Camera"
property desiredMic : "iPhone Microphone"
property appName : "Microsoft Teams"
property settingsMenuLabel : "Settings"
property devicesLabel : "Devices"
property cameraControlLabel : "Camera"
property microphoneControlLabel : "Microphone"

-- resolveArg returns argv's idx-th item if present and non-empty,
-- otherwise defaultValue.
on resolveArg(argv, idx, defaultValue)
  if (count of argv) >= idx then
    set candidateValue to item idx of argv
    if candidateValue is not "" then return candidateValue
  end if
  return defaultValue
end resolveArg

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

-- selectDeviceFromCandidates: see select_zoom_camera.scpt for the
-- identical rationale (exactly one unambiguous candidate, explicit
-- success/failure result, never a silent guess).
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
        delay 0.2
        click (first menu item whose title is deviceName) of menu 1 of theControl
        return {true, ""}
      on error errMsg number errNum
        return {false, "device item \"" & deviceName & "\" unavailable on the matched control: " & errMsg & " (error " & errNum & ")"}
      end try
    end tell
  end tell
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
  error "Teams device selection failed: " & failureText
end run
