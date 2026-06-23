import os
import glob
import base64
from datetime import datetime
import requests

# ==============================================================================
# FSOFTWARE AKILLI AKTİFLİK ANALİZ VE RAPORLAMA MOTORU
# ==============================================================================

# --- GİTHUB API VE ERİŞİM YAPILANDIRMASI ---
TOKEN = "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"  # GitHub'dan aldığın yeni Private Token'ı yaz
OWNER = "firatseyrek35"            # GitHub Kullanıcı Adın
REPO = "digger"                 # Private Deponun Adı
LOG_FILE_PATH = "aktiflik_raporu.txt"  # Raporun yazılacağı dosya adı

def bilgisayar_aktiflik_analizi():
    """
    Sistemdeki kullanıcı profillerini ve masaüstü hareketlerini tarayarak
    gün içindeki en erken (ilk giriş) ve en geç (son çıkış) saatleri bulur.
    """
    active_hours = []
    
    # Bilgisayardaki tüm kullanıcı klasör yollarını tarıyoruz
    user_profiles = glob.glob("C:\\Users\\*")
    
    for profile in user_profiles:
        # Windows'un sistem ve ortak kullanım klasörlerini eliyoruz
        if any(x in profile.lower() for x in ["public", "all users", "default", "desktop.ini"]):
            continue
        try:
            # Ana kullanıcı klasörünün son etkileşim zamanını alıyoruz
            stat = os.stat(profile)
            mtime = datetime.fromtimestamp(stat.st_mtime)
            active_hours.append(mtime.hour)
            
            # Eğer varsa Masaüstü (Desktop) klasöründeki güncel dosya hareketlerini tarıyoruz
            desktop_path = os.path.join(profile, "Desktop")
            if os.path.exists(desktop_path):
                for f in os.listdir(desktop_path):
                    f_path = os.path.join(desktop_path, f)
                    if os.path.isfile(f_path):
                        active_hours.append(datetime.fromtimestamp(os.stat(f_path).st_mtime).hour)
        except Exception:
            # İzin hatası veya kilitli dosyalarda döngünün kırılmaması için es geç
            continue

    # Eğer sistemden veri toplanabildiyse sınırları belirle
    if active_hours:
        ilk_giris = min(active_hours)
        son_cikis = max(active_hours)
    else:
        # Bilgisayardan hiç iz alınamazsa güvenli varsayılan şablon (09:00 - 23:00)
        ilk_giris, son_cikis = 9, 23
        
    return ilk_giris, son_cikis

def github_log_yaz(ilk_saat, son_saat):
    """
    Hesaplanan aktiflik verilerini GitHub API üzerinden 
    Private depodaki log dosyasına güvenli bir şekilde push (commit) eder.
    """
    url = f"https://api.github.com/repos/{OWNER}/{REPO}/contents/{LOG_FILE_PATH}"
    headers = {
        "Authorization": f"Bearer {TOKEN}",
        "Accept": "application/vnd.github.v3+json"
    }
    
    bugun = datetime.now().strftime("%Y-%m-%d")
    otomasyon_baslangic = f"{son_saat}:30"
    
    # Kullanıcı gelmeden yarım saat önce kapanacak şekilde stratejik saat hesabı
    kapanis_hesap = ilk_saat - 1 if ilk_saat - 1 >= 0 else 23
    otomasyon_bitis = f"{kapanis_hesap}:30"
    
    # GitHub'a basılacak temiz log satırı
    yeni_log_satiri = f"[{bugun}] PC Ilk Giris: {ilk_saat}:00 | Son Cikis: {son_saat}:00 -> Sonraki Otomasyon Dongusu: {otomasyon_baslangic} - {otomasyon_bitis} arasi.\n"
    
    # GitHub'da daha önceden bu log dosyası oluşturulmuş mu kontrol ediyoruz (SHA değerini almak için)
    response = requests.get(url, headers=headers)
    sha = None
    mevcut_icerik = ""
    
    if response.status_code == 200:
        file_data = response.json()
        sha = file_data["sha"]
        # Mevcut log geçmişini base64'ten çözerek stringe çeviriyoruz
        mevcut_icerik = base64.b64decode(file_data["content"]).decode("utf-8")
    
    # Yeni rapor satırını, eski logların en altına ekleyerek geçmişi koruyoruz
    guncel_icerik = mevcut_icerik + yeni_log_satiri
    # GitHub API veriyi base64 formatında kabul ettiği için encode ediyoruz
    icerik_base64 = base64.b64encode(guncel_icerik.encode("utf-8")).decode("utf-8")
    
    payload = {
        "message": f"FSoftware Otomasyon Raporu Islendi - {bugun}",
        "content": icerik_base64,
        "branch": "main"
    }
    
    # Eğer dosya zaten varsa, üzerine yazmak için eski dosyanın SHA kimliğini ekliyoruz
    if sha:
        payload["sha"] = sha
        
    # PUT isteği ile veriyi doğrudan repoya commitliyoruz
    put_response = requests.put(url, headers=headers, json=payload)
    
    return put_response.status_code

if __name__ == "__main__":
    # 1. Bilgisayardaki kullanıcı hareket saatlerini analiz et
    ilk, son = bilgisayar_aktiflik_analizi()
    
    # 2. Sonuçları GitHub'daki Private depoya log olarak gönder
    status = github_log_yaz(ilk, son)