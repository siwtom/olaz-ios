import SwiftUI
import UIKit

struct IOSRootView: View {
    @Bindable var engine: ZaloEngine

    var body: some View {
        Group {
            switch engine.phase {
            case .starting:
                launchPlaceholder
            case .preparing(let setup):
                preparingView(setup)
            case .login(let login):
                IOSLoginView(engine: engine, login: login, signOutNotice: engine.signOutNotice)
            case .signingIn:
                signingInView
            case .ready:
                MobileTabShellView(engine: engine)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: engine.phase)
    }

    private var launchPlaceholder: some View {
        VStack(spacing: 18) {
            ZaloWordmark(size: 42)
            ProgressView()
                .controlSize(.large)
            Text("Đang khởi động máy khách Zalo...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    private func preparingView(_ setup: ZaloEngine.RuntimeSetup) -> some View {
        VStack(spacing: 20) {
            ZaloWordmark(size: 36)
            if let failure = setup.failure {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 38))
                        .foregroundStyle(.orange)
                    Text("Không nạp được ZaloRuntime")
                        .font(.headline)
                    Text(failure)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Button("Thử lại") {
                        engine.retryRuntimeSetup()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 24)
            } else {
                ProgressView()
                    .controlSize(.large)
                Text("Đang chuẩn bị gói tài nguyên Zalo...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    private var signingInView: some View {
        VStack(spacing: 16) {
            ZaloWordmark(size: 36)
            ProgressView()
                .controlSize(.large)
            Text("Đang đăng nhập và đồng bộ hội thoại...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}

struct IOSLoginView: View {
    let engine: ZaloEngine
    let login: ZaloEngine.LoginState
    let signOutNotice: String?

    @State private var savedNotice: String?
    @State private var showQRShare = false
    @State private var shareImage: UIImage?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ZaloWordmark(size: 38)
                    .padding(.top, 24)

                Text("Đăng nhập Zalo bằng mã QR")
                    .font(.title3.weight(.semibold))

                if let signOutNotice, !signOutNotice.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(.orange)
                        Text(signOutNotice)
                            .font(.footnote)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(12)
                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                }

                qrCard

                VStack(alignment: .leading, spacing: 8) {
                    Label("Cách đăng nhập trên chính iPhone này:", systemImage: "iphone.and.arrow.forward")
                        .font(.subheadline.weight(.semibold))
                    Text("1. Nhấn \"Lưu mã QR\" hoặc chụp ảnh màn hình.\n2. Mở ứng dụng Zalo chính thức → chạm biểu tượng QR → \"Quét ảnh từ thư viện\".\n3. Chọn ảnh QR vừa lưu và xác nhận \"Đăng nhập\".")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))

                if let savedNotice {
                    Text(savedNotice)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.green)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
            .frame(maxWidth: 460)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .sheet(isPresented: $showQRShare) {
            if let shareImage {
                ActivityShareSheet(items: [shareImage])
                    .ignoresSafeArea()
            }
        }
    }

    @ViewBuilder
    private var qrCard: some View {
        VStack(spacing: 16) {
            if login.isSecondQR {
                Text("Mã xác thực bước 2 (thiết bị tin cậy)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.14), in: Capsule())
            }

            switch login.step {
            case .generating:
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Đang tạo mã QR...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 220, height: 220)

            case .waitingScan:
                qrImageBlock

            case .waitingConfirm(let name, let avatar):
                VStack(spacing: 12) {
                    MobileAvatarView(url: avatar, name: name, size: 72)
                    Text(name.isEmpty ? "Tài khoản Zalo" : name)
                        .font(.headline)
                    Text("Đã quét mã. Vui lòng bấm \"Đăng nhập\" trên điện thoại.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    ProgressView()
                }
                .frame(minHeight: 220)

            case .expired:
                VStack(spacing: 12) {
                    Image(systemName: "qrcode")
                        .font(.system(size: 54))
                        .foregroundStyle(.secondary)
                    Text("Mã QR đã hết hạn")
                        .font(.headline)
                    Button {
                        engine.refreshQR()
                    } label: {
                        Label("Tạo mã QR mới", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(width: 220, height: 220)

            case .failed(let message):
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.red)
                    Text(message)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                    Button("Thử lại") {
                        engine.refreshQR()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(minWidth: 220, minHeight: 220)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    @ViewBuilder
    private var qrImageBlock: some View {
        if let data = login.qrPNG, let image = PlatformImageCodec.decode(data: data) {
            VStack(spacing: 14) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 220, height: 220)
                    .padding(12)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.08), radius: 8, y: 2)

                HStack(spacing: 12) {
                    Button {
                        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                        savedNotice = "Đã lưu mã QR vào Thư viện ảnh."
                    } label: {
                        Label("Lưu mã QR", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        shareImage = image
                        showQRShare = true
                    } label: {
                        Label("Chia sẻ", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        engine.refreshQR()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Làm mới QR")
                }
            }
        } else {
            ProgressView("Đang hiển thị mã QR...")
                .frame(width: 220, height: 220)
        }
    }
}
