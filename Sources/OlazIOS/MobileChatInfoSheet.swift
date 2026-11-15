import SwiftUI

struct MobileChatInfoSheet: View {
    @Bindable var engine: ZaloEngine
    let conversationId: String
    @Binding var groupComposeRequest: GroupComposeRequest?
    var onJumpToMessage: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var mediaKind: SharedMediaKind = .images
    @State private var mediaItems: [ChatMessage] = []
    @State private var nextCursor: String?
    @State private var hasMore = false
    @State private var loadingMedia = false
    @State private var photoViewerItem: PhotoViewerItem?
    @State private var videoViewerItem: VideoViewerItem?

    private var summary: ZaloEngine.ConversationSummary? {
        engine.conversations.first { $0.id == conversationId }
    }

    private var plan: ConversationMenuPlan {
        ConversationMenuPlan.make(
            id: conversationId,
            preset: .chatBox,
            state: engine.conversationActions,
            unread: summary?.unread ?? 0,
            muted: engine.isConversationMuted(conversationId)
        )
    }

    private var pins: PinnedList {
        engine.pins[conversationId] ?? PinnedList(json: [:])
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        MobileAvatarView(
                            url: summary?.avatar,
                            name: conversationTitle,
                            size: 58,
                            isGroup: summary?.isGroup ?? false
                        )
                        VStack(alignment: .leading, spacing: 4) {
                            Text(conversationTitle)
                                .font(.title3.weight(.semibold))
                            if let members = summary?.members, summary?.isGroup == true, members > 0 {
                                Text("\(members) thành viên")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            if let muteInfo = engine.notificationSettings.mute(for: conversationId) {
                                Text(muteInfo.statusText())
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Tùy chọn hội thoại") {
                    if let pin = plan.pin {
                        Button {
                            if pin == .pin { engine.pinConversation(conversationId) } else { engine.unpinConversation(conversationId) }
                        } label: {
                            Label(pin == .pin ? "Ghim hội thoại" : "Bỏ ghim hội thoại", systemImage: pin == .pin ? "pin" : "pin.slash")
                        }
                    }

                    if let mute = plan.mute {
                        if mute == .unmute {
                            Button {
                                engine.unmuteConversation(conversationId)
                            } label: {
                                Label("Bật thông báo", systemImage: "bell")
                            }
                        } else {
                            Menu {
                                ForEach(MuteDuration.allCases) { d in
                                    Button(d.title) { engine.muteConversation(conversationId, d) }
                                }
                            } label: {
                                Label("Tắt thông báo", systemImage: "bell.slash")
                            }
                        }
                    }

                    if plan.showsLabel && !engine.conversationExtras.labels.isEmpty {
                        Picker("Phân loại", selection: Binding(
                            get: { engine.conversationExtras.labelByConversation[conversationId] ?? "" },
                            set: { engine.setConversationLabel(conversationId, labelId: $0.isEmpty ? nil : $0) }
                        )) {
                            Text("Không có").tag("")
                            ForEach(engine.conversationExtras.labels) { label in
                                Text(label.name).tag(label.id)
                            }
                        }
                    }

                    if summary?.isGroup == false && conversationId != engine.selfConversationId {
                        Button {
                            dismiss()
                            groupComposeRequest = GroupComposeRequest(members: [conversationId])
                        } label: {
                            Label("Tạo nhóm với người này", systemImage: "person.3")
                        }
                    }

                    if let hide = plan.hide {
                        Button {
                            dismiss()
                            engine.conversationPrompt = (hide == .hide) ? .hide(id: conversationId) : .unhide(id: conversationId)
                        } label: {
                            Label(hide == .hide ? "Ẩn trò chuyện" : "Hiện trò chuyện", systemImage: hide == .hide ? "eye.slash" : "eye")
                        }
                    }
                }

                if !pins.items.isEmpty {
                    Section("Đã ghim (\(pins.items.count))") {
                        ForEach(pins.items) { item in
                            Button {
                                if !item.msgId.isEmpty {
                                    onJumpToMessage(item.msgId)
                                } else if !item.cliMsgId.isEmpty {
                                    onJumpToMessage(item.cliMsgId)
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.label)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.orange)
                                    Text(item.title)
                                        .font(.subheadline)
                                        .lineLimit(2)
                                }
                            }
                            .swipeActions {
                                if pins.canPin {
                                    Button("Bỏ ghim", role: .destructive) {
                                        engine.requestUnpin(item, in: conversationId)
                                    }
                                }
                            }
                        }
                    }
                }

                Section {
                    Picker("Kho lưu trữ", selection: $mediaKind) {
                        Text("Ảnh/Video").tag(SharedMediaKind.images)
                        Text("File").tag(SharedMediaKind.files)
                        Text("Link").tag(SharedMediaKind.links)
                    }
                    .pickerStyle(.segmented)

                    if loadingMedia && mediaItems.isEmpty {
                        ProgressView("Đang tải...")
                    } else if mediaItems.isEmpty {
                        Text("Chưa có mục nào được chia sẻ.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(mediaItems) { msg in
                            sharedMediaRow(msg)
                        }
                        if hasMore {
                            Button("Tải thêm") {
                                Task { await loadMoreMedia(reset: false) }
                            }
                        }
                    }
                } header: {
                    Text("Ảnh, File, Link đã chia sẻ")
                }
            }
            .navigationTitle("Thông tin hội thoại")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Đóng") { dismiss() } }
            }
        }
        .task(id: mediaKind) {
            await loadMoreMedia(reset: true)
        }
        .fullScreenCover(item: $photoViewerItem) { item in
            MobilePhotoViewerSheet(item: item)
        }
        .fullScreenCover(item: $videoViewerItem) { item in
            MobileVideoPlayerSheet(item: item)
        }
    }

    private var conversationTitle: String {
        if conversationId == engine.selfConversationId { return "Cloud của tôi" }
        return summary?.displayName ?? "Trò chuyện"
    }

    @ViewBuilder
    private func sharedMediaRow(_ msg: ChatMessage) -> some View {
        switch msg.kind {
        case .photo(let url, _, _):
            Button {
                photoViewerItem = PhotoViewerItem(engine: engine, conversationId: conversationId, messageId: msg.id, fallbackURL: url)
            } label: {
                HStack(spacing: 12) {
                    MobileAsyncPhotoView(url: url, maxPixelSize: 220, contentMode: .fill)
                        .frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(msg.senderName.isEmpty ? "Hình ảnh" : msg.senderName)
                            .font(.subheadline.weight(.medium))
                        Text(msg.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)

        case .video(let thumb, _, let url):
            Button {
                videoViewerItem = VideoViewerItem(engine: engine, conversationId: conversationId, messageId: msg.id, fallbackURL: url)
            } label: {
                HStack(spacing: 12) {
                    MobileAsyncPhotoView(url: thumb ?? url, maxPixelSize: 220, contentMode: .fill)
                        .frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay { Image(systemName: "play.circle.fill").foregroundStyle(.white) }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Video từ \(msg.senderName)")
                            .font(.subheadline.weight(.medium))
                        Text(msg.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)

        case .file(let name, let size, let url):
            Button {
                Task {
                    guard let url else { return }
                    if let localURL = try? await MediaLoader.shared.localFile(for: url) {
                        NotificationCenter.default.post(name: .olazShareFileRequested, object: localURL)
                    } else {
                        WebLink.open(url)
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "doc.fill")
                        .font(.title3)
                        .foregroundStyle(ZaloTheme.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name).font(.subheadline.weight(.medium)).lineLimit(1)
                        Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)

        case .link(let title, let url, _, _, _):
            Button {
                WebLink.open(url)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "link")
                        .foregroundStyle(ZaloTheme.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title.isEmpty ? (url?.absoluteString ?? msg.text) : title)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        if let url {
                            Text(url.absoluteString)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .buttonStyle(.plain)

        default:
            EmptyView()
        }
    }

    private func loadMoreMedia(reset: Bool) async {
        loadingMedia = true
        defer { loadingMedia = false }
        let cursor = reset ? nil : nextCursor
        if let page = await engine.sharedMedia(in: conversationId, kind: mediaKind, after: cursor, limit: 30) {
            if reset { mediaItems = page.items } else { mediaItems.append(contentsOf: page.items) }
            nextCursor = page.cursor
            hasMore = page.more
        }
    }
}
