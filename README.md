# STRUKKU — Panduan Menjalankan Program

Aplikasi pencatat keuangan dari struk belanja: **foto struk → OCR → kategori otomatis (ML) → koreksi → simpan → dashboard bulanan**.

```text
strukku/
├── backend/        Server API (Python FastAPI + Tesseract OCR + model TF-IDF/Naive Bayes)
├── mobile/         Aplikasi Android (Flutter)
├── docs/laporan/   Laporan fase 1.0 – 4.0
└── README.md       Panduan ini
```

Urutan menjalankan selalu: **1) nyalakan backend → 2) jalankan aplikasi Flutter**.

---

## 0. Persiapan (sekali saja)

| Kebutuhan | Cek dengan | Catatan |
|---|---|---|
| Python 3.11 – 3.13 (64-bit) | `python --version` | Centang *Add Python to PATH* saat instalasi |
| Tesseract OCR + bahasa Indonesia | `& "C:\Program Files\Tesseract-OCR\tesseract.exe" --list-langs` | Harus memuat `eng` dan `ind`. Installer: https://github.com/UB-Mannheim/tesseract/wiki |
| Flutter SDK + Android SDK | `flutter doctor` | Android Studio dengan plugin Flutter & Dart |
| Emulator Android atau HP Android | `flutter devices` | API 24+ |

---

## 1. Menjalankan backend

Buka PowerShell:

```powershell
cd D:\strukku\backend

# a. Buat virtual environment (sekali saja)
python -m venv .venv
.venv\Scripts\Activate.ps1
#   Jika ditolak: Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

# b. Instal dependensi (sekali saja)
python -m pip install --upgrade pip
pip install -r requirements.txt

# c. Jalankan server
python -m uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

Setelah langkah a–b pernah dilakukan, cukup **dobel klik `backend\jalankan_server.bat`** untuk menyalakan server.

**File `.env` sudah disiapkan** di `backend\.env` untuk pengembangan lokal:
- Database SQLite (`backend\strukku.db`, dibuat otomatis saat server pertama kali start).
- `JWT_SECRET_KEY` acak sudah dibuat.
- `REQUIRE_EMAIL_VERIFICATION=false` → akun baru langsung bisa login tanpa email.
- Foto struk disimpan di `backend\storage\uploads\`.

Untuk memakai Supabase, ganti `DATABASE_URL` di `.env` (contoh ada di dalam file), lalu restart server.

**Cek server berjalan** — buka di browser laptop:
- http://127.0.0.1:8000/api/v1/health → `"status": "ok"`
- http://127.0.0.1:8000/docs → dokumentasi Swagger untuk mencoba API

Biarkan jendela server tetap terbuka selama aplikasi dipakai.

---

## 2. Menjalankan aplikasi Flutter

Buka terminal **baru** (server tetap berjalan di terminal pertama):

```powershell
cd D:\strukku\mobile
flutter pub get
```

Lalu pilih sesuai perangkat:

| Perangkat | Perintah | Alamat server yang dipakai |
|---|---|---|
| Emulator Android | `flutter run` | otomatis `http://10.0.2.2:8000` |
| HP Android fisik (Wi-Fi sama dengan laptop) | `flutter run --dart-define=API_BASE_URL=http://IP_LAPTOP:8000` | IP laptop, lihat `ipconfig` → *IPv4 Address* |
| Mode demo tanpa backend | `flutter run --dart-define=USE_FASTAPI=false` | data disimpan di HP, akun demo `satria@gmail.com` / `Strukku123` |

Atau lewat Android Studio: **File → Open → `D:\strukku\mobile`**, pilih emulator, tekan **Run**.

> Proyek Flutter ini hanya berisi platform **Android**. Untuk Windows/Web jalankan dulu
> `flutter create . --platforms=windows,web` di folder `mobile`.

### Membuat file APK

```powershell
cd D:\strukku\mobile
flutter build apk --release --dart-define=API_BASE_URL=http://IP_LAPTOP:8000
```

Hasil: `mobile\build\app\outputs\flutter-apk\app-release.apk`.

---

## 3. Mencoba alur lengkap

1. Di aplikasi: **Daftar** akun baru → login.
2. Tekan tombol kamera di Beranda → foto struk (atau pilih dari galeri).
3. Periksa hasil di layar **Koreksi & Validasi** — item bertanda kuning perlu diperiksa kategorinya.
4. **Simpan** → total pengeluaran dan distribusi kategori di Beranda bertambah.

Di emulator, cara termudah memasukkan foto struk: seret file gambar ke jendela emulator, lalu pilih dari galeri.

---

## 4. Fitur pindai buram, klasifikasi, dan rekomendasi

**Alur pindai (mode server, default)**
1. Foto dikirim ke server (`POST /api/v1/scans`): OCR Tesseract bertingkat, parser lengkap
   (jumlah & harga satuan), dan kategori per barang.
2. Di layar validasi, jumlah barang bisa diubah dengan tombol −/+ (harga total ikut dihitung
   bila harga satuan diketahui). Catatan dari server (mutu foto, total tidak cocok) ditampilkan.
3. Saat disimpan, `scan_id` ikut dikirim sehingga **foto struk tersimpan di server** dan bisa
   dibuka lagi dari detail struk (ketuk foto untuk memperbesar).
4. Bila server tidak terjangkau atau tidak bisa membaca struk, aplikasi otomatis memakai
   OCR di HP (ML Kit) seperti di bawah.

Uji integrasi aplikasi ↔ server (backend harus sedang berjalan):
```powershell
cd D:\strukku\mobile
flutter test test/server_scan_integration_test.dart --dart-define=RUN_SERVER_TESTS=true --dart-define=API_BASE_URL=http://127.0.0.1:8000 --dart-define=TEST_RECEIPT_IMAGE=C:/path/foto_struk.jpg
```

**Foto buram / gelap / pudar**
- Di aplikasi (OCR ML Kit di HP, dipakai saat offline / mode demo): bila hasil baca belum lengkap, foto otomatis
  diperjelas (cahaya diratakan, tulisan dipertajam, kontras ditarik) lalu dibaca ulang;
  bila masih kurang, dicoba penajaman lebih kuat. Hasil terbaik dipilih otomatis dan
  layar validasi menampilkan catatan mutu foto (mis. "foto buram").
- Di server (`POST /api/v1/scans`, Tesseract): pembacaan bertingkat yang sama, ditambah
  peringatan mutu foto pada respons.

**Klasifikasi barang** — urutan penentu kategori (`CLASSIFIER_PIPELINE` di `backend\.env`):
`user_history → keyword_rules → id_model → ml_model`
- Teks OCR diperbaiki dulu: angka/huruf tertukar (`TE1UR` → telur), kata terpecah
  (`FRESHMI LK` → fresh milk), kata tergabung, salah eja ringan.
- `id_model`: TF-IDF + Naive Bayes nama barang berbahasa Indonesia (±10.000 contoh,
  data dari smart_receipt_v2 + kata kunci), dilatih otomatis saat server start.
- Data latih: `backend\app\data\training_items_id.json`; kata kunci: `keyword_rules.json`.

Mengukur akurasi (dari folder `backend`, venv aktif):
```powershell
python -m scripts.evaluate_classifier --csv tests/data/classification_eval_ocr.csv --show-errors
python -m scripts.evaluate_ocr path\ke\foto_struk.jpg
```

**Analisis, anggaran, dan notifikasi** (setara smart_receipt_v2):
- **Analisis & tren** (Beranda → "Lihat lengkap", atau Profil → Analisis & tren): pilih periode
  **Hari / Bulan / Tahun**, grafik pengeluaran harian, persona, temuan, pengeluaran per kategori
  beserta saran, **toko favorit**, **tren bulanan** (12 bulan) dan **tren tahunan**, termasuk
  "bulan terboros", "naik/turun 3 bulan berturut-turut", dan perbandingan dengan tahun lalu.
- **Anggaran bulanan** (Profil → Anggaran bulanan): batas total dan per kategori, bilah pemakaian,
  dan peringatan di Beranda saat pemakaian ≥ 80% atau melewati batas. Batas disimpan di HP per akun.
- **Notifikasi** (Profil → Notifikasi): pengingat harian (jam bisa diubah), ringkasan mingguan
  (Minggu 19.00), dan peringatan anggaran 80% / 100%. Android 13+ akan meminta izin notifikasi
  saat aplikasi pertama dibuka; di HP Xiaomi, izinkan juga *Autostart* agar pengingat tetap muncul.
- Endpoint backend baru: `GET /api/v1/analytics/period?date_from=&date_to=` dan `GET /api/v1/analytics/yearly`.

**Fitur tambahan**
- **Model belajar dari koreksi**: setiap koreksi kategori menjadi data latih `id_model`; server
  melatih ulang otomatis di latar belakang (beberapa detik). Matikan dengan
  `LEARN_FROM_CORRECTIONS=false` di `backend\.env`.
- **Kinerja model** (Profil → Kinerja model): akurasi kategori otomatis menurut koreksi Anda,
  per kategori, per sumber prediksi, tren per bulan, dan barang yang paling sering dikoreksi
  (`GET /api/v1/analytics/model`). Hanya di mode server.
- **Catat manual tanpa struk** (tombol ✎ di samping tombol kamera di Beranda): untuk parkir, ojek,
  warung, dll. Kategori ditebak otomatis setelah nama barang diketik.
- **Deteksi struk ganda**: bila tanggal, total, dan nama toko sama dengan struk yang sudah ada,
  aplikasi bertanya "Simpan tetap?" (server: kode `POSSIBLE_DUPLICATE`, kirim `allow_duplicate=true`).
- **Ekspor laporan Excel (.xlsx)** (Fitur → Ekspor, pilih bulan; atau ikon bagikan di halaman Analisis):
  satu baris per barang + ringkasan kategori; bisa dibuka di Excel / Google Sheets dan dibagikan
  lewat WhatsApp, email, atau Drive.

- **Cari & filter riwayat** (Beranda → Struk terbaru → Lihat semua): cari nama toko/barang,
  filter kategori dan rentang tanggal, lengkap dengan jumlah & total hasil filter.
- **Riwayat harga** (Profil → Riwayat harga, atau ketuk barang di detail struk): harga satuan
  barang di setiap toko, toko termurah, dan selisih hematnya (`GET /api/v1/items/price-history?q=`).
- **Pindai banyak struk** dari galeri: pilih beberapa foto sekaligus, setiap struk diproses dan
  divalidasi bergantian ("Struk 2 dari 5"); yang tidak terbaca dilewati.
- **Pengeluaran berulang** (Profil → Pengeluaran berulang): langganan/tagihan bulanan dengan
  tanggal jatuh tempo; dicatat otomatis saat aplikasi dibuka, bisa dijeda atau dihapus.

- **Lokasi toko** (Profil → Lokasi toko, atau alamat di detail struk): alamat toko dibaca dari
  struk (bisa disunting di layar validasi), toko dikelompokkan per cabang, dan diketuk untuk
  dibuka di Google Maps (tanpa API key). Backend: kolom `merchant_address` (migrasi otomatis) dan
  `GET /api/v1/stores`.
- **Tampilan baru**: header Beranda dan kartu total memakai foto Unsplash (lihat
  `mobile/assets/images/CREDITS.md`); kartu kategori, struk, temuan, anggaran, dan toko memakai
  motif ikon kategori yang digambar kode.

**Rekomendasi** (seperti smart_receipt_v2), dihitung di aplikasi:
- **Beranda → Analisis & Rekomendasi**: tipe pengeluaran (persona), rata-rata per hari,
  proyeksi akhir bulan, perbandingan dengan bulan lalu, kategori dominan, hari paling boros,
  toko langganan, dan saran hemat.
- **Kategori**: saran untuk setiap kategori yang ada pengeluarannya.
- **Koreksi & Validasi**: saran berdasarkan kategori terbesar di struk yang baru dipindai.

---

## 5. Menjalankan pengujian

```powershell
# Backend
cd D:\strukku\backend
.venv\Scripts\Activate.ps1
pip install -r requirements-dev.txt
pytest -q

# Flutter
cd D:\strukku\mobile
flutter analyze
flutter test
```

---

## 6. Masalah umum

| Gejala | Penyebab & solusi |
|---|---|
| Aplikasi: *"Tidak dapat terhubung ke server"* | Backend belum jalan; server tidak memakai `--host 0.0.0.0`; HP fisik tidak memakai IP laptop; atau Windows Firewall memblokir Python (izinkan untuk jaringan *Private*). |
| `JWT_SECRET_KEY harus memiliki minimal 48 karakter` | `.env` hilang/rusak. Salin `.env.example` → `.env`, isi kunci dari `python -c "import secrets; print(secrets.token_urlsafe(48))"`. |
| `/health` menunjukkan OCR tidak siap | Tesseract belum terinstal atau `TESSERACT_CMD` di `.env` salah lokasi; pastikan bahasa `ind` ada. |
| *"Email belum diverifikasi"* saat login | Pastikan `REQUIRE_EMAIL_VERIFICATION=false` di `backend\.env`, restart server. |
| `pip install` gagal dengan *Read timed out* | Koneksi lambat. Ulangi dengan `pip install --default-timeout=120 --retries 10 -r requirements.txt`. |
| `Activate.ps1 cannot be loaded` | `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass` lalu ulangi. |
| Build Flutter error setelah ganti versi/kode | `flutter clean` lalu `flutter pub get`. |
| Teks struk tidak terbaca | Foto lebih terang, struk lurus dan memenuhi layar; atau pilih **Isi Manual**. |

Dokumentasi lebih rinci:
- Backend: `backend\README.md`, kontrak API untuk Flutter: `backend\docs\API_FRONTEND.md`
- Flutter: `mobile\README.md`, `mobile\CARA_MENJALANKAN.md`
