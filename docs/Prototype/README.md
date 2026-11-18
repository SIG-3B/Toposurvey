# TopoSurvey Mobile — Prototipe Android Interaktif

**Status:** prototipe PWA/web interaktif, bukan APK Kotlin native. Berdasarkan dokumen "Rancangan Lengkap Aplikasi Android Survei Topografi" (17 November 2026).

## Ruang lingkup

Tujuh menu utama: Dashboard, Ambil Koordinat, Peta Survei, Data Survei, Riwayat Aktivitas, Ekspor Data, Pengaturan. Fitur yang sudah bekerja dalam prototipe:

- Meminta izin GPS secara eksplisit dan membaca satu fix baru melalui **Browser Geolocation API** (`enableHighAccuracy: true`, `maximumAge: 0`, timeout 20 detik).
- Memvalidasi longitude/latitude, usia fix maksimal 30 detik, dan status akurasi; memberikan peringatan akurasi rendah.
- Menampilkan elevasi WGS84 elipsoid bila tersedia, atau keterangan "Tidak tersedia" jika tidak diberikan API browser.
- Membuat, memilih, mengubah, dan menghapus proyek; simpan titik dengan kode/nama/catatan.
- Penyimpanan lokal persisten di `localStorage` browser (prototipe, belum Room Database).
- Data survei: cari, filter per proyek, detail, ubah metadata, hapus dengan konfirmasi.
- Jejak aktivitas untuk pembuatan, pembaruan, penghapusan titik, pengelolaan proyek, dan ekspor.
- Peta interaktif dengan pan, zoom dan marker. Basemap OSM online; grid peta tetap dapat digunakan saat offline.
- Ekspor **CSV**, **GeoJSON**, **KML**, serta **Cetak / Simpan sebagai PDF** melalui dialog cetak browser.
- Ekspor/impor seluruh data dalam backup JSON dengan validasi dan konfirmasi penggantian data.
- Tema terang/gelap, preferensi akurasi, mode demo terpisah dari pengukuran asli.
- PWA dapat diinstal ke layar utama Android dari Chrome; cache berkas aplikasi melalui service worker.

## Menjalankan lokal

Buka terminal di folder ini dan jalankan:

```bash
python -m http.server 8000
```

Lalu buka `http://localhost:8000`. GPS pada HP membutuhkan **HTTPS**; `localhost` adalah pengecualian hanya untuk perangkat yang menjalankan server itu sendiri. Jika membuka server lokal komputer dari HP menggunakan IP jaringan biasa `http://192.168...`, Geolocation API dapat ditolak karena tidak berada pada secure context. Untuk uji GPS di HP, unggah ke GitHub Pages (HTTPS).

## Deploy GitHub Pages

1. Buat repositori GitHub, lalu unggah seluruh isi folder ini ke root branch `main`.
2. Buka **Settings → Pages → Build and deployment → Deploy from a branch**.
3. Pilih `main` dan `/ (root)` lalu Save.
4. Buka alamat `https://<user>.github.io/<repo>/` dan izinkan akses lokasi saat dibutuhkan.
5. Di Chrome Android buka menu tiga titik → **Add to Home screen** / **Install app** (ketersediaan tergantung Chrome dan perangkat).

## Demonstrasi tanpa GPS

Buka **Ambil Koordinat → Coba Mode Demo** untuk fix simulasi tunggal; atau **Pengaturan → Isi Data Contoh untuk Demo** untuk 6 titik. Semua data simulasi diberi `source=DEMO` dan label visual yang berbeda. **Jangan klaim data simulasi sebagai hasil survei nyata.**

## Batasan penting

- Ini adalah **prototipe**, belum APK native, belum menggunakan Room Database, belum diuji pada seluruh versi Android, dan belum memiliki sistem akun atau sinkronisasi server.
- GPS ponsel **bukan** instrumen topografi berketelitian tinggi. Akurasi horizontal dari browser merupakan estimasi, bukan jaminan galat nyata.
- Nilai `altitude`, jika tersedia, dilabel sebagai ketinggian di atas elipsoid WGS84, **bukan** otomatis tinggi atas permukaan laut (MSL). Tidak ada datum conversion yang dibuat-buat.
- `localStorage` dapat hilang jika data browser dibersihkan atau mode privat dipakai; lakukan **Unduh Backup JSON** secara berkala. Tidak cocok untuk arsip produksi skala besar.
- Peta dasar OSM online perlu jaringan; grid offline bukan peta topografi offline. PWA cache hanya untuk berkas aplikasi, **tidak** menyimpan tile OSM massal.
- Laporan PDF via browser print: pilih printer **Save as PDF** secara manual; ini bukan engine PDF native.
- Preferensi satuan `ft` mengubah tampilan elevasi dan akurasi menjadi kaki, tetapi seluruh nilai mentah yang disimpan dan diekspor tetap menggunakan meter; koordinat tetap derajat desimal.

## Rekomendasi porting ke native Android

Kotlin, Jetpack Compose, Fused Location Provider `getCurrentLocation`, `Location.hasAltitude`, Room Database untuk tabel `project`, `survey_point`, `point_activity`, serta Android Storage Access Framework untuk ekspor dan pemulihan. Terapkan pola MVVM dan uji perangkat nyata. Versi PWA ini **bukan** substitusi implementasi tersebut.

## Struktur

```
index.html              Shell UI
styles.css              Responsive styling, mobile bottom navigation, print styling
app.js                  State, routes, GPS, CRUD, map, ekspor, backup
manifest.webmanifest    Metadata install PWA
sw.js                   Cache shell offline
icons/                  Ikon PWA
README.md               Petunjuk dan batasan
```

## Privasi

Tidak memakai backend. Pembacaan GPS terjadi atas tindakan pengguna. Titik disimpan dalam storage browser. Jika membuka peta OSM online, tile dimuat dari `tile.openstreetmap.org`; stylesheet juga meminta font dari Google Fonts saat online. Keduanya adalah layanan pihak ketiga. Untuk penggunaan yang membutuhkan perlindungan data lokasi khusus, lakukan peninjauan keamanan dan migrasikan penyimpanan ke database native terenkripsi sesuai kebutuhan.
