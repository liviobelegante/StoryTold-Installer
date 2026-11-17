# Startup dependency checks for Windows PowerShell.
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


