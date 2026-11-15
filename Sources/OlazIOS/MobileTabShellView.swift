import SwiftUI

struct MobileTabShellView: View {
    enum Tab: Hashable {
        case chats, contacts, cloud, settings
    }

    @Bindable var engine: ZaloEngine

    @State private var selectedTab: Tab = .chats
    @State private var chatPath: [String] = []
    @State private var groupComposeRequest: GroupComposeRequest?

    private var unreadConversationBadge: Int {
        engine.visibleConversations.reduce(0) { $0 + ($1.unread > 0 ? 1 : 0) }
    }

    var body: some View {
        ZStack(alignment: .top) {
            TabView(selection: $selectedTab) {
                NavigationStack(path: $chatPath) {
                    MobileConversationListView(
                        engine: engine,
                        groupComposeRequest: $groupComposeRequest,
                        onOpenConversation: { openConversation($0) }
                    )
                    .navigationDestination(for: String.self) { conversationId in
                        MobileChatView(
                            engine: engine,
                            conversationId: conversationId,
                            groupComposeRequest: $groupComposeRequest
                        )
                    }
                }
                .tabItem {
                    Label("Tin nhắn", systemImage: "bubble.left.and.bubble.right.fill")
                }
                .badge(unreadConversationBadge)
                .tag(Tab.chats)

                MobileContactsView(
                    engine: engine,
                    groupComposeRequest: $groupComposeRequest,
                    onOpenConversation: { openConversation($0) }
                )
                .tabItem {
                    Label("Danh bạ", systemImage: "person.2.fill")
                }
                .badge(engine.contacts.pendingRequestCount)
                .tag(Tab.contacts)

                MobileCloudView(
                    engine: engine,
                    onOpenConversation: { openConversation($0) }
                )
                .tabItem {
                    Label("zCloud", systemImage: "icloud.fill")
                }
                .tag(Tab.cloud)

                MobileSettingsView(engine: engine)
                    .tabItem {
                        Label("Cài đặt", systemImage: "gearshape.fill")
                    }
                    .tag(Tab.settings)
            }

            VStack(spacing: 8) {
                if let toast = engine.conversationUI.toast {
                    toastBanner(toast)
                }
                if let incoming = engine.call.incoming {
                    incomingCallBanner(incoming)
                }
                if let transfer = engine.transfer {
                    transferBanner(transfer)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
        }
        .onChange(of: engine.navigationRequest) { _, target in
            guard let target, !target.isEmpty else { return }
            engine.navigationRequest = nil
            openConversation(target)
        }
        .onChange(of: engine.conversationUI.removal) { _, removal in
            guard let removal else { return }
            chatPath.removeAll { removal.ids.contains($0) }
        }
        .onReceive(NotificationCenter.default.publisher(for: SectionRouter.notification)) { note in
            guard let raw = note.object as? String, let target = SidebarTarget(rawValue: raw) else { return }
            switch target {
            case .chats:
                selectedTab = .chats
            case .contacts, .groups:
                selectedTab = .contacts
            }
        }
        .sheet(item: $groupComposeRequest) { req in
            MobileCreateGroupSheet(engine: engine, initialMembers: req.members)
        }
        .alert(item: Binding(
            get: { engine.call.notice },
            set: { if $0 == nil { engine.dismissCallNotice() } }
        )) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("Đóng"))
            )
        }
    }

    private func openConversation(_ id: String) {
        selectedTab = .chats
        if chatPath.last != id {
            if chatPath.isEmpty {
                chatPath = [id]
            } else {
                chatPath[chatPath.count - 1] = id
            }
        }
    }

    private func toastBanner(_ toast: ConversationActionUI.Toast) -> some View {
        let tint: Color = switch toast.kind {
        case .success: .green
        case .neutral: ZaloTheme.blue
        case .failure: .red
        }
        return HStack(spacing: 8) {
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)
            Text(toast.text)
                .font(.footnote.weight(.medium))
                .lineLimit(2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func incomingCallBanner(_ incoming: CallState.Incoming) -> some View {
        HStack(spacing: 12) {
            MobileAvatarView(url: incoming.avatar, name: incoming.name, size: 40, isGroup: incoming.group)
            VStack(alignment: .leading, spacing: 2) {
                Text(incoming.name.isEmpty ? "Cuộc gọi đến" : incoming.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(incoming.caller.map { "\($0) đang gọi" } ?? "Cuộc gọi thoại/video chỉ khả dụng trên Zalo chính thức trên iPhone.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Button("Đóng") {
                engine.dismissIncomingCall()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }

    private func transferBanner(_ transfer: MessageTransferState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            switch transfer.phase {
            case .offer:
                Text(transfer.officialTitle ?? "Đồng bộ tin nhắn từ điện thoại")
                    .font(.subheadline.weight(.semibold))
                Text(transfer.officialDescription ?? transfer.message ?? "Cho phép chuyển lịch sử tin nhắn về phiên Olaz này.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Button("Đồng bộ") {
                        engine.respondToTransfer(accept: true)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    Button("Để sau") {
                        engine.respondToTransfer(accept: false)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

            case .waitingForPhone:
                HStack(spacing: 10) {
                    ProgressView()
                    Text(transfer.message ?? "Vui lòng xác nhận đồng bộ trên điện thoại...")
                        .font(.caption)
                    Spacer()
                    Button("Đóng") { engine.dismissTransfer() }
                        .font(.caption)
                }

            case .transferring:
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(transfer.message ?? "Đang đồng bộ tin nhắn...")
                            .font(.caption.weight(.medium))
                        Spacer()
                        if let total = transfer.totalConversations, total > 0 {
                            Text("\(transfer.syncedConversations)/\(total)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let progress = transfer.progress {
                        ProgressView(value: min(max(progress, 0), 1))
                    } else {
                        ProgressView()
                    }
                }

            case .finished:
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Đồng bộ tin nhắn hoàn tất")
                        .font(.caption.weight(.medium))
                    Spacer()
                    Button("Đóng") { engine.dismissTransfer() }
                        .font(.caption)
                }

            case .failed(let msg):
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(msg)
                        .font(.caption)
                        .lineLimit(2)
                    Spacer()
                    if transfer.canRetry {
                        Button("Thử lại") { engine.respondToTransfer(accept: true) }
                            .font(.caption.weight(.semibold))
                    }
                    Button("Đóng") { engine.dismissTransfer() }
                        .font(.caption)
                }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.1), radius: 8, y: 3)
    }
}
