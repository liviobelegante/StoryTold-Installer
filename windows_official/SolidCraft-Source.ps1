# SolidCraft source builds and local application discovery.

# ----------- Convert-AppVersion ----------
function Convert-AppVersion {
    param([string]$Value)
    if ($Value -match '^v?(\d+)\.(\d+)\.(\d+)(?:\.(\d+))?$') {
        $revision = 0
        if ($Matches[4]) { $revision = [int]$Matches[4] }
        return [version]::new([int]$Matches[1], [int]$Matches[2], [int]$Matches[3], $revision)
    }
    return $null
}
# -----------------------------

# ----------- Get-PathInstallScope ----------
function Get-PathInstallScope {
    param([string]$Path)
    $full = [IO.Path]::GetFullPath($Path)
    if ($full.StartsWith(($env:LOCALAPPDATA.TrimEnd('\') + '\'), [StringComparison]::OrdinalIgnoreCase)) { return 'CurrentUser' }
    foreach ($root in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if ($root -and $full.StartsWith(($root.TrimEnd('\') + '\'), [StringComparison]::OrdinalIgnoreCase)) { return 'AllUsers' }
    }
    return 'Unknown'
}
# -----------------------------

# ----------- Get-ComInstallProperty ----------
function Get-ComInstallProperty {
    param($Object, [string]$Name, [object[]]$Arguments = @())
    return $Object.GetType().InvokeMember($Name, [Reflection.BindingFlags]::GetProperty, $null, $Object, $Arguments)
}
# -----------------------------

# ----------- Get-MsiRegistrations ----------
function Get-MsiRegistrations {
    param([string]$App)
    if ($null -eq $script:msiSnapshot) {
        $installer=$null;$products=$null
        $inventory=@()
        try {
            $installer=New-Object -ComObject WindowsInstaller.Installer
            # Empty SID means current account; context mask 7 also includes machine products.
            $products=$installer.ProductsEx('','',7)
            foreach($product in $products) {
                $name=''
                try {
                    $state=[int](Get-ComInstallProperty $product 'State')
                    if($state -ne 5){continue}
                    $name=[string](Get-ComInstallProperty $product 'InstallProperty' @('ProductName'))
                    if(-not @($catalog | Where-Object {$name -match ('^'+[regex]::Escape($_)+'(?:\s|$)')}).Count){continue}
                    $context=[int](Get-ComInstallProperty $product 'Context')
                    $scope=switch($context){1{'CurrentUser'};2{'CurrentUser'};4{'AllUsers'};default{'Unknown'}}
                    $directory=''
                    try{$directory=[string](Get-ComInstallProperty $product 'InstallProperty' @('InstallLocation'))}catch{}
                    $inventory += [pscustomobject]@{Name=$name;ProductCode=[string](Get-ComInstallProperty $product 'ProductCode');Scope=$scope;Context=$context;Directory=$directory}
                }
                catch {
                    # An unrelated damaged MSI registration must not prevent this GUI from opening.
                    if($name -and @($catalog | Where-Object {$name -match ('^'+[regex]::Escape($_)+'(?:\s|$)')}).Count){throw}
                }
                finally {if($product){[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($product)}}
            }
            $script:msiSnapshot=$inventory
        }
        finally {
            if($products){[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($products)}
            if($installer){[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($installer)}
        }
    }
    return @($script:msiSnapshot | Where-Object {$_.Name -match ('^'+[regex]::Escape($App)+'(?:\s|$)')})
}
# -----------------------------

# ----------- Get-LocalApplication ----------
function Get-LocalApplication {
    param([string]$App, [string]$Scope = 'Any')
    $repo = $App.ToLowerInvariant()
    $candidates = [Collections.Generic.List[string]]::new()
    $managed = Join-Path $env:LOCALAPPDATA 'Programs\StoryToldCraft\SolidCraft\solidcraft.exe'
    if ($App -eq 'SolidCraft') { $candidates.Add($managed) }
    $programs = ${env:ProgramFiles(x86)}
    if (-not $programs) { $programs = $env:ProgramFiles }
    $legacyFolder = $repo + '-main'
    if ($App -eq 'SolidCraft') { $legacyFolder = 'solid-main' }
    $legacyExecutable = Join-Path $programs ('StoryTold\' + $legacyFolder + '\target\release\' + $repo + '.exe')
    $candidates.Add($legacyExecutable)
    if ($null -eq $script:registrySnapshot) {
        $script:registrySnapshot = @()
        foreach ($registry in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKCU:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')) {
            $script:registrySnapshot += @(Get-ItemProperty ($registry + '\*') -ErrorAction SilentlyContinue)
        }
    }
    foreach ($entry in $script:registrySnapshot) {
            if ($entry.DisplayName -notmatch ('^' + [regex]::Escape($App) + '(?:\s|$)')) { continue }
            if ($entry.InstallLocation) { $candidates.Add((Join-Path $entry.InstallLocation ($repo + '.exe'))) }
            if ($entry.DisplayIcon -match '^"?(.+?\.exe)"?(?:,\s*-?\d+)?$') { $candidates.Add($Matches[1]) }
    }
    $msiRegistrations=@()
    if($App) {
        $msiRegistrations=@(Get-MsiRegistrations $App)
        foreach($registration in $msiRegistrations){if($registration.Directory){$candidates.Add((Join-Path $registration.Directory ($repo+'.exe')))}}
    }
    foreach ($root in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, (Join-Path $env:LOCALAPPDATA 'Programs'))) {
        if (-not $root) { continue }
        foreach ($folder in @($App, ('ArtCraft\' + $App), ('StoryTold\' + $App))) {
            $candidates.Add((Join-Path $root ($folder + '\' + $repo + '.exe')))
            # Older installers used one version-named subdirectory per release.
            $appRoot = Join-Path $root $folder
            if ($App -eq 'SolidCraft' -and (Test-Path -LiteralPath $appRoot -PathType Container)) {
                foreach ($versionFolder in @(Get-ChildItem -LiteralPath $appRoot -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^v?\d+\.\d+\.\d+(?:\.\d+)?$' -and -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) })) {
                    $candidates.Add((Join-Path $versionFolder.FullName 'solidcraft.exe'))
                }
            }
        }
    }
    $shell = $null
    $link = $null
    try {
        $shell = New-Object -ComObject WScript.Shell
        foreach ($desktop in @([Environment]::GetFolderPath('DesktopDirectory'),[Environment]::GetFolderPath('CommonDesktopDirectory'))) {
            if ($desktop -and (Test-Path -LiteralPath (Join-Path $desktop ($App + '.lnk')))) {
                $link = $shell.CreateShortcut((Join-Path $desktop ($App + '.lnk')))
                if ($link.TargetPath) { $candidates.Add($link.TargetPath) }
                [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($link)
                $link = $null
            }
        }
    }
    finally {
        if ($link) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($link) }
        if ($shell) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell) }
    }
    $found = @()
    foreach ($path in @($candidates | Select-Object -Unique)) {
        if ([IO.Path]::GetFileName($path) -ine ($repo + '.exe') -or -not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
        $info = [Diagnostics.FileVersionInfo]::GetVersionInfo($path)
        $versionText = $info.ProductVersion
        if (-not $versionText) { $versionText = $info.FileVersion }
        $kind = 'Existing installation'
        $commit = ''
        if ($App -eq 'SolidCraft' -and ($path -ieq $managed -or $path -ieq $legacyExecutable)) {
            $receiptPath = Join-Path (Split-Path -LiteralPath $path) 'build-receipt.json'
            if (Test-Path -LiteralPath $receiptPath) {
                try {
                    $receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
                    if ($receipt.Sha256 -eq (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash) {
                        $versionText = $receipt.Version
                        $commit = $receipt.Commit
                        $kind = 'Managed source build'
                    }
                    else { $versionText = ''; $kind = 'Modified managed build' }
                }
                catch { $versionText = ''; $kind = 'Unreadable managed receipt' }
            }
        }
        $number = Convert-AppVersion $versionText
        $installScope = Get-PathInstallScope $path
        foreach ($entry in $script:registrySnapshot) {
            if ($entry.WindowsInstaller -ne 1 -or $entry.DisplayName -notmatch ('^' + [regex]::Escape($App) + '(?:\s|$)')) {continue}
            if (($entry.InstallLocation -and $path.StartsWith(($entry.InstallLocation.TrimEnd('\') + '\'),[StringComparison]::OrdinalIgnoreCase)) -or ($entry.DisplayIcon -and $entry.DisplayIcon.Trim('"') -like ($path + '*'))) {
                $registered=@($msiRegistrations | Where-Object {$_.ProductCode -ieq $entry.PSChildName})
                if($registered.Count -eq 1 -and $registered[0].Scope -ne 'Unknown'){$installScope=$registered[0].Scope}
            }
        }
        foreach($registration in $msiRegistrations){
            if($registration.Directory -and $path.StartsWith(($registration.Directory.TrimEnd('\')+'\'),[StringComparison]::OrdinalIgnoreCase) -and $registration.Scope -ne 'Unknown'){$installScope=$registration.Scope}
        }
        if ($Scope -ne 'Any' -and $installScope -ne $Scope) {continue}
        $found += [pscustomobject]@{ Version=$versionText; Number=$number; Path=$path; Kind=$kind; Commit=$commit; Scope=$installScope }
    }
    if ($found.Count) { return ($found | Sort-Object -Property Number -Descending | Select-Object -First 1) }
    return $null
}
# -----------------------------

# ----------- Get-RegisteredMsiScopes ----------
function Get-RegisteredMsiScopes {
    param([string]$App)
    return @((Get-MsiRegistrations $App) | ForEach-Object Scope | Select-Object -Unique)
}
# -----------------------------

# ----------- Check-AppVersion ----------
function Check-AppVersion {
    param([string]$App)
    try {
        $local = Get-LocalApplication $App -Scope $script:request.Scope
        $localText='Not detected'
        if ($local) { $localText=$local.Version; if (-not $localText) {$localText='Unknown version'} }
        Write-Status $App '' 'Local version' $localText
        $repo='storytold/' + $App.ToLowerInvariant()
        if ($App -eq 'SolidCraft') { $repo='tangency-labs/solidcraft' }
        $release=Invoke-RestMethod ("https://api.github.com/repos/$repo/releases/latest") -Headers $headers -TimeoutSec 60
        $latest=Convert-AppVersion $release.tag_name
        if ($release.draft -or $release.prerelease -or -not $latest) {throw 'Unsupported stable release version.'}
        $state='Install available'
        if ($local) {
            $state='Version unknown'
            if ($local.Number) {
                $state='Update available'
                if ($local.Number -ge $latest) {$state='Up to date'}
            }
        }
        if ($App -eq 'SolidCraft' -and $local -and $local.Kind -eq 'Managed source build' -and $local.Number -eq $latest) {
            $commitInfo=Invoke-RestMethod ('https://api.github.com/repos/tangency-labs/solidcraft/commits/' + [uri]::EscapeDataString($release.tag_name)) -Headers $headers -TimeoutSec 60
            if ($commitInfo.sha -notmatch '^[a-f0-9]{40}$') {throw 'Invalid source commit.'}
            if ($local.Commit -ne $commitInfo.sha) {$state='Update available'}
        }
        Write-Status $App $release.tag_name $state ("Installed: $localText; latest stable: $($release.tag_name); repository: $repo")
        if ($App -ne 'SolidCraft') {
            $opposite='AllUsers'
            if ($script:request.Scope -eq 'AllUsers') {$opposite='CurrentUser'}
            if (@(Get-RegisteredMsiScopes $App) -contains $opposite) {Write-Status $App $release.tag_name 'Scope change required' 'The official MSI requires uninstalling the existing copy before changing installation scope. No automatic uninstall is performed.'}
        }
    }
    catch {Write-Status $App '' Failed $_.Exception.Message}
}
# -----------------------------

# ----------- Invoke-BuildCommand ----------
function Invoke-BuildCommand {
    param([string]$Executable, [string]$Arguments, [string]$Directory, [string]$Name)
    $stdout = Join-Path $RunFolder ($Name + '-output.log')
    $stderr = Join-Path $RunFolder ($Name + '-error.log')
    $state = 'Preparing / building'
    if ($Name -eq 'cargo-build') { $state = 'Compiling' }
    Write-Status SolidCraft '' $state ("$Name. Output: $stdout; progress/errors: $stderr")
    $process = Start-Process -FilePath $Executable -ArgumentList $Arguments -WorkingDirectory $Directory -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    if ($process.ExitCode -eq 3010) {
        $script:dependencyRestartRequired = $true
        Write-Status '' '' 'Dependency restart required' ("$Name requires a Windows restart.")
    }
    if ($process.ExitCode -notin @(0,3010)) { throw "$Name failed (exit $($process.ExitCode)). See $stderr" }
}
# -----------------------------

# ----------- Find-BuildTool ----------
function Find-BuildTool {
    param([string]$Name)
    $command = Get-Command $Name -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { return $command.Source }
    $fallbacks = @((Join-Path $env:USERPROFILE ('.cargo\bin\' + $Name)))
    if ($script:originalCargoHome) { $fallbacks = @((Join-Path $script:originalCargoHome ('bin\' + $Name))) + $fallbacks }
    if ($Name -eq 'winget.exe') { $fallbacks += (Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe') }
    if ($Name -eq 'git.exe') { $fallbacks += (Join-Path $env:ProgramFiles 'Git\cmd\git.exe') }
    foreach ($path in $fallbacks) { if (Test-Path -LiteralPath $path -PathType Leaf) { return $path } }
    return $null
}
# -----------------------------

# ----------- Install-BuildPrerequisites ----------
function Install-BuildPrerequisites {
    param([bool]$AllowSetup)
    # Keep the public function and the existing checkbox, centralize detailed checks.
    Install-RequiredBuildTools $AllowSetup
}
# -----------------------------

# ----------- Get-SourceGitArguments ----------
function Get-SourceGitArguments {
    param([string]$Directory)
    # FAT/exFAT do not retain ownership. Trust only this operation's checked source
    # directory, for these Git invocations; never change global safe.directory.
    $work = Get-InstallerWorkFolder $script:WorkFolder ([string]$script:request.WorkId)
    $prefix = [IO.Path]::Combine($work,'source') + '\'
    $full = [IO.Path]::GetFullPath($Directory)
    if (-not $full.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)) { throw 'Git source path is outside the owned work folder.' }
    Assert-PlainDirectoryPath $full
    return @('-c', ('safe.directory=' + $full.Replace('\','/')))
}
# -----------------------------

# ----------- Test-SourceCurrent ----------
function Test-SourceCurrent {
    param($Local, [string]$Version, [string]$Commit)
    if (-not $Local -or -not $Local.Number) { return $false }
    $latest = Convert-AppVersion $Version
    if (-not $latest) { throw "Unsupported stable version: $Version" }
    if ($Local.Number -gt $latest) { return $true }
    if ($Local.Number -eq $latest) {
        if ($Local.Kind -eq 'Managed source build') { return $Local.Commit -eq $Commit }
        return $true
    }
    return $false
}
# -----------------------------

# ----------- Publish-SourceBuild ----------
function Publish-SourceBuild {
    param([string]$Binary, [string]$Destination, [string]$Version, [string]$Commit)
    if (@(Get-Process -Name solidcraft -ErrorAction SilentlyContinue).Count) { throw 'SolidCraft is running. Save your work and close it before retrying.' }
    $Destination = [IO.Path]::GetFullPath($Destination)
    if ($Destination.TrimEnd('\') -eq [IO.Path]::GetPathRoot($Destination).TrimEnd('\')) { throw 'Refusing to replace a volume root.' }
    Assert-PlainDirectoryPath $Destination
    $parent = Split-Path -LiteralPath $Destination
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    $stage = Join-Path $parent ('SolidCraft-stage-' + [guid]::NewGuid().ToString('N'))
    $backup = Join-Path $parent ('SolidCraft-backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $stage | Out-Null
    $moved = $false
    try {
        Copy-Item -LiteralPath $Binary -Destination (Join-Path $stage 'solidcraft.exe')
        $hash = (Get-FileHash -LiteralPath $Binary -Algorithm SHA256).Hash
        if ((Get-FileHash (Join-Path $stage 'solidcraft.exe')).Hash -ne $hash) { throw 'Staged executable checksum mismatch.' }
        [ordered]@{ Version=$Version; Commit=$Commit; Sha256=$hash; Architecture=$Architecture; Source='https://github.com/tangency-labs/solidcraft'; BuiltAt=(Get-Date -Format o) } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $stage 'build-receipt.json') -Encoding UTF8
        if (Test-Path -LiteralPath $Destination) { Move-Item -LiteralPath $Destination -Destination $backup; $moved = $true }
        try { Move-Item -LiteralPath $stage -Destination $Destination }
        catch { if ($moved) { Move-Item -LiteralPath $backup -Destination $Destination }; throw }
        if ($moved) { Write-Status SolidCraft $Version 'Backup saved' $backup }
        return (Join-Path $Destination 'solidcraft.exe')
    }
    finally {
        # Only remove the uniquely named staging directory under this installation's parent.
        if (Test-Path -LiteralPath $stage) {
            $fullStage = [IO.Path]::GetFullPath($stage)
            if ((Split-Path -LiteralPath $fullStage) -eq [IO.Path]::GetFullPath($parent) -and [IO.Path]::GetFileName($fullStage) -like 'SolidCraft-stage-*') { Remove-Item -LiteralPath $fullStage -Recurse -Force }
        }
    }
}
# -----------------------------

# ----------- Invoke-SourcePublication ----------
function Invoke-SourcePublication {
    param([string]$Binary, [string]$Destination, [string]$Version, [string]$Commit)
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    $protected = $false
    foreach ($root in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if ($root -and [IO.Path]::GetFullPath($Destination).StartsWith(([IO.Path]::GetFullPath($root).TrimEnd('\') + '\'), [StringComparison]::OrdinalIgnoreCase)) { $protected = $true }
    }
    if ($isAdmin -or -not $protected) { return (Publish-SourceBuild $Binary $Destination $Version $Commit) }
    $guard = [IO.File]::Open($Binary, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        $resultFile = Join-Path $RunFolder ('publication-' + [guid]::NewGuid().ToString('N') + '.json')
        $payloadHash = (Get-FileHash -LiteralPath $Binary -Algorithm SHA256).Hash
        $packet = @{ Binary=$Binary; Destination=$Destination; Version=$Version; Commit=$Commit; Architecture=$Architecture; RunFolder=$RunFolder; ResultFile=$resultFile; Sha256=$payloadHash } | ConvertTo-Json -Compress
        $packetBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($packet))
        # Pass a snapshot of the reviewed publication code, not an editable script path, to UAC.
        $helper = '$ErrorActionPreference="Stop"' + "`n"
        foreach ($name in @('Assert-PlainDirectoryPath','Write-Status','Publish-SourceBuild')) {
            $helper += '# ----------- ' + $name + " ----------`nfunction " + $name + " {`n" + (Get-Command $name -CommandType Function).Definition + "`n}`n# -----------------------------`n"
        }
        $helper += '$data=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String("' + $packetBase64 + '")) | ConvertFrom-Json' + "`n"
        $helper += @'
$RunFolder=$data.RunFolder
$Architecture=$data.Architecture
try {
    if ((Get-FileHash -LiteralPath $data.Binary -Algorithm SHA256).Hash -ne $data.Sha256) {throw 'Publication payload checksum mismatch.'}
    $path=Publish-SourceBuild $data.Binary $data.Destination $data.Version $data.Commit
    @{Success=$true;Path=$path} | ConvertTo-Json | Set-Content -LiteralPath $data.ResultFile -Encoding UTF8
    exit 0
}
catch {
    @{Success=$false;Error=$_.Exception.Message} | ConvertTo-Json | Set-Content -LiteralPath $data.ResultFile -Encoding UTF8
    exit 1
}
'@
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($helper))
        Write-Status SolidCraft $Version 'Administrator approval' ("Publishing to $Destination. Accept the Windows UAC prompt.")
        $process = Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList ('-NoLogo -NoProfile -ExecutionPolicy Bypass -EncodedCommand ' + $encoded) -Verb RunAs -WindowStyle Hidden -Wait -PassThru
        if (-not (Test-Path -LiteralPath $resultFile)) { throw "Publication did not finish (exit $($process.ExitCode)). Administrator approval may have been declined." }
        $result = Get-Content -LiteralPath $resultFile -Raw | ConvertFrom-Json
        if ($process.ExitCode -ne 0 -or -not $result.Success) { throw ("Publication failed: " + $result.Error) }
        $expected = Join-Path $Destination 'solidcraft.exe'
        # The caller compares against its own hash, not a hash supplied by the result file.
        if ($result.Path -ine $expected -or (Get-FileHash -LiteralPath $expected).Hash -ne $payloadHash) { throw 'Installed executable does not match the compiled payload.' }
        return $expected
    }
    finally { $guard.Dispose() }
}
# -----------------------------

# ----------- Install-SolidCraftSource ----------
function Install-SolidCraftSource {
    $version = ''
    try {
        $local = Get-LocalApplication SolidCraft -Scope $script:request.Scope
        if (-not $local) {
            $other = Get-LocalApplication SolidCraft
            if ($other) { Write-Status SolidCraft '' 'Other scope exists' ("Existing copy: $($other.Path) ($($other.Scope)). The selected $($script:request.Scope) scope uses a separate destination; the existing copy will be preserved.") }
        }
        Write-Status SolidCraft '' Checking 'Checking tangency-labs/solidcraft and local installations.'
        $release = Invoke-RestMethod 'https://api.github.com/repos/tangency-labs/solidcraft/releases/latest' -Headers $headers -TimeoutSec 60
        if ($release.draft -or $release.prerelease -or -not (Convert-AppVersion $release.tag_name)) { throw 'No supported stable SolidCraft version was found.' }
        $version = $release.tag_name
        $commitInfo = Invoke-RestMethod ('https://api.github.com/repos/tangency-labs/solidcraft/commits/' + [uri]::EscapeDataString($version)) -Headers $headers -TimeoutSec 60
        $commit = [string]$commitInfo.sha
        if ($commit -notmatch '^[a-f0-9]{40}$') { throw 'Invalid source commit received from GitHub.' }
        Write-Status SolidCraft $version 'Source verified' ("Release: $version; commit: $commit")
        if (Test-SourceCurrent $local $version $commit) {
            Install-SolidCraftRuntime (Get-ExecutableArchitecture $local.Path)
            $detail = "Installed $($local.Version) at $($local.Path). No build required."
            try { $detail += ' Shortcut: ' + (New-ApplicationShortcut SolidCraft $local.Path); $state='Up to date' }
            catch { $detail += ' Shortcut warning: ' + $_.Exception.Message; $state='Up to date (shortcut warning)' }
            Write-Status SolidCraft $version $state $detail
            return
        }
        Close-RunningApplication SolidCraft
        Install-BuildPrerequisites ([bool]$script:request.SetupBuildTools)
        $cache = Join-Path $script:WorkFolder ('source\' + $commit + '-' + $Architecture)
        New-Item -ItemType Directory -Path $cache -Force | Out-Null
        $git = Find-BuildTool git.exe
        $gitSafe = @(Get-SourceGitArguments $cache)
        $gitPrefix = '-c "' + $gitSafe[1] + '" '
        if (-not (Test-Path -LiteralPath (Join-Path $cache '.git'))) { Invoke-BuildCommand $git ($gitPrefix + 'init') $cache 'git-init' }
        else {
            $dirty = & $git @gitSafe -C $cache status --porcelain --untracked-files=all
            if ($LASTEXITCODE -ne 0 -or $dirty) { throw 'Source cache contains modified or untracked files. Refusing to overwrite it.' }
        }
        Invoke-BuildCommand $git ($gitPrefix + 'fetch --depth 1 https://github.com/tangency-labs/solidcraft.git ' + $commit) $cache 'git-fetch'
        Invoke-BuildCommand $git ($gitPrefix + 'checkout --detach --force ' + $commit) $cache 'git-checkout'
        # This cache belongs to the installer. Refuse dirty sources rather than compiling modified code.
        $head = & $git @gitSafe -C $cache rev-parse HEAD
        if ($LASTEXITCODE -ne 0 -or $head -ne $commit) { throw 'Fetched source commit does not match the release.' }
        $dirty = & $git @gitSafe -C $cache status --porcelain --untracked-files=all
        if ($LASTEXITCODE -ne 0 -or $dirty) { throw 'Source cache contains modified or untracked files. Use a clean cache before building.' }
        $manifest = [IO.File]::ReadAllText((Join-Path $cache 'Cargo.toml'))
        if ($manifest -notmatch '(?m)^rust-version\s*=\s*"(\d+\.\d+(?:\.\d+)?)"') { throw 'Required Rust version is not specified in Cargo.toml.' }
        $minimumText = $Matches[1]
        if (($minimumText -split '\.').Count -eq 2) { $minimumText += '.0' }
        $minimum = [version]$minimumText
        $rustup = Find-BuildTool rustup.exe
        $rustVersion = Get-RustStableVersion $rustup
        if (-not $rustVersion -or $rustVersion -lt $minimum) {
            if (-not $script:request.SetupBuildTools) { throw "Rust stable $minimum or newer is required. Enable build-tool setup." }
            Invoke-BuildCommand $rustup 'toolchain install stable --profile minimal' $cache 'rust-update'
            $rustVersion = Get-RustStableVersion $rustup
            if (-not $rustVersion -or $rustVersion -lt $minimum) { throw 'Rust stable could not be verified after setup.' }
        }
        $target = switch ($Architecture) { x64 {'x86_64-pc-windows-msvc'}; arm64 {'aarch64-pc-windows-msvc'}; x86 {'i686-pc-windows-msvc'}; default {throw 'Unsupported build architecture.'} }
        $targets = @(& $rustup target list --installed --toolchain stable)
        if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect installed Rust targets.' }
        if ($targets -notcontains $target) {
            if (-not $script:request.SetupBuildTools) { throw "Rust target $target is missing. Enable build-tool setup." }
            Invoke-BuildCommand $rustup ('target add ' + $target + ' --toolchain stable') $cache 'rust-target'
            $targets = @(& $rustup target list --installed --toolchain stable)
            if ($LASTEXITCODE -ne 0 -or $targets -notcontains $target) { throw 'Rust target could not be verified after setup.' }
        }
        Write-Status SolidCraft $version Compiling 'Compiling desktop app from the pinned stable release. The first build can take a long time. See cargo-build-error.log for progress.'
        Invoke-BuildCommand $rustup ('run stable cargo build --locked --release --target ' + $target + ' --target-dir "' + (Join-Path $cache 'target') + '" -p solidcraft') $cache 'cargo-build'
        $binary = Join-Path $cache ('target\' + $target + '\release\solidcraft.exe')
        if (-not (Test-Path -LiteralPath $binary -PathType Leaf)) { throw 'Build finished without the expected solidcraft.exe.' }
        $builtVersion = [Diagnostics.FileVersionInfo]::GetVersionInfo($binary).ProductVersion
        if ((Convert-AppVersion $builtVersion) -ne (Convert-AppVersion $version)) { throw 'Compiled executable version does not match the stable release.' }
        Install-SolidCraftRuntime (Get-ExecutableArchitecture $binary)
        $programs = ${env:ProgramFiles(x86)}
        if (-not $programs) { $programs = $env:ProgramFiles }
        $destination = Join-Path $programs 'StoryTold\solid-main\target\release'
        if ($script:request.Scope -eq 'CurrentUser') {$destination=Join-Path $env:LOCALAPPDATA 'Programs\StoryToldCraft\SolidCraft'}
        if ($local -and (Split-Path -LiteralPath $local.Path) -ine $destination) {
            Write-Status SolidCraft $version 'Installation location' ("The existing copy at $($local.Path) is not in this installer's managed directory. It will be preserved; the new source build and shortcut use $destination.")
        }
        # A user may have reopened the application during a long source build.
        Close-RunningApplication SolidCraft
        $installed = Invoke-SourcePublication $binary $destination $version $commit
        $detail = "Installed source build $version ($commit) at $installed. Locally compiled executable is unsigned."
        try { $detail += ' Shortcut: ' + (New-ApplicationShortcut SolidCraft $installed); $state='Installed' }
        catch { $detail += ' Shortcut warning: ' + $_.Exception.Message; $state='Installed (shortcut warning)' }
        Write-Status SolidCraft $version $state $detail
    }
    catch { Write-Status SolidCraft $version Failed $_.Exception.Message }
}
# -----------------------------
