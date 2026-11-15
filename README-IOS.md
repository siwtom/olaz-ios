# Olaz iOS — Hướng dẫn build IPA cho iPhone XS Max (iOS 17.0+)

Bản port iOS của **Olaz (`zalo-swift-re`)** chạy trực tiếp engine JS chính thức của Zalo PC (`WKWebView` + proxy TLS/HTTP2 Chromium 108 tích hợp qua Go static C-archive `libolazfp.a`), được tối ưu riêng cho **iPhone XS Max (`arm64`, Apple A12 Bionic, 4 GB RAM, iOS 17.0+)** và **nạp sẵn `app.asar` (`26.10.20`)** ngay trong file `.ipa`.

## Điểm nổi bật

- **Nạp sẵn `app.asar` (`ZaloSetup-universal-26.10.20.dmg`)**: Pipeline tự tải từ CDN chính thức VNG, kiểm tra `SHA-256` & chữ ký `CVB6BX97VM`, loại bỏ module macOS (`.node`, `.dylib`, `.so`, `unpacked`), đóng gói sẵn `Olaz.app/ZaloRuntime/Contents/Resources/app.asar` và map bằng `.alwaysMapped` để tiết kiệm RAM. Mở app là có ngay mã QR đăng nhập, không cần tải 100+ MB lúc chạy.
- **Tối ưu RAM cho A12 / 4 GB**:
  - Giảm cache `URLCache` (12 MB RAM / 250 MB disk) và `NSCache` (48 MB), tự dọn cache khi nhận memory warning hoặc khi vào nền (`scenePhase == .background`).
  - `SharedWorker` khởi chạy **theo nhu cầu** (khi mở tab **zCloud** hoặc bật trong **Cài đặt → Hiệu năng & Engine**), không chiếm RAM thường trực khi chỉ nhắn tin.
- **Fingerprint Helper nội bộ**: Biên dịch Go `FingerprintHelper` sang `libolazfp.a` (`GOOS=ios GOARCH=arm64`) lắng nghe trên loopback `127.0.0.1` bên trong sandbox ứng dụng (không dùng `Process` con).

---

## Cách 1: Build `.ipa` tự động trên GitHub Actions (Khuyên dùng khi đang ở Windows)

1. Push repo lên GitHub (nhánh `main`).
2. Vào tab **Actions → Build iOS IPA (Olaz) → Run workflow** (hoặc push tag dạng `v0.1.0-ios`).
3. Sau ~5–8 phút, tải artifact **`Olaz-iOS-IPA`** chứa **`Olaz-iOS-unsigned.ipa`** (đã nhúng sẵn `app.asar`).

### Ký tự động bằng chứng chỉ `muacert.com` ngay trong GitHub Actions (Tùy chọn)

Chứng chỉ đã kiểm tra trong `build/certs/00008020-001474A40A81002E/` (được `.gitignore` bỏ qua, không push lên git):
- **UDID thiết bị**: `00008020-001474A40A81002E` (iPhone XS Max)
- **Team / Chứng chỉ**: `YHYVTUKWV9` — `Apple Distribution: Runlin Chen (YHYVTUKWV9)` (hạn tới `02/11/2027`)
- **Explicit Bundle ID**: `app.lynx1884.lavender1499` (tên hiển thị ngoài màn hình chính vẫn giữ là **`Olaz`**)
- **Entitlements khớp profile**: `application-identifier`, `keychain-access-groups` (cho Keychain lưu phiên Zalo), kèm `increased-memory-limit` & `extended-virtual-addressing` (giúp `WKWebView` ổn định hơn trên máy 4 GB RAM)

Vào **Settings → Secrets and variables → Actions** trên repo GitHub của bạn và thêm 3 secret (đã xuất sẵn để copy tại thư mục gitignored `build/certs/gh-secrets/`):
- `MUACERT_P12_BASE64`: nội dung file `build/certs/gh-secrets/MUACERT_P12_BASE64.txt`
- `MUACERT_PROVISION_BASE64`: nội dung file `build/certs/gh-secrets/MUACERT_PROVISION_BASE64.txt`
- `MUACERT_P12_PASSWORD`: nội dung file `build/certs/gh-secrets/MUACERT_P12_PASSWORD.txt` (`1`)

> Có thể tạo lại bộ file secret bất kỳ lúc nào bằng:
> `python scripts/prepare-signing-profile.py --provision <file.mobileprovision> --p12 <file.p12> --password <pass> --export-gh-secrets build/certs/gh-secrets`

Khi có đủ secret, workflow sẽ tự động chạy `scripts/sign-ipa.sh`: đổi `CFBundleIdentifier` khớp provision (`app.lynx1884.lavender1499`), giữ tên app **`Olaz`**, nhúng entitlements chuẩn từ profile, ký ra **`Olaz-iOS-signed.ipa`** và kiểm tra lại nội dung `.ipa` trước khi upload artifact.

---

## Cách 2: Ký `Olaz-iOS-unsigned.ipa` với chứng chỉ `muacert.com` trực tiếp

Nếu chỉ tải `Olaz-iOS-unsigned.ipa` về máy/điện thoại:

### Trên chính iPhone XS Max (Feather / ESign — nhanh nhất)
1. Tải `Olaz-iOS-unsigned.ipa`, `cert.p12` (mật khẩu `1`) và `cert.mobileprovision` từ `muacert.com` vào app **Tệp (Files)**.
2. Mở **Feather** hoặc **ESign** → nạp cặp `.p12` + `.mobileprovision`.
3. Import `Olaz-iOS-unsigned.ipa` → **Sign / Ký** → **bắt buộc đặt Bundle ID = `app.lynx1884.lavender1499`** (theo đúng Explicit App ID trong profile; tên app giữ `Olaz`) → **Install**.

### Trên máy tính bằng `scripts/sign-ipa.sh` (macOS / Linux / WSL có `zsign`)
Script `scripts/sign-ipa.sh` tự động đọc `build/certs/00008020-001474A40A81002E/{cert.p12,cert.mobileprovision,pass.txt}`, sinh entitlements từ `.mobileprovision`, ký bằng `zsign` và verify lại `.ipa`:
```bash
bash scripts/sign-ipa.sh
```
Hoặc chỉ định đường dẫn chứng chỉ khác qua biến môi trường:
```bash
MUACERT_P12_PATH=cert.p12 MUACERT_P12_PASSWORD=1 MUACERT_PROVISION_PATH=cert.mobileprovision bash scripts/sign-ipa.sh
```
Sau đó cài `dist/Olaz-iOS-signed.ipa` qua **Sideloadly**, **3uTools**, **Apple Configurator (`cfgutil`)**, hoặc **Xcode Devices**.

---

## Cách 3: Build cục bộ trên máy Mac

Yêu cầu: macOS với Xcode 15+, Go 1.22+, Python 3.10+, Homebrew `xcodegen` và `zsign`:

```bash
GOTOOLCHAIN=auto bash scripts/build-ipa.sh
```

Nếu đã có sẵn chứng chỉ tại `build/certs/00008020-001474A40A81002E/` (hoặc truyền `MUACERT_P12_PATH`, `MUACERT_P12_PASSWORD`, `MUACERT_PROVISION_PATH`), script sẽ build cả `dist/Olaz-iOS-unsigned.ipa` lẫn **`dist/Olaz-iOS-signed.ipa`**.

---

## Đăng nhập QR trên chính chiếc iPhone XS Max

Olaz đóng vai trò một phiên Zalo PC chạy trực tiếp trên iPhone nên có thể chạy song song với ứng dụng Zalo chính thức:
1. Mở **Olaz** → chờ vài giây tạo mã QR → bấm **Lưu mã QR** (lưu vào Thư viện ảnh).
2. Mở app **Zalo** chính thức trên cùng máy → bấm biểu tượng **QR** góc trên bên phải → **Quét ảnh từ thư viện** → chọn ảnh QR vừa lưu → bấm **Đăng nhập**.
