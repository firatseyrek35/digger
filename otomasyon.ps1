# ==============================================================================
# FSOFTWARE AKILLI OTOMASYON MOTORU (SESSİZ GECE MESAİSİ)
# ==============================================================================

# --- 1. KULLANICI AKTİFLİK KORUMASI ---
# Eğer gece bilgisayar başındaysan otomasyon çalışmaz, seni bölmez.
$UserSession = qwinsta | Select-String "console"
if ($UserSession -match "Active") { Exit }

# Donanımın ağa (internete) tamamen bağlanması için kilit ekranı arkasında esneme payı
Start-Sleep -Seconds 30

# --- 2. SESSİZ PYTHON VE PIP EKOSİSTEMİ KURULUMU ---
# SYSTEM yetkisiyle kilit ekranı arkasında çalışacağımız için ortak alana kurulum yapıyoruz
$TargetDir = "C:\Python311"

if (-not (Test-Path "$TargetDir\python.exe")) {
    $InstallerPath = "$env:TEMP\python_installer.exe"
    # Resmi Python sunucusundan sessiz yükleyiciyi indir
    Invoke-WebRequest -Uri "https://www.python.org/ftp/python/3.11.9/python-3.11.9-amd64.exe" -OutFile $InstallerPath
    
    # Arka planda hiçbir pencere ve onay çıkarmadan ortak dizine sessizce enjekte et
    Start-Process -FilePath $InstallerPath -ArgumentList "/quiet InstallAllUsers=1 TargetDir=$TargetDir PrependPath=1 Include_test=0" -Wait
    Remove-Item $InstallerPath -Force
    
    # Ortam değişkenlerini yenile (Python'ın sistem tarafından hemen tanınması için)
    [Environment]::SetEnvironmentVariable("Path", [Environment]::GetEnvironmentVariable("Path", "Machine") + ";$TargetDir;$TargetDir\Scripts", "Process")
}
$PythonPath = "$TargetDir\python.exe"

# Projenin log atabilmesi için gerekli olan requests kütüphanesini sessizce indir/güncelle
& $PythonPath -m pip install --upgrade pip --quiet
& $PythonPath -m pip install requests --quiet

# --- 3. ANA PYTHON RAPORLAMA KODUNU GİTHUB'DAN ÇEKME ---
$Workspace = "C:\Otomasyon"
if (-not (Test-Path $Workspace)) { New-Item -ItemType Directory -Force -Path $Workspace | Out-Null }
$PythonScriptPath = "$Workspace\gorev.py"

# --- GİTHUB BAĞLANTI AYARLARI ---
$GitHubToken = "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"  # GitHub'dan aldığın Token'ı buraya yaz
$RepoOwner   = "firatseyrek35"            # GitHub Kullanıcı Adın
$RepoName    = "digger"                 # GitHub Depo Adın
$Branch      = "main"

$Headers = @{ "Authorization" = "Bearer $GitHubToken"; "Accept" = "application/vnd.github.v3+json" }
$Uri = "https://api.github.com/repos/$RepoOwner/$RepoName/contents/gorev.py?ref=$Branch"

try {
    # GitHub'dan güncel aktiflik analizi yapan Python kodunu çekiyoruz
    $Response = Invoke-RestMethod -Uri $Uri -Headers $Headers -Method Get
    $CodeBytes = [Convert]::FromBase64String($Response.content)
    $PythonCode = [System.Text.Encoding]::UTF8.GetString($CodeBytes)
    
    # Kodu diske 'gorev.py' olarak yaz
    Set-Content -Path $PythonScriptPath -Value $PythonCode -Encoding UTF8
    
    # --- 4. PYTHON KODUNU GİZLİ PENCEREDE TETİKLEME ---
    # Siyah konsol ekranı dahi açılmadan arka planda tamamen görünmez çalışır
    Start-Process -FilePath $PythonPath -ArgumentList "-W ignore `"$PythonScriptPath`"" -WindowStyle Hidden -Wait
} catch {
    # Ağ kopması veya GitHub API sınırlarında bilgisayarın takılı kalmaması için es geç
}

# --- 5. GECE MESAİSİ BİTTİ: BİLGİSAYARI TAMAMEN KAPAT ---
# Python kodu görevini bitirip logu GitHub'a bastıktan sonra bilgisayarı kapatır.
# Böylece sabah sen gelmeden önce donanım kapanmış ve dinlenmiş olur.
Start-Sleep -Seconds 15
Stop-Computer -Force