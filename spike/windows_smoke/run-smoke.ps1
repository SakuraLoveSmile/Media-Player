param(
    [Parameter(Mandatory = $true)][string]$Server,
    [Parameter(Mandatory = $true)][string]$Username,
    [string]$Password,
    [string[]]$ItemIds = @('53212', '69117')
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

if (-not $Password) {
    $secure = Read-Host -AsSecureString "Emby password for $Username"
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        $Password = [Runtime.InteropServices.Marshal]::PtrToStringUni($bstr)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

$Server = $Server.TrimEnd('/')
$deviceId = 'm0-windows-smoke'
$authHeader = 'MediaBrowser Client="MediaPlayerSmoke", Device="WindowsSmoke", DeviceId="' + $deviceId + '", Version="0.1.0"'
$token = $null
$configPath = Join-Path $root 'emby_config.json'
$infoPath = Join-Path $root 'playback-info.txt'

function Write-SystemInfo {
    $sys = @()
    $sys += 'Time: ' + (Get-Date -Format o)
    $sys += 'OS: ' + ((Get-CimInstance Win32_OperatingSystem | Select-Object Caption, Version, BuildNumber, OSArchitecture) | Format-List | Out-String)
    $sys += 'CPU: ' + ((Get-CimInstance Win32_Processor | Select-Object Name, NumberOfCores, NumberOfLogicalProcessors) | Format-List | Out-String)
    $sys += 'GPU: ' + ((Get-CimInstance Win32_VideoController | Select-Object Name, DriverVersion, CurrentHorizontalResolution, CurrentVerticalResolution) | Format-List | Out-String)
    $sys += 'PowerShell: ' + $PSVersionTable.PSVersion
    $sys | Set-Content -Path (Join-Path $root 'system.txt') -Encoding UTF8
}

try {
    Write-SystemInfo
    Set-Content -Path $infoPath -Value '' -Encoding UTF8

    $authBody = @{ Username = $Username; Pw = $Password } | ConvertTo-Json
    $auth = Invoke-RestMethod -Uri "$Server/Users/AuthenticateByName" -Method Post `
        -Headers @{ 'X-Emby-Authorization' = $authHeader } `
        -ContentType 'application/json' -Body $authBody -TimeoutSec 20
    $token = $auth.AccessToken
    $userId = $auth.User.Id
    if (-not $token) { throw 'Authentication failed: no AccessToken' }

    $profile = @{
        Name = 'MediaPlayer-mpv'
        DirectPlayProfiles = @(@{
            Container = 'mkv,mp4,m4v,mov,ts,webm'
            Type = 'Video'
            VideoCodec = 'h264,hevc,av1,vp9,mpeg2video'
            AudioCodec = 'aac,ac3,eac3,dts,truehd,flac,opus,vorbis,mp3'
        })
        SubtitleProfiles = @(
            @{ Format = 'srt'; Method = 'External' },
            @{ Format = 'ass'; Method = 'External' },
            @{ Format = 'pgssub'; Method = 'Embed' },
            @{ Format = 'dvdsub'; Method = 'Embed' }
        )
    }

    $items = @()
    foreach ($itemId in $ItemIds) {
        $pbBody = @{
            UserId = $userId
            StartTimeTicks = 0
            IsPlayback = $false
            AutoOpenLiveStream = $false
            MaxStreamingBitrate = 1000000000
            EnableDirectPlay = $true
            EnableDirectStream = $true
            EnableTranscoding = $true
            DeviceProfile = $profile
        } | ConvertTo-Json -Depth 10

        $pb = Invoke-RestMethod -Uri "$Server/Items/$itemId/PlaybackInfo?UserId=$userId" -Method Post `
            -Headers @{ 'X-Emby-Token' = $token } `
            -ContentType 'application/json' -Body $pbBody -TimeoutSec 30
        $ms = @($pb.MediaSources)[0]
        $name = switch ($itemId) {
            '53212' { 'HEVC 4K MKV' }
            '69117' { 'H.264 1080p MKV' }
            default { "item-$itemId" }
        }
        $direct = [bool]$ms.SupportsDirectPlay
        $hasTranscode = [bool]$ms.TranscodingUrl
        $directUrl = [string]$ms.DirectStreamUrl
        Add-Content -Path $infoPath -Value "$name id=$itemId directPlay=$direct transcodeUrl=$hasTranscode directUrl=$([bool]$directUrl)" -Encoding UTF8
        if (-not $directUrl) {
            throw "Item $itemId has no DirectStreamUrl (transcode=$hasTranscode)"
        }
        if ($directUrl -match '^https?://') {
            $fullUrl = $directUrl
        }
        else {
            $fullUrl = $Server + $directUrl
        }
        $headerUrl = ($fullUrl -replace '([?&])api_key=[^&]*', '$1').TrimEnd([char[]]@('?', '&'))
        $items += @{ name = $name; url = $headerUrl; token = $token }
    }

    $config = @{ items = @($items) } | ConvertTo-Json -Depth 5
    [IO.File]::WriteAllText($configPath, $config, (New-Object Text.UTF8Encoding($false)))

    $exe = Join-Path $root 'm0_smoke.exe'
    if (-not (Test-Path $exe)) { throw "m0_smoke.exe not found in $root" }

    $proc = Start-Process -FilePath $exe -WorkingDirectory $root -PassThru
    if (-not $proc.WaitForExit(180000)) {
        $proc.Kill()
        Add-Content -Path $infoPath -Value 'App did not exit in 180s; killed.' -Encoding UTF8
    }
    else {
        Add-Content -Path $infoPath -Value "App exit code: $($proc.ExitCode)" -Encoding UTF8
    }
}
catch {
    Add-Content -Path $infoPath -Value ("ERROR: " + $_.Exception.Message) -Encoding UTF8
    throw
}
finally {
    if ($token) {
        try {
            Invoke-RestMethod -Uri "$Server/Sessions/Logout" -Method Post -Headers @{ 'X-Emby-Token' = $token } -TimeoutSec 10 | Out-Null
        }
        catch {}
    }
    Remove-Item -Path $configPath -Force -ErrorAction SilentlyContinue

    $logFiles = @('m0_smoke.log', 'm0_result.json', 'system.txt', 'playback-info.txt') |
        ForEach-Object { Join-Path $root $_ } |
        Where-Object { Test-Path $_ }
    if ($logFiles) {
        $zip = Join-Path $root 'm0_windows_report.zip'
        Compress-Archive -Path $logFiles -DestinationPath $zip -Force
        Write-Host "Report: $zip"
    }
    else {
        Write-Host 'No logs were produced.'
    }
}
