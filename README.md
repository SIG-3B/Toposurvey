# TopoSurvey

Aplikasi Android Material 3 untuk mengukur koordinat dan elevasi dengan layanan
lokasi ponsel, menampilkan posisi di peta OpenStreetMap, dan menyimpan hasil
survei secara **lokal & offline menggunakan SQLite di perangkat**. Proyek ini juga
menyertakan folder `backend/` (FastAPI + SQLite) untuk pengujian REST API lokal.

Ukur lintang, bujur, dan elevasi, lalu lihat posisi serta titik tersimpan di
peta. Riwayat menyediakan detail dan penghapusan survei secara langsung dari
penyimpanan lokal perangkat tanpa perlu koneksi server.

## Unduh APK (GitHub Release)

APK siap pasang dapat diunduh langsung melalui halaman rilis GitHub berikut:

- **Halaman Rilis (`v1.1.0`):** [GitHub Release v1.1.0](https://github.com/SIG-3B/Toposurvey/releases/tag/v1.1.0)
- **Unduh Langsung APK:** [TopoSurvey-v1.1.0.apk](https://github.com/SIG-3B/Toposurvey/releases/download/v1.1.0/TopoSurvey-v1.1.0.apk)
- **Semua Rilis Terbaru:** [GitHub Releases](https://github.com/SIG-3B/Toposurvey/releases)

## Landing Page & Otomatisasi GitHub

- **Landing page:** [TopoSurvey di GitHub Pages](https://sig-3b.github.io/Toposurvey/)
- Sumber halaman statis ada di `docs/index.html` dan di-deploy oleh
  `.github/workflows/pages.yml` setiap ada perubahan di branch `main`.
- Untuk deployment pertama, buka **Settings → Pages**, lalu pilih **GitHub
  Actions** sebagai sumber build. Workflow juga dapat dijalankan manual dari tab
  **Actions**.
- `.github/workflows/release.yml` menjalankan analisis dan tes Flutter, membuat
  tag versi otomatis, membangun APK release, lalu menerbitkan GitHub Release
  saat ada push ke `main`. Jalankan manual dari tab **Actions** untuk memilih
  jenis kenaikan versi.

---

- `frontend/` berisi aplikasi Flutter dan Dart dengan Material 3, Geolocator,
  Flutter Map, LatLong2, OpenStreetMap, serta penyimpanan SQLite lokal (`sqlite3`
  dan `path_provider`). Layar, model, layanan, dan widget peta berada di
  `frontend/lib/`. Uji Flutter ada di `frontend/test/`.
- `backend/` berisi REST API FastAPI untuk Python dan database SQLite lokal
  (`backend/toposurvey.sqlite3`) yang tetap tersedia untuk pengujian REST API.

Siapkan Flutter 3.47.5 (Dart 3.13.3), Android SDK dan emulator atau perangkat
Android, serta Python 3.11 atau lebih baru (opsional untuk menjalankan `backend/`).
Periksa instalasi Android dengan `flutter doctor -v`.

## Backend (Opsional — REST API Lokal)

Dari root proyek di PowerShell:

```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
.\.venv\Scripts\python.exe -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

Buka terminal lain untuk memeriksa endpoint:

```powershell
Invoke-RestMethod http://127.0.0.1:8000/api/health
```

Jika API dan tabel survei dapat diakses, responsnya HTTP 200 dengan
`{"status":"ok","database":"ok"}`. Backend membuat tabel `surveys` di
`backend/toposurvey.sqlite3` saat startup. Menjalankan ulang server tetap
menggunakan file database yang sama.

| Endpoint | Respons berhasil |
|---|---|
| `GET /api/health` | `200` dengan status API dan SQLite |
| `POST /api/surveys` | `201` dengan survei yang tersimpan |
| `GET /api/surveys` | `200` dengan daftar survei, ID terbaru di atas |
| `GET /api/surveys/{id}` | `200` dengan detail survei |
| `DELETE /api/surveys/{id}` | `204` tanpa isi |

Contoh menyimpan survei dan membaca kembali hasilnya:

```powershell
$survey = Invoke-RestMethod -Method Post http://127.0.0.1:8000/api/surveys -ContentType 'application/json' -Body '{"latitude":-6.9,"longitude":107.6,"elevation":-4.5}'
Invoke-RestMethod "http://127.0.0.1:8000/api/surveys/$($survey.id)"
```

Kirim `latitude` dari −90 hingga 90, `longitude` dari −180 hingga 180,
serta `elevation` dalam meter sebagai angka JSON. Elevasi negatif diterima.
Jika elevasi tidak tersedia, permintaan ditolak dengan `422`. Server menetapkan
`created_at` dalam format ISO 8601 UTC saat menyimpan survei. ID yang tidak
ditemukan menghasilkan `404`. Gangguan SQLite saat server berjalan
menghasilkan `503`. Dokumentasi interaktif tersedia di `/docs`.

## Frontend

Nyalakan emulator atau hubungkan perangkat Android, lalu jalankan dari root proyek:

```powershell
cd frontend
flutter pub get
flutter analyze
flutter test
flutter run
```

Secara default aplikasi berjalan menggunakan `TopoSurveyApp.local()`, sehingga
seluruh penyimpanan dan pembacaan riwayat survei dilakukan **secara offline
menggunakan database SQLite lokal di perangkat** (`toposurvey.sqlite3` pada
direktori dokumen aplikasi) tanpa memerlukan server eksternal.

Buka tab **Survei**, ketuk **Aktifkan GPS** jika muncul, lalu beri izin lokasi
untuk melihat garis
lintang, garis bujur, ketinggian dalam meter, dan perkiraan akurasi horizontal.
Aplikasi meminta pembaruan posisi dengan akurasi tinggi hanya saat tab Survei
terbuka dan aplikasi berada di depan. Ketinggian Android mengacu pada
[elipsoid WGS 84](https://developer.android.com/reference/android/location/Location#getAltitude()).
Jika ponsel tidak memberikan elevasi, layar menampilkan tanda strip.
Akurasi horizontal yang ditampilkan adalah perkiraan radius posisi. Nilai itu
tidak mengukur ketelitian elevasi. Akurasi GNSS ponsel dipengaruhi kondisi
sinyal, misalnya gedung atau pepohonan yang menghalangi pandangan ke langit.
Gunakan perangkat survei geodetik jika pekerjaan mensyaratkan ketelitian
geodetik. [Referensi akurasi GPS](https://www.gps.gov/gps-accuracy)

Peta dapat digeser dan diperbesar. Marker biru mengikuti posisi ponsel, dan
lingkaran menunjukkan perkiraan akurasi horizontal jika tersedia. Peta memusat
saat posisi pertama diterima. Gunakan tombol **Kembali ke posisi saya**
untuk memusatkan lagi. Gambar peta memerlukan internet. Pengukuran GPS tetap
berjalan apabila tile gagal dimuat, dengan tombol untuk mencoba memuat peta lagi.
Atribusi peta menautkan [OpenStreetMap](https://www.openstreetmap.org/copyright).

Setelah koordinat dan elevasi valid, pilih **Simpan Hasil Survei**. Aplikasi
menyimpan pembacaan langsung ke SQLite lokal perangkat. Beranda, Riwayat, dan
marker hijau di peta langsung memuat ulang data dari SQLite lokal. Riwayat
memakai `created_at` dalam UTC sebagai waktu simpan dan menampilkannya dalam zona
waktu perangkat. Gunakan Riwayat untuk melihat detail, menghapus survei, atau
mengekspor data ke format **GeoJSON (`FeatureCollection`)** lewat tombol
**Ekspor GeoJSON** (bisa langsung **Unduh (.geojson)** ke folder `Download/`,
**Salin** ke *clipboard*, atau **Bagikan** ke aplikasi lain).

Untuk menguji GPS lapangan, gunakan ponsel Android dengan layanan lokasi
aktif. Lokasi dari emulator adalah simulasi.
