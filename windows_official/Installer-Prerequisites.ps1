# Dependency checks for Windows PowerShell and the local SolidCraft source build.
# Official StoryTold MSI applications contain their CRT; they do not need modern .NET.

# ----------- Get-FrameworkRelease ----------
function Get-FrameworkRelease {
    # Read both registry views so a 32-bit launcher also detects the machine runtime.
    $release = 0
    foreach ($view in @([Microsoft.Win32.RegistryView]::Registry64, [Microsoft.Win32.RegistryView]::Registry32)) {
        $base = $null; $key = $null
        try {
            $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey('LocalMachine', $view)
            $key = $base.OpenSubKey('SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full')
            if ($key) { $release = [Math]::Max($release, [int]$key.GetValue('Release', 0)) }
        }
        finally { if ($key) { $key.Dispose() }; if ($base) { $base.Dispose() } }
    }
    return $release
}
# -----------------------------

# ----------- Install-MicrosoftDependency ----------
function Install-MicrosoftDependency {
    param([string]$Name, [string]$Url, [string]$Arguments, [switch]$DownloadOnly)
    # Download only known Microsoft endpoints, verify the publisher and lock the file
    # against changes for the entire installer run. Never force a Windows restart.
    $uri = [uri]$Url
    if ($uri.Scheme -ne 'https' -or $uri.Host -notin @('aka.ms','go.microsoft.com','download.microsoft.com')) {
        throw 'Unapproved prerequisite download address.'
    }
    $directory = Join-Path $script:WorkFolder 'prerequisites'
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $file = Join-Path $directory ($Name + '.exe')
    Write-Status '' '' 'Dependency download' $Name
    Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $file -TimeoutSec 900
    $guard = [IO.File]::Open($file, 'Open', 'Read', 'Read')
    try {
        $signature = Get-AuthenticodeSignature -LiteralPath $file
        if ($signature.Status -ne 'Valid' -or -not $signature.SignerCertificate -or
            $signature.SignerCertificate.Subject -notmatch '(?:^|,\s*)O=Microsoft Corporation(?:,|$)') {
            throw "Invalid Microsoft signature on $Name. Dependency installation blocked."
        }
        if ($DownloadOnly) { return $file }
        Write-Status '' '' 'Installing dependency' "$Name. Windows may request administrator approval."
        $process = Start-Process -FilePath $file -ArgumentList $Arguments -Verb RunAs -WorkingDirectory $directory -Wait -PassThru
        if ($process.ExitCode -in @(3010,1641)) {
            $script:dependencyRestartRequired = $true
            Write-Status '' '' 'Dependency restart required' "$Name requires a Windows restart."
        }
        elseif ($process.ExitCode -ne 0) { throw "$Name failed (exit $($process.ExitCode)). See prerequisite logs in $RunFolder." }
    }
    finally {
        $guard.Dispose()
        if ($Name -eq 'vs-buildtools' -and $env:TEMP -and (Test-Path -LiteralPath $env:TEMP)) {
            # The worker's temporary directory is deleted later; retain VS diagnostics first.
            Get-ChildItem -LiteralPath $env:TEMP -Filter 'dd_*' -File -ErrorAction SilentlyContinue | Copy-Item -Destination $RunFolder -Force -ErrorAction SilentlyContinue
        }
    }
}
# -----------------------------

# ----------- Get-VCInstalledVersion ----------
function Get-VCInstalledVersion {
    param([ValidateSet('x86','x64','arm64')][string]$TargetArchitecture)
    $best = [version]'0.0'
    foreach ($view in @([Microsoft.Win32.RegistryView]::Registry64, [Microsoft.Win32.RegistryView]::Registry32)) {
        $base = $null; $key = $null
        try {
            $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey('LocalMachine', $view)
            $key = $base.OpenSubKey("SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\$TargetArchitecture")
            if ($key -and [int]$key.GetValue('Installed',0) -eq 1) {
                $parsed = $null
                if ([version]::TryParse(([string]$key.GetValue('Version','')).TrimStart('v'), [ref]$parsed) -and $parsed -gt $best) { $best = $parsed }
            }
        }
        finally { if ($key) { $key.Dispose() }; if ($base) { $base.Dispose() } }
    }
    return $best
}
# -----------------------------

# ----------- Install-SolidCraftRuntime ----------
function Install-SolidCraftRuntime {
    param([ValidateSet('x86','x64','arm64')][string]$TargetArchitecture = $Architecture)
    # Our Cargo build uses the dynamic MSVC CRT, unlike the statically linked official MSI apps.
    # Compare against the signed current redistributable, not a guessed minimum version.
    if (-not $script:checkedVCRuntimes) { $script:checkedVCRuntimes = @{} }
    if ($script:checkedVCRuntimes.ContainsKey($TargetArchitecture)) { return }
    $name = 'vc-redist-' + $TargetArchitecture
    $file = Install-MicrosoftDependency $name ("https://aka.ms/vc14/vc_redist.$TargetArchitecture.exe") '' -DownloadOnly
    $guard = [IO.File]::Open($file, 'Open', 'Read', 'Read')
    try {
        # Revalidate after acquiring this lock; DownloadOnly has released its own lock.
        $signature = Get-AuthenticodeSignature -LiteralPath $file
        if ($signature.Status -ne 'Valid' -or -not $signature.SignerCertificate -or
            $signature.SignerCertificate.Subject -notmatch '(?:^|,\s*)O=Microsoft Corporation(?:,|$)') { throw 'VC++ package signature changed.' }
        $info = [Diagnostics.FileVersionInfo]::GetVersionInfo($file)
        $required = [version]::new($info.ProductMajorPart,$info.ProductMinorPart,$info.ProductBuildPart,$info.ProductPrivatePart)
        if ($required.Major -ne 14) { throw 'Unexpected VC++ redistributable version.' }
        if ((Get-VCInstalledVersion $TargetArchitecture) -lt $required) {
            Write-Status SolidCraft '' 'Installing dependency' "Visual C++ v14 $TargetArchitecture ($required)."
            $arguments = '/install /passive /norestart /log "' + (Join-Path $RunFolder ($name + '.log')) + '"'
            $process = Start-Process -FilePath $file -ArgumentList $arguments -Verb RunAs -Wait -PassThru
            if ($process.ExitCode -in @(3010,1641)) {
                $script:dependencyRestartRequired = $true
                Write-Status '' '' 'Dependency restart required' 'Visual C++ runtime requires a Windows restart.'
            }
            elseif ($process.ExitCode -notin @(0,1638)) { throw "Visual C++ runtime installation failed (exit $($process.ExitCode))." }
            # 1638 is accepted only if a same/newer registered runtime really exists.
            if ((Get-VCInstalledVersion $TargetArchitecture) -lt $required) { throw 'Visual C++ runtime could not be verified after installation.' }
        }
        Write-Status SolidCraft '' 'Dependency ready' "Visual C++ v14 $TargetArchitecture is installed."
        $script:checkedVCRuntimes[$TargetArchitecture] = $true
    }
    finally { $guard.Dispose() }
}
# -----------------------------

# ----------- Get-ExecutableArchitecture ----------
function Get-ExecutableArchitecture {
    param([string]$Path)
    # Read the PE header without executing the application (existing copies may be x86).
    $stream = [IO.File]::OpenRead($Path)
    $reader = [IO.BinaryReader]::new($stream)
    try {
        if ($stream.Length -lt 64 -or $reader.ReadUInt16() -ne 0x5A4D) { throw 'Invalid executable header.' }
        $stream.Position = 0x3C; $offset = $reader.ReadUInt32()
        if ($offset -gt $stream.Length - 6) { throw 'Invalid PE offset.' }
        $stream.Position = $offset
        if ($reader.ReadUInt32() -ne 0x4550) { throw 'Invalid PE signature.' }
        switch ($reader.ReadUInt16()) { 0x14C {return 'x86'}; 0x8664 {return 'x64'}; 0xAA64 {return 'arm64'}; default {throw 'Unsupported executable architecture.'} }
    }
    finally { $reader.Dispose() }
}
# -----------------------------

# ----------- Get-WorkingWinget ----------
function Get-WorkingWinget {
    # Bootstrap only when a missing Git/Rust installation actually requires WinGet.
    $winget = Find-BuildTool 'winget.exe'
    if ($winget) { try { & $winget --version *> $null; if ($LASTEXITCODE -eq 0) { return $winget } } catch { } }
    Write-Status SolidCraft '' 'Installing dependency' 'Preparing Microsoft WinGet for missing build tools.'
    $code = @'
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Scope CurrentUser -Force | Out-Null
Install-Module -Name Microsoft.WinGet.Client -Repository PSGallery -Scope CurrentUser -Force -AllowClobber
Import-Module Microsoft.WinGet.Client -ErrorAction Stop
Repair-WinGetPackageManager -Force -Latest
'@
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code))
    Invoke-BuildCommand "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" ('-NoProfile -ExecutionPolicy Bypass -EncodedCommand ' + $encoded) $RunFolder 'setup-winget'
    $winget = Find-BuildTool 'winget.exe'
    if ($winget) { try { & $winget --version *> $null; if ($LASTEXITCODE -eq 0) { return $winget } } catch { } }
    throw 'WinGet setup could not be verified. See setup-winget logs; Windows policy or Store restrictions may prevent installation.'
}
# -----------------------------

# ----------- Get-CppBuildState ----------
function Get-CppBuildState {
    param([ValidateSet('x86','x64','arm64')][string]$TargetArchitecture = $Architecture)
    # Verify the compiler, linker, libraries and a complete SDK, not just vswhere.exe.
    $programs = ${env:ProgramFiles(x86)}
    if (-not $programs) { $programs = $env:ProgramFiles }
    $vswhere = Join-Path $programs 'Microsoft Visual Studio\Installer\vswhere.exe'
    $compiler = $null; $buildTools = $null; $sdk = $null
    if (Test-Path -LiteralPath $vswhere) {
        $instances = & $vswhere -products '*' -format json -utf8 | Out-String | ConvertFrom-Json
        if ($LASTEXITCODE -ne 0) { throw 'Visual Studio inventory failed.' }
        foreach ($instance in @($instances | Sort-Object installationVersion -Descending)) {
            if ($instance.productId -eq 'Microsoft.VisualStudio.Product.BuildTools' -and $instance.installationVersion -like '17.*') { $buildTools = $instance.installationPath }
            if (-not $instance.isComplete -or -not $instance.isLaunchable) { continue }
            $root = Join-Path $instance.installationPath 'VC\Tools\MSVC'
            if (-not (Test-Path -LiteralPath $root)) { continue }
            foreach ($toolset in @(Get-ChildItem -LiteralPath $root -Directory | Sort-Object Name -Descending)) {
                foreach ($hostArch in @('Hostarm64','Hostx64','Hostx86')) {
                    if ($hostArch -eq 'Hostarm64' -and (Get-Architecture) -ne 'arm64') { continue }
                    if ($hostArch -eq 'Hostx64' -and (Get-Architecture) -eq 'x86') { continue }
                    $bin = Join-Path $toolset.FullName ("bin\$hostArch\$TargetArchitecture")
                    $files = @((Join-Path $bin 'cl.exe'),(Join-Path $bin 'link.exe'),(Join-Path $toolset.FullName 'include\vcruntime.h'),(Join-Path $toolset.FullName "lib\$TargetArchitecture\libcmt.lib"))
                    if (@($files | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) }).Count -eq 0) { $compiler = $instance.installationPath; break }
                }
                if ($compiler) { break }
            }
            if ($compiler) { break }
        }
    }
    $kits = Join-Path $programs 'Windows Kits\10'
    $registeredKits = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows Kits\Installed Roots' -ErrorAction SilentlyContinue
    if ($registeredKits.KitsRoot10) { $kits = $registeredKits.KitsRoot10 }
    $include = Join-Path $kits 'Include'
    if (Test-Path -LiteralPath $include) {
        foreach ($version in @(Get-ChildItem -LiteralPath $include -Directory | Where-Object Name -Match '^10\.0\.\d+\.0$' | Sort-Object { [version]$_.Name } -Descending)) {
            $v = $version.Name
            $hostArch = Get-Architecture
            $files = @((Join-Path $kits "Include\$v\um\Windows.h"),(Join-Path $kits "Include\$v\ucrt\stdio.h"),(Join-Path $kits "Lib\$v\um\$TargetArchitecture\kernel32.lib"),(Join-Path $kits "Lib\$v\ucrt\$TargetArchitecture\ucrt.lib"),(Join-Path $kits "bin\$v\$hostArch\rc.exe"))
            if (@($files | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) }).Count -eq 0) { $sdk = $v; break }
        }
    }
    return [pscustomobject]@{Ready=[bool]($compiler -and $sdk); Compiler=$compiler; Sdk=$sdk; BuildTools=$buildTools}
}
# -----------------------------

# ----------- Get-RustStableVersion ----------
function Get-RustStableVersion {
    param([string]$Rustup)
    # Native stderr in Windows PowerShell 5.1 must not abort the missing-toolchain branch.
    $output = Join-Path $RunFolder 'rust-version-output.log'
    $errors = Join-Path $RunFolder 'rust-version-error.log'
    $process = Start-Process -FilePath $Rustup -ArgumentList 'run stable rustc --version' -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput $output -RedirectStandardError $errors
    if ($process.ExitCode -eq 0) {
        $text = [IO.File]::ReadAllText($output)
        if ($text -match '^rustc (\d+\.\d+\.\d+)') { return [version]$Matches[1] }
    }
    return $null
}
# -----------------------------

# ----------- Install-RequiredBuildTools ----------
function Install-RequiredBuildTools {
    param([bool]$AllowSetup)
    # Rustup must install persistent tools outside the operation's disposable CARGO_HOME.
    $temporaryCargo = $env:CARGO_HOME
    $persistentCargo = $script:originalCargoHome
    if (-not $persistentCargo) { $persistentCargo = Join-Path $env:USERPROFILE '.cargo' }
    try {
        $env:CARGO_HOME = $persistentCargo
        foreach ($tool in @(@('git.exe','Git.Git'), @('rustup.exe','Rustlang.Rustup'))) {
            $exe = Find-BuildTool $tool[0]
            $working = $false
            if ($exe) { try { & $exe --version *> $null; $working = $LASTEXITCODE -eq 0 } catch { $working = $false } }
            if (-not $working) {
                if (-not $AllowSetup) { throw "Missing or unusable $($tool[0]). Enable automatic build-tool setup." }
                $winget = Get-WorkingWinget
                Invoke-BuildCommand $winget ('install --id ' + $tool[1] + ' --exact --source winget --accept-source-agreements --accept-package-agreements --disable-interactivity --force') $RunFolder ('setup-' + $tool[1])
                $env:PATH = [Environment]::GetEnvironmentVariable('PATH','Machine') + ';' + [Environment]::GetEnvironmentVariable('PATH','User') + ';' + (Join-Path $persistentCargo 'bin')
                $exe = Find-BuildTool $tool[0]
                if (-not $exe) { throw "Tool still unavailable after setup: $($tool[0])." }
                & $exe --version *> $null
                if ($LASTEXITCODE -ne 0) { throw "Tool failed verification after setup: $($tool[0])." }
            }
            Write-Status SolidCraft '' 'Dependency ready' $tool[0]
        }
        $state = Get-CppBuildState
        if (-not $state.Ready) {
            if (-not $AllowSetup) { throw 'C++ compiler or Windows SDK is missing/incomplete. Enable automatic build-tool setup.' }
            $arguments = '--passive --wait --norestart --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 --add Microsoft.VisualStudio.Component.Windows11SDK.26100'
            if ($Architecture -eq 'arm64') { $arguments += ' --add Microsoft.VisualStudio.Component.VC.Tools.ARM64' }
            if ($state.BuildTools) { $arguments = 'modify --installPath "' + $state.BuildTools + '" ' + $arguments }
            Install-MicrosoftDependency 'vs-buildtools' 'https://aka.ms/vs/17/release/vs_buildtools.exe' $arguments
            $state = Get-CppBuildState
            if (-not $state.Ready) { throw 'C++/Windows SDK verification failed after setup. Restart Windows if requested, then retry. See Visual Studio setup logs in the operation log folder.' }
        }
        Write-Status SolidCraft '' 'Dependency ready' ("C++ compiler: $($state.Compiler); Windows SDK: $($state.Sdk).")
        if ($script:dependencyRestartRequired) { throw 'Restart Windows to finish prerequisite setup, then run the installer again. Compilation has not started.' }
    }
    finally { $env:CARGO_HOME = $temporaryCargo }
}
# -----------------------------
