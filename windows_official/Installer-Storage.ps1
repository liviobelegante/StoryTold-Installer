# Temporary work directories belong to one installer operation only.

# ----------- Assert-PlainDirectoryPath ----------
function Assert-PlainDirectoryPath {
    param([string]$Path)
    $current = [IO.Path]::GetFullPath($Path)
    while ($current) {
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force
            if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                throw "Unsafe temporary directory or redirected path: $current"
            }
        }
        $parent = Split-Path -LiteralPath $current
        if ($parent -eq $current) { break }
        $current = $parent
    }
}
# -----------------------------

# ----------- New-InstallerWorkFolder ----------
function New-InstallerWorkFolder {
    param([string]$Id, [string[]]$Roots = @('D:\Temp','C:\Temp',([IO.Path]::Combine($env:LOCALAPPDATA,'Temp'))))
    if ($Id -notmatch '^[a-f0-9]{32}$') { throw 'Invalid temporary operation identifier.' }
    $failures = @()
    foreach ($root in $Roots) {
        try {
            $volume = [IO.Path]::GetPathRoot([IO.Path]::GetFullPath($root))
            if (-not (Test-Path -LiteralPath $volume -PathType Container)) { continue }
            $folder = [IO.Path]::GetFullPath((Join-Path $root ('StoryToldCraft\' + $Id)))
            Assert-PlainDirectoryPath $folder
            if (Test-Path -LiteralPath $folder) { throw 'Temporary operation folder already exists.' }
            New-Item -ItemType Directory -Path $folder -Force | Out-Null
            @{Owner='StoryToldCraftInstaller'; Id=$Id} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $folder '.storytold-work.json') -Encoding UTF8
            return $folder
        }
        catch { $failures += $_.Exception.Message }
    }
    throw ('Cannot create a writable temporary folder in: ' + ($Roots -join ', ') + '. ' + ($failures -join ' '))
}
# -----------------------------

# ----------- Get-InstallerWorkFolder ----------
function Get-InstallerWorkFolder {
    param([string]$Path, [string]$Id, [string[]]$Roots = @('D:\Temp','C:\Temp',([IO.Path]::Combine($env:LOCALAPPDATA,'Temp'))), [switch]$AllowMissing)
    if ($Id -notmatch '^[a-f0-9]{32}$') { throw 'Invalid cleanup identifier.' }
    $fullPath = [IO.Path]::GetFullPath($Path)
    # Build allowed paths without accessing drives: the preferred D: drive may be absent.
    # Keep the exact operation-folder allowlist and ownership checks unchanged.
    $allowed = @($Roots | ForEach-Object { [IO.Path]::GetFullPath([IO.Path]::Combine($_, ('StoryToldCraft\' + $Id))) })
    if ($fullPath -notin $allowed) { throw "Cleanup refused outside the owned temporary folder: $fullPath" }
    if (-not (Test-Path -LiteralPath $fullPath)) {
        if ($AllowMissing) { return $fullPath }
        throw 'Owned temporary folder is missing.'
    }
    Assert-PlainDirectoryPath $fullPath
    $marker = Join-Path $fullPath '.storytold-work.json'
    if ((Get-Item -LiteralPath $marker -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Cleanup marker is redirected.' }
    $receipt = Get-Content -LiteralPath $marker -Raw | ConvertFrom-Json
    if ($receipt.Owner -ne 'StoryToldCraftInstaller' -or $receipt.Id -ne $Id) { throw 'Cleanup ownership marker does not match.' }
    return $fullPath
}
# -----------------------------

# ----------- Remove-InstallerWorkFolder ----------
function Remove-InstallerWorkFolder {
    param([string]$Path, [string]$Id, [string[]]$Roots = @('D:\Temp','C:\Temp',([IO.Path]::Combine($env:LOCALAPPDATA,'Temp'))))
    $fullPath = Get-InstallerWorkFolder $Path $Id $Roots -AllowMissing
    if (-not (Test-Path -LiteralPath $fullPath)) { return }
    $pending = [Collections.Generic.Stack[string]]::new()
    $pending.Push($fullPath)
    while ($pending.Count) {
        foreach ($entry in @(Get-ChildItem -LiteralPath $pending.Pop() -Force)) {
            if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Cleanup refused because a redirected entry exists: $($entry.FullName)" }
            if ($entry.PSIsContainer) { $pending.Push($entry.FullName) }
        }
    }
    # Both the resolved target and every contained entry were checked before recursive removal.
    Remove-Item -LiteralPath $fullPath -Recurse -Force
}
# -----------------------------
