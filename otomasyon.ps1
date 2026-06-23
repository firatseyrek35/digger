# ==============================================================================
# FSOFTWARE AKILLI OTOMASYON MOTORU [TEST MODU - KAPATMA VE AKTİFLİK DEVRE DIŞI]
# ==============================================================================

# [TEST İÇİN DEVRE DIŞI] --- 1. KULLANICI AKTİFLİK KORUMASI ---
# Test sırasında bilgisayar başında olacağımız için bu filtreyi pasif yapıyoruz.
# $UserSession = qwinsta | Select-String "console"
# if ($UserSession -match "Active") { Exit }

Write-Host "[TEST] Aktiflik kontrolü bypass edildi. İşlemler başlıyor..." -ForegroundColor Cyan
Start-Sleep -Seconds 5

# --- 2. AKILLI PYTHON SÜRÜMÜ TESPİT ETME MOTORU ---
$PythonPath = $null

$RegPaths = @(
    "HKLM:\SOFTWARE\Python\PythonCore",
    "HKCU:\SOFTWARE\Python\PythonCore"
)
foreach ($RegPath in $RegPaths) {
    if (Test-Path $RegPath) {
        $Versions = Get-ChildItem -Path $RegPath | Select-Object -ExpandProperty Name
        foreach ($Ver in $Versions) {
            $InstallPathKey = "$Ver\InstallPath"
            if (Test-Path $InstallPathKey) {
                $ExecPath = (Get-ItemProperty -Path $InstallPathKey)."(default)"
                if ($ExecPath -and (Test-Path "$ExecPath\python.exe")) {
                    $PythonPath = "$ExecPath\python.exe"
                    break
                }
            }
        }
    }
    if ($PythonPath) { break }
}

if (-not $PythonPath) {
    $CommonPaths = @(
        "C:\Windows\System32\python.exe",
        "C:\Python312\python.exe",
        "C:\Python311\python.exe",
        "C:\Python310\python.exe",
        "C:\Program Files\Python311\python.exe",
        "C:\Program Files\Python312\python.exe"
    )
    foreach ($Path in $CommonPaths) {
        if (Test-Path $Path) {
            $PythonPath = $Path
            break
        }
    }
}

# Emniyet Kemeri: Hiçbir Python yoksa 3.11.9 sürümünü kurur
$TargetDir = "C:\Python311"
if (-not $PythonPath) {
    if (-not (Test-Path "$TargetDir\python.exe")) {
        Write-Host "[TEST] Sistemde Python bulunamadı. Python 3.11.9 indiriliyor..." -ForegroundColor Yellow
        $InstallerPath = "$env:TEMP\python-3.11.9-amd64.exe"
        Invoke-WebRequest -Uri "https://www.python.org/ftp/python/3.11.9/python-3.11.9-amd64.exe" -OutFile $InstallerPath
        Start-Process -FilePath $InstallerPath -ArgumentList "/quiet InstallAllUsers=1 TargetDir=$TargetDir PrependPath=1 Include_test=0" -Wait
        Remove-Item $InstallerPath -Force
        [Environment]::SetEnvironmentVariable("Path", [Environment]::GetEnvironmentVariable("Path", "Machine") + ";$TargetDir;$TargetDir\Scripts", "Process")
    }
    $PythonPath = "$TargetDir\python.exe"
}

Write-Host "[TEST] Kullanılacak Python Yolu: $PythonPath" -ForegroundColor Green

# --- 3. PIP VEYA REQUESTS KONTROLÜ ---
Write-Host "[TEST] Kütüphaneler kontrol ediliyor..." -ForegroundColor Tool
& $PythonPath -m pip install --upgrade pip --quiet
& $PythonPath -m pip install requests --quiet

# --- 4. ANA PYTHON RAPORLAMA KODUNU GİTHUB'DAN ÇEKME ---
$Workspace = "C:\Otomasyon"
if (-not (Test-Path $Workspace)) { New-Item -ItemType Directory -Force -Path $Workspace | Out-Null }
$PythonScriptPath = "$Workspace\gorev.py"

# --- GİTHUB BAĞLANTI AYARLARI ---
$GitHubToken = "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"  
$RepoOwner   = "firatseyrek35"            
$RepoName    = "digger"                 
$Branch      = "main"

$Headers = @{ "Authorization" = "Bearer $GitHubToken"; "Accept" = "application/vnd.github.v3+json" }
$Uri = "https://api.github.com/repos/$RepoOwner/$RepoName/contents/gorev.py?ref=$Branch"

try {
    Write-Host "[TEST] GitHub'dan gorev.py indiriliyor..." -ForegroundColor Yellow
    $Response = Invoke-RestMethod -Uri $Uri -Headers $Headers -Method Get
    $CodeBytes = [Convert]::FromBase64String($Response.content)
    $PythonCode = [System.Text.Encoding]::UTF8.GetString($CodeBytes)
    Set-Content -Path $PythonScriptPath -Value $PythonCode -Encoding UTF8
    
    # --- 5. PYTHON KODUNU MANUEL TETİKLEME (Görünür Pencerede) ---
    Write-Host "[TEST] Python kodu arka planda tetikleniyor. GitHub logunu kontrol et!" -ForegroundColor Green
    Start-Process -FilePath $PythonPath -ArgumentList "-W ignore `"$PythonScriptPath`"" -Wait
} catch {
    Write-Host "[TEST] GitHub baglantisinda hata olustu!" -ForegroundColor Red
}

# [TEST İÇİN DEVRE DIŞI] --- 6. GECE MESAİSİ BİTTİ: PC KAPATMA ---
# Test yaparken bilgisayarın kapanmaması için bu kısmı tamamen pasif hale getirdik.
Write-Host "[TEST] Görev başarıyla tamamlandı. Test Modu açık olduğu için PC KAPATILMADI." -ForegroundColor Cyan
# Start-Sleep -Seconds 15
# Stop-Computer -Force