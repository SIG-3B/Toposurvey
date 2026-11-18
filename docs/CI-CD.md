# CI/CD dan Rilis Android

## Workflow

| Workflow | Pemicu | Fungsi |
|---|---|---|
| `Flutter CI` | Pull request ke `main` dan pemanggilan dari workflow release | `flutter analyze` dan `flutter test` |
| `Android Release` | Push ke `main` yang mengubah `frontend/**`, atau `workflow_dispatch` pada `main` | Validasi, signing, build APK, tag SemVer, checksum, dan GitHub Release |
| `Deploy GitHub Pages` | Perubahan `docs/**` pada `main`, atau `workflow_dispatch` | Deploy `docs/` |
| `CodeQL Security Scan` | Pull request, push ke `main`, dan mingguan | Analisis GitHub Actions, JavaScript/TypeScript, dan Python |
| `Dependency Review` | Pull request ke `main` | Menolak perubahan dependensi dengan kerentanan tingkat tinggi atau lebih |

Perubahan dokumentasi saja tidak menjalankan workflow rilis APK. Rilis manual
tersedia pada **Actions → Android Release → Run workflow** di branch `main`;
pilih `auto`, `patch`, `minor`, atau `major`. Mode `auto` menggunakan konvensi
commit: `BREAKING CHANGE`/`#major` menaikkan major, `feat:`/`#minor` menaikkan
minor, dan perubahan lainnya menaikkan patch. Tag pertama menggunakan versi
`MAJOR.MINOR.PATCH` di `frontend/pubspec.yaml`.

Nama tag, judul GitHub Release, dan `versionName` APK berasal dari satu versi
SemVer yang sama. `versionCode` APK berasal dari nomor run GitHub Actions.
Setiap rilis berisi satu `TopoSurvey.apk` dan satu `TopoSurvey.apk.sha256`;
workflow juga menyimpan keduanya sebagai Actions artifact selama 30 hari.
Release notes dibuat otomatis oleh GitHub.
Setelah mengunduh kedua file ke direktori yang sama, verifikasi checksum di
Linux/macOS dengan `sha256sum -c TopoSurvey.apk.sha256`. Di Windows,
bandingkan nilai `Get-FileHash .\TopoSurvey.apk -Algorithm SHA256` dengan nilai
hash pada file `.sha256`.

## Android release signing

Jangan menyimpan keystore, kata sandi, atau file hasil encoding ke repository.
Buat satu keystore release, simpan cadangan terenkripsi secara offline, dan
gunakan keystore yang sama untuk seluruh pembaruan aplikasi. Kehilangan atau
pergantian kunci membuat APK baru tidak dapat memperbarui instalasi yang
ditandatangani dengan kunci lama. APK lama yang ditandatangani debug juga tidak
dapat diperbarui langsung oleh APK release pertama; pengguna perlu mengganti
instalasi saat migrasi awal.

Buat keystore, misalnya:

```sh
keytool -genkeypair -v \
  -keystore toposurvey-release.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias toposurvey
```

Di **Settings → Secrets and variables → Actions → New repository secret**,
tambahkan:

| Secret | Nilai |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | Seluruh isi keystore dalam Base64 satu baris |
| `ANDROID_KEYSTORE_PASSWORD` | Kata sandi keystore |
| `ANDROID_KEY_ALIAS` | Alias yang dibuat pada langkah `keytool` |
| `ANDROID_KEY_PASSWORD` | Kata sandi key alias |

Di PowerShell, encoding dapat dibuat tanpa memasukkannya sebagai argumen
command-line:

```powershell
$encoded = [Convert]::ToBase64String([IO.File]::ReadAllBytes(".\toposurvey-release.jks"))
$encoded | gh secret set ANDROID_KEYSTORE_BASE64 --repo SIG-3B/Toposurvey
Remove-Variable encoded
```

Atur tiga secret lainnya melalui halaman Secrets GitHub. Simpan keystore dan
salinan cadangan dengan aman; hapus file Base64 sementara jika dibuat. Workflow
memvalidasi keberadaan secret, memakai kunci dari direktori sementara runner,
dan menghapus file kunci setelah job selesai. Release tidak pernah fallback ke
debug signing.

## Branch protection

`main` sebaiknya mewajibkan pull request dan status check
`Flutter CI / Analyze and Test Flutter`, menolak force-push serta penghapusan
branch, dan menerapkan aturan kepada administrator. Atur di **Settings →
Branches → Branch protection rules**. Pastikan pemeriksaan CI sudah pernah
berjalan sehingga status check tersebut tersedia untuk dipilih.

## Dependabot dan keamanan

`.github/dependabot.yml` memeriksa pembaruan GitHub Actions, Flutter Pub, dan
Python Pip setiap minggu. CodeQL berjalan pada setiap pull request, push ke
`main`, dan secara terjadwal; Dependency Review menilai perubahan dependensi
pada pull request. Tinjau hasil pemindaian dan Dependabot sebelum merge.
