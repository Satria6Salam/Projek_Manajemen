# Panduan: Memasukkan Desain Figma STRUKKU ke Laporan

## Bahan yang sudah tersedia

| Bahan | Lokasi |
|---|---|
| File Figma (6 layar, layer bisa diedit) | https://www.figma.com/design/1at0cYWi7nT9AhA6i7Sr3d |
| Tangkapan layar aplikasi asli (13 layar, PNG) | `docs/tampilan_aplikasi/` di repositori |
| Repositori kode | https://github.com/Satria6Salam/Projek_Manajemen |

Layar di Figma: 01 Login · 02 Beranda · 03 Kategori · 04 Fitur · 05 Profil · 06 Koreksi & Validasi.
Tangkapan layar PNG: 01 Login · 02 Beranda · 03 Kategori · 04 Fitur · 05 Profil · 06 Koreksi & Validasi ·
07 Detail struk · 08 Analisis · 09 Anggaran · 10 Pengeluaran berulang · 11 Lokasi toko ·
12 Riwayat harga · 13 Kinerja model.

## Langkah 1 — Siapkan tautan Figma agar bisa dilihat dosen

1. Buka file Figma di atas.
2. Klik **Share** (kanan atas).
3. Pada *Who has access*, ubah menjadi **Anyone with the link → can view**.
4. Klik **Copy link**.
5. (Opsional) Undang Reza dan Fidian lewat kolom email di jendela Share.

## Langkah 2 — Ekspor gambar dari Figma untuk dokumen Word

1. Klik nama frame, misalnya **02 Beranda**.
2. Panel kanan → bagian **Export** → klik **+** → pilih **PNG** dan **2x** → **Export**.
3. Ulangi untuk layar lain, atau pakai PNG yang sudah ada di `docs/tampilan_aplikasi/`.

## Langkah 3 — Masukkan ke dokumen laporan

### A. Project Monitoring Detail Report — baris No. 9
Kolom **Bukti / keterangan**, tambahkan:

> Akun Figma tim aktif (paket Starter). File desain tampilan aplikasi hasil program dibuat 16-11-2026:
> https://www.figma.com/design/1at0cYWi7nT9AhA6i7Sr3d (6 layar: Login, Beranda, Kategori, Fitur,
> Profil, Koreksi & Validasi). Repositori GitHub: https://github.com/Satria6Salam/Projek_Manajemen.
> VPS dan domain/SSL masih dalam proses.

### B. Laporan_Penyelesaian_Fase_4_0_StrukKu.docx — Lampiran 3 (WBS 4.3, antarmuka)
Tambahkan subjudul **"Desain Antarmuka Final (Figma)"**, lalu:

1. Satu kalimat pengantar:
   > Tampilan berikut dibuat ulang di Figma dari aplikasi Flutter hasil fase 4.0 sebagai dokumentasi desain final.
2. Tautan Figma.
3. Tabel gambar 2 kolom (Insert → Table, isi tiap sel dengan gambar PNG, lebar ±7 cm):

| Gambar | Keterangan |
|---|---|
| Gambar X.1 Login | Pengguna masuk atau mendaftar akun. |
| Gambar X.2 Beranda | Total bulanan, pintasan fitur, distribusi kategori, rekomendasi, struk terbaru. |
| Gambar X.3 Kategori | Pengeluaran per kategori dengan persentase dan saran hemat. |
| Gambar X.4 Fitur | Menu fitur: analisis, anggaran, pengeluaran berulang, lokasi toko, riwayat harga, ekspor, kinerja model, notifikasi. |
| Gambar X.5 Koreksi & Validasi | Hasil pindai: pengguna memeriksa kategori otomatis (kuning = perlu diperiksa) dan jumlah barang. |
| Gambar X.6 Profil | Data akun dan tombol keluar. |

4. Beri caption pada setiap gambar: klik kanan gambar → **Insert Caption** → "Gambar".

### C. Laporan_Kemajuan_Proyek_STRUKKU.docx
Pada tabel **Tahap 4.0**, baris **4.3**, kolom **Bukti / realisasi**, tambahkan di akhir:

> Desain tampilan final terdokumentasi di Figma: https://www.figma.com/design/1at0cYWi7nT9AhA6i7Sr3d

### D. Laporan akhir proyek (WBS 7.1) dan user manual (WBS 6.1)
Gunakan PNG dari `docs/tampilan_aplikasi/` sebagai gambar panduan penggunaan, karena berasal langsung dari
aplikasi (13 layar, termasuk Analisis, Anggaran, Lokasi Toko, Riwayat Harga, dan Kinerja Model).

## Catatan penting

- **Paket Figma:** akun tim memakai paket **Starter (gratis)**. RAB fase 2.0 mencatat lisensi
  **Figma Pro Rp750.000**. Jika Pro tidak dibeli, koreksi atau jelaskan catatan biaya tersebut
  pada laporan berikutnya (log perubahan biaya).
- **Data contoh:** angka pada layar (Rp472.000, Toko Sejahtera, dll.) adalah data contoh yang meniru struk uji tim.
- **Revisi dokumen:** laporan Fase 4.0 sudah ditandatangani 11/11/2026, jadi tambahkan catatan
  "Revisi 16-11-2026: penambahan dokumentasi desain Figma dan tautan GitHub".
