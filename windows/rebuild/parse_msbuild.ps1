function Parse-MSBuild {
  begin {
    $last_error = @{}
    $skip_note = @{}
    $done = $false
  }
  process {
    $id = ''
    $prefix = '---     '
    # We rely on /consoleloggerparameters:ShowEventId to do the bulk of the
    # work of piecing back the various threads in the log.
    if ($_ -match "^(.*)\s*\(TaskId:(?<id>\d+)\)$") {
      $id = $Matches.id
      $prefix = "TSK" + $id.PadLeft(5)
      $_ = $Matches.1
    } elseif ($_ -match "^(.*)\s*\(TargetId:(?<id>\d+)\)$") {
      $prefix = "TGT" + $Matches.id.PadLeft(5)
      $_ = $Matches.1
    }
    Write-Output "$prefix|$_"
    if ($done -or $_ -eq 'Build FAILED.') {
      $done = $true
      return
    }
    # The first line of errors and warnings seems to invariably be missing a
    # TaskId parenthetical; tie them to the next task that logs.
    if ($last_error[''] -and $id) {
      if ($last_error[$id]) {
        Write-Output $last_error[$id]
      }
      $last_error[$id] = $last_error['']
      $skip_note[$id] = $false
      $last_error[''] = $null
    }
    if ($_ -match "\s*(?<location>(?<file>[^>]*)\((?<line>\d+),(?<column>\d+)\)): (?<title>(?<type>error|warning|message|note)[^:]*): (?<message>.*)") {
      if ($Matches.type -in @('error', 'warning')) {
        if ($last_error['']) {
          Write-Output $last_error['']
        }
        if ($id -and $last_error[$id]) {
          Write-Output $last_error[$id]
        }
        $last_error[''] = $null
        $last_error[$id] = $null
        $skip_note[$id] = $false
        if ($Matches.title -eq 'error C2220') {
          return
        }
        if ($Matches.file.StartsWith($PWD)) {
          $last_error[$id] = "::$($Matches.type) file=$($Matches.file),line=$($Matches.line),col=$($Matches.column),title=$($Matches.title)::$($Matches.message)"
        } else {
          # This error is not in our code. We prefix it with *** both to mark
          # that we need to fill in the file and line if we find a note about
          # our code, and to prevent it from becoming a real annotation if we
          # never figure out where it goes.
          $last_error[$id] = "***::$($Matches.type) file={file},line={line},col={column},title=$($Matches.title)::$($Matches.location):%0A$($Matches.message)"
        }
      } elseif ($last_error[$id]) {
        if ($Matches.file.StartsWith($PWD)) {
          if ($last_error[$id].StartsWith('***') -and ($_.Contains("see reference") -or $_.Contains("see the first reference"))) {
            $last_error[$id] = $last_error[$id].Substring(3).Replace('{file}', $Matches.file).Replace('{line}', $Matches.line).Replace('{column}', $Matches.column)
          }
          $last_error[$id] += "%0A$($Matches.title): $($Matches.message)"
          $skip_note[$id] = $false
        } else {
          $skip_note[$id] = $true
        }
      } else {
        # We have a note and we could not figure out what it’s about.
        # This probably means that we got confused by interspersed logs, and
        # since there are long strings of notes after an error, we would quickly
        # exhaust our limit of 10 annotations.
        # Write down that we noticed it for debugging it, but don’t make it an
        # actual annotation so as not to spam.
        Write-Output "SUPPRESSED::notice file=$($Matches.file),line=$($Matches.line),col=$($Matches.column),title=$($Matches.title)::$($Matches.message)"
      }
    } elseif ($last_error[$id] -and -not $skip_note[$id] -and $_ -notmatch '^         \S') {
      # At 9 spaces we have filenames, commands, etc. which sometimes
      # get interspersed in the logs for one TaskId.  Ignore these.
      # Notes are also at 9 spaces, so we need to have checked that this
      # is not a note already.
      if ($_ -match '.{7} {8}') {
        # Multiline or error message continuation.
        $last_error[$id] += "%0A$_"
      } else {
        Write-Output $last_error[$id]
        $last_error[$id] = $null
        $skip_note[$id] = $false
      }
    }
  }
  end {
    Write-Output $last_error.Values
  }
}