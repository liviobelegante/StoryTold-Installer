# Installed application discovery and release checks.

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

# ----------- Resolve-ApplicationScope ----------
function Resolve-ApplicationScope {
    param([string]$App, [ValidateSet('CurrentUser','AllUsers')][string]$PreferredScope)
    # MSI registration takes precedence, even if its executable is missing.
    $scopes = @(Get-RegisteredMsiScopes $App | Where-Object { $_ -in @('CurrentUser','AllUsers') } | Select-Object -Unique)
    if (-not $scopes.Count) {
        foreach ($scope in @('CurrentUser','AllUsers')) {
            if (Get-LocalApplication $App -Scope $scope) { $scopes += $scope }
        }
    }
    if ($scopes.Count -eq 1) { return $scopes[0] }
    # New app or both scopes: the checkbox selects the target.
    return $PreferredScope
}
# -----------------------------

# ----------- Check-AppVersion ----------
function Check-AppVersion {
    param([string]$App)
    try {
        $script:request.Scope = Resolve-ApplicationScope $App $script:request.Scope
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
        if ($App -eq 'SolidCraft' -and $local -and @(Get-RegisteredMsiScopes $App) -notcontains $script:request.Scope) {
            $state = 'Official installer available'
        }
        Write-Status $App $release.tag_name $state ("Installed: $localText; latest stable: $($release.tag_name); repository: $repo")
    }
    catch {Write-Status $App '' Failed $_.Exception.Message}
}
# -----------------------------


