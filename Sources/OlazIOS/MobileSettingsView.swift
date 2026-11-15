import SwiftUI

struct MobileSettingsView: View {
    @Bindable var engine: ZaloEngine

    @AppStorage("olaz.appearance") private var appearanceMode = 0
    @AppStorage("olaz.accent") private var accentHex = "#0068FF"

    @State private var showResetPINConfirm = false
    @State private var showSetPIN = false
    @State private var newPIN = ""
    @State private var showLogsSheet = false
    @State private var showSignOutConfirm = false
    @State private var feedbackText: String?

    var body: some View {
        NavigationStack {
            List {
                if let profile = engine.profile {
                    Section {
                        HStack(spacing: 14) {
                            MobileAvatarView(url: profile.avatar, name: profile.displayName, size: 58)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(profile.displayName)
                                    .font(.headline)
                                if let phone = profile.phone, !phone.isEmpty {
                                    Text(phone)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                Text("ID: \(profile.userId)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                if let feedbackText {
                    Section {
                        Text(feedbackText)
                            .font(.footnote)
                            .foregroundStyle(ZaloTheme.blue)
                    }
                }

                Section("Giao diện") {
                    Picker("Chế độ màu", selection: $appearanceMode) {
                        Text("Hệ thống").tag(0)
                        Text("Sáng").tag(1)
                        Text("Tối").tag(2)
                    }
                    Picker("Màu nhấn", selection: $accentHex) {
                        Text("Zalo Blue").tag("#0068FF")
                        Text("Teal").tag("#00A88F")
                        Text("Tím").tag("#6F3FCF")
                        Text("Cam").tag("#FF6905")
                    }
                }

                Section("Thông báo") {
                    Toggle("Nhận thông báo", isOn: Binding(
                        get: { engine.notificationSettings.enabled },
                        set: { engine.setNotificationsEnabled($0) }
                    ))
                    Toggle("Âm thanh thông báo", isOn: Binding(
                        get: { engine.notificationSettings.sound },
                        set: { engine.setNotificationSound($0) }
                    ))
                    Toggle("Hiển thị nội dung xem trước", isOn: Binding(
                        get: { engine.notificationSettings.showsPreview },
                        set: { engine.setMessagePreview($0) }
                    ))
                    Button("Cài đặt thông báo iOS") {
                        engine.openSystemNotificationSettings()
                    }
                }

                if engine.conversationActions.hiddenEnabled {
                    Section("Trò chuyện ẩn") {
                        Button(engine.conversationActions.hasHiddenPIN ? "Đổi mã PIN 4 số" : "Tạo mã PIN 4 số") {
                            newPIN = ""
                            showSetPIN = true
                        }
                        if engine.conversationActions.hasHiddenPIN {
                            Button("Xóa mã PIN & bỏ ẩn tất cả", role: .destructive) {
                                showResetPINConfirm = true
                            }
                        }
                    }
                }

                Section("Đồng bộ tin nhắn") {
                    Button("Đồng bộ tin nhắn từ điện thoại") {
                        engine.startTransfer()
                    }
                    .disabled(!engine.canStartTransfer)
                    if let reason = engine.transferStartBlockedReason, !engine.canStartTransfer {
                        Text(ZaloEngine.transferBlockedText(reason))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    HStack {
                        Text("Phiên bản Zalo JS")
                        Spacer()
                        Text(engine.clientVersion ?? "26.10.20")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Proxy vân tay")
                        Spacer()
                        Text(FingerprintProxy.shared.statusLabel)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Lưu trữ cục bộ")
                        Spacer()
                        Text(engine.storageBackend?.rawValue ?? "Đang khởi tạo")
                            .foregroundStyle(.secondary)
                    }
                    Toggle("Tiến trình nền (zCloud / Sao lưu)", isOn: Binding(
                        get: { engine.isBackgroundWorkerRunning },
                        set: { enabled in
                            if enabled { engine.ensureBackgroundWorker() } else { engine.stopBackgroundWorker() }
                        }
                    ))
                    Button("Dọn bộ nhớ cache ảnh/media") {
                        engine.purgeMediaMemory()
                        feedbackText = "Đã giải phóng bộ nhớ cache media."
                    }
                    Button("Xem nhật ký Engine") {
                        showLogsSheet = true
                    }
                } header: {
                    Text("Hiệu năng & Engine (iPhone XS Max 4GB)")
                }

                Section {
                    Button("Đăng xuất", role: .destructive) {
                        showSignOutConfirm = true
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Cài đặt")
            .onAppear {
                engine.notificationSettingsDidAppear()
            }
            .confirmationDialog("Xác nhận đăng xuất?", isPresented: $showSignOutConfirm, titleVisibility: .visible) {
                Button("Đăng xuất", role: .destructive) {
                    engine.logOut()
                }
                Button("Hủy", role: .cancel) {}
            }
            .confirmationDialog("Xóa mã PIN và toàn bộ danh sách ẩn?", isPresented: $showResetPINConfirm, titleVisibility: .visible) {
                Button("Xác nhận xóa PIN", role: .destructive) {
                    Task {
                        let res = await engine.resetHiddenChatPIN()
                        feedbackText = res.text.isEmpty ? "Đã xóa mã PIN trò chuyện ẩn." : res.text
                    }
                }
                Button("Hủy", role: .cancel) {}
            }
            .sheet(isPresented: $showSetPIN) {
                NavigationStack {
                    Form {
                        SecureField("Nhập PIN 4 chữ số", text: $newPIN)
                            .keyboardType(.numberPad)
                    }
                    .navigationTitle(engine.conversationActions.hasHiddenPIN ? "Đổi mã PIN" : "Tạo mã PIN")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Hủy") { showSetPIN = false } }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Lưu") {
                                Task {
                                    let res = await engine.setHiddenChatPIN(newPIN, changed: engine.conversationActions.hasHiddenPIN)
                                    feedbackText = res.text
                                    showSetPIN = false
                                }
                            }
                            .disabled(newPIN.count != 4)
                        }
                    }
                }
            }
            .sheet(isPresented: $showLogsSheet) {
                NavigationStack {
                    List(engine.recentLog, id: \.self) { line in
                        Text(line)
                            .font(.caption.monospaced())
                    }
                    .navigationTitle("Nhật ký Engine")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Đóng") { showLogsSheet = false } }
                    }
                }
            }
        }
    }
}
