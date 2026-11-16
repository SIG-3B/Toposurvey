# TopoSurvey

Aplikasi Android Material 3 untuk mengukur koordinat dan elevasi dengan layanan
lokasi ponsel dan menampilkan posisi di peta OpenStreetMap. Backend FastAPI
menyediakan API survei dengan penyimpanan SQLite.

Ukur lintang, bujur, dan elevasi, lalu lihat posisi serta titik tersimpan di
peta. Riwayat menyediakan detail dan penghapusan survei.

## Unduh APK (GitHub Release)

APK siap pasang dapat diunduh langsung melalui halaman rilis GitHub berikut:

- **Halaman Rilis (`v1.0.1`):** [GitHub Release v1.0.1](https://github.com/SIG-3B/Toposurvey/releases/tag/v1.0.1)
- **Unduh Langsung APK:** [TopoSurvey-v1.0.1.apk](https://github.com/SIG-3B/Toposurvey/releases/download/v1.0.1/TopoSurvey-v1.0.1.apk)
- **Semua Rilis Terbaru:** [GitHub Releases](https://github.com/SIG-3B/Toposurvey/releases)

---

- `frontend/` berisi aplikasi Flutter dan Dart dengan Material 3, Geolocator,
  Flutter Map, LatLong2, OpenStreetMap, dan `http`. Layar, model, layanan,
  dan widget peta berada di `frontend/lib/`. Uji Flutter ada di `frontend/test/`.
- `backend/` berisi REST API FastAPI untuk Python dan database SQLite yang
  diakses melalui `sqlite3`.

Siapkan Flutter 3.47.4 (Dart 3.13.3), Android SDK dan emulator atau perangkat
Android, serta Python 3.11 atau lebih baru. Periksa instalasi Android dengan
`flutter doctor -v`.

## Backend

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
`{"status":"ok","database":"ok"}`. Saat dijalankan lokal, backend membuat tabel `surveys` di
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

## SQLite di Railway

Pasang volume pada layanan backend dengan mount path `/data`. Backend membaca
`RAILWAY_VOLUME_MOUNT_PATH` yang disediakan Railway dan menyimpan database di
`/data/toposurvey.sqlite3`. [Panduan Railway Volume](https://docs.railway.com/volumes)

Jika server sudah berisi hasil survei, cadangkan SQLite lama sebelum
redeploy dan pindahkan salinannya ke volume. Perubahan lokasi ini tidak
menyalin data lama secara otomatis.

## Frontend

Nyalakan emulator Android, lalu jalankan dari root proyek di terminal baru:

```powershell
cd frontend
flutter pub get
flutter analyze
flutter test
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

`API_BASE_URL` dibaca saat kompilasi dan default ke `http://10.0.2.2:8000`.
Alamat `10.0.2.2` mengarah ke [komputer host dari emulator Android](https://developer.android.com/studio/run/emulator-networking-address). Untuk HP
fisik di jaringan yang sama, gunakan IP LAN komputer sebagai nilai
`API_BASE_URL` (misalnya `http://192.168.1.20:8000`). Jika koneksi terhalang,
izinkan port 8000 pada firewall untuk jaringan privat yang dipercaya.
Gunakan HTTP untuk pengembangan lokal dengan build debug. Gunakan HTTPS
untuk build rilis.

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
mengirim satu pembacaan ke FastAPI. Setelah server mengonfirmasi, Beranda,
Riwayat, dan marker hijau di peta memuat ulang data SQLite. Riwayat memakai
`created_at` dari backend sebagai waktu simpan dan menampilkannya dalam zona
waktu perangkat. Gunakan Riwayat untuk melihat detail atau menghapus survei.

Pengukuran GPS tetap tersedia saat backend tidak terjangkau. Jumlah survei
akan ditandai belum tersedia sampai berhasil dimuat. Aplikasi memerlukan akses
ke backend untuk menyimpan titik dan tidak mengantrekan penyimpanan luring.
Jika permintaan simpan kehabisan waktu, cek Riwayat sebelum mencoba lagi.
Untuk menguji GPS lapangan, gunakan ponsel Android dengan layanan lokasi
aktif. Lokasi dari emulator adalah simulasi.
