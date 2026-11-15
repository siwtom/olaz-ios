import SwiftUI

struct MobileChatView: View {
    @Bindable var engine: ZaloEngine
    let conversationId: String
    @Binding var groupComposeRequest: GroupComposeRequest?

    @State private var replyTo: ChatMessage?
    @State private var showChatInfo = false
    @State private var photoViewerItem: PhotoViewerItem?
    @State private var videoViewerItem: VideoViewerItem?
    @State private var reactionDetailRequest: ReactionDetailRequest?
    @State private var pendingScrollMessageId: String?

    private var summary: ZaloEngine.ConversationSummary? {
        engine.conversations.first { $0.id == conversationId }
    }

    private var messages: [ChatMessage] {
        engine.messages[conversationId] ?? []
    }

    private var pinnedList: PinnedList {
        engine.pins[conversationId] ?? PinnedList(json: [:])
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    if engine.hasMoreHistory[conversationId] == true {
                        Button {
                            engine.loadOlderMessages(conversationId)
                        } label: {
                            Label("Xem tin nhắn cũ hơn", systemImage: "arrow.up.circle")
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(Color(.tertiarySystemFill), in: Capsule())
                        }
                        .padding(.top, 8)
                    }

                    ForEach(Array(messages.enumerated()), id: \.element.id) { index, msg in
                        let previous = index > 0 ? messages[index - 1] : nil
                        let showsSender = !msg.isMine
                            && (summary?.isGroup ?? false)
                            && (previous == nil || previous?.senderId != msg.senderId || previous?.kind.isStandalone == true)
                        let showsDay = previous == nil || !Calendar.current.isDate(msg.date, inSameDayAs: previous!.date)

                        if showsDay {
                            daySeparator(msg.date)
                        }

                        MobileMessageBubble(
                            engine: engine,
                            message: msg,
                            showsSenderName: showsSender,
                            onReply: { replyTo = $0 },
                            onOpenPhoto: { photoViewerItem = PhotoViewerItem(engine: engine, conversationId: conversationId, messageId: msg.id, fallbackURL: $0) },
                            onOpenVideo: { videoViewerItem = VideoViewerItem(engine: engine, conversationId: conversationId, messageId: msg.id, fallbackURL: $0) },
                            onShowReactions: { reactionDetailRequest = ReactionDetailRequest(conversationId: conversationId, messageId: msg.id) }
                        )
                        .id(msg.id)
                    }

                    if let typer = engine.typing[conversationId] {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.mini)
                            Text("\(typer) đang nhập...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .top, spacing: 0) {
                topInsetContent(proxy: proxy)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                MobileComposerBar(
                    engine: engine,
                    conversationId: conversationId,
                    isGroup: summary?.isGroup ?? false,
                    replyTo: $replyTo
                )
            }
            .onChange(of: pendingScrollMessageId) { _, targetId in
                guard let targetId else { return }
                pendingScrollMessageId = nil
                withAnimation {
                    proxy.scrollTo(targetId, anchor: .center)
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(conversationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    if let groupGate = engine.call.conversationGroup, !groupGate.disabled, !engine.canCall {
                        Image(systemName: "video.slash")
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        showChatInfo = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                }
            }
        }
        .task(id: conversationId) {
            engine.openConversation(conversationId)
            if messages.contains(where: { _ in false }) { }
        }
        .onDisappear {
            if engine.openConversationId == conversationId {
                engine.closeConversation()
                CardActionCenter.shared.reset()
            }
        }
        .sheet(isPresented: $showChatInfo) {
            MobileChatInfoSheet(
                engine: engine,
                conversationId: conversationId,
                groupComposeRequest: $groupComposeRequest,
                onJumpToMessage: { msgId in
                    showChatInfo = false
                    pendingScrollMessageId = msgId
                }
            )
        }
        .fullScreenCover(item: $photoViewerItem) { item in
            MobilePhotoViewerSheet(item: item)
        }
        .fullScreenCover(item: $videoViewerItem) { item in
            MobileVideoPlayerSheet(item: item)
        }
        .sheet(item: $reactionDetailRequest) { req in
            MobileReactionDetailSheet(engine: engine, conversationId: req.conversationId, messageId: req.messageId)
        }
        .sheet(item: Binding(
            get: { engine.forwardRequest },
            set: { if $0 == nil { engine.forwardRequest = nil } }
        )) { req in
            MobileForwardSheet(engine: engine, request: req)
        }
        .sheet(item: Binding(
            get: { CardActionCenter.shared.profile },
            set: { CardActionCenter.shared.profile = $0 }
        )) { req in
            MobileProfileSheet(engine: engine, request: req)
        }
        .sheet(item: Binding(
            get: { CardActionCenter.shared.alias },
            set: { CardActionCenter.shared.alias = $0 }
        )) { req in
            MobileAliasSheet(engine: engine, request: req)
        }
        .sheet(item: Binding(
            get: { CardActionCenter.shared.groupInvite },
            set: { CardActionCenter.shared.groupInvite = $0 }
        )) { req in
            MobileGroupInviteSheet(engine: engine, request: req)
        }
        .sheet(item: Binding(
            get: { CardActionCenter.shared.stickers },
            set: { CardActionCenter.shared.stickers = $0 }
        )) { req in
            MobileStickerCategorySheet(engine: engine, request: req)
        }
        .sheet(item: Binding(
            get: { CardActionCenter.shared.reminder },
            set: { CardActionCenter.shared.reminder = $0 }
        )) { req in
            MobileReminderDetailSheet(engine: engine, request: req)
        }
        .sheet(item: Binding(
            get: { CardActionCenter.shared.poll },
            set: { CardActionCenter.shared.poll = $0 }
        )) { req in
            MobilePollDetailSheet(engine: engine, request: req)
        }
        .alert(
            engine.messageConfirm?.title ?? "",
            isPresented: Binding(
                get: { engine.messageConfirm != nil },
                set: { if !$0, let c = engine.messageConfirm { engine.answerMessageConfirm(c, ok: false) } }
            )
        ) {
            if let c = engine.messageConfirm {
                Button(c.ok, role: c.destructive ? .destructive : nil) {
                    engine.answerMessageConfirm(c, ok: true)
                }
                Button(c.cancel, role: .cancel) {
                    engine.answerMessageConfirm(c, ok: false)
                }
            }
        } message: {
            Text(engine.messageConfirm?.message ?? "")
        }
        .alert(
            engine.composerConfirm?.title ?? "",
            isPresented: Binding(
                get: { engine.composerConfirm != nil },
                set: { if !$0, let c = engine.composerConfirm { engine.answerComposerConfirm(c, ok: false) } }
            )
        ) {
            if let c = engine.composerConfirm {
                Button(c.ok) { engine.answerComposerConfirm(c, ok: true) }
                Button(c.cancel, role: .cancel) { engine.answerComposerConfirm(c, ok: false) }
            }
        } message: {
            Text(engine.composerConfirm?.message ?? "")
        }
    }

    private var conversationTitle: String {
        if conversationId == engine.selfConversationId { return "Cloud của tôi" }
        return summary?.displayName ?? "Trò chuyện"
    }

    @ViewBuilder
    private func topInsetContent(proxy: ScrollViewProxy) -> some View {
        VStack(spacing: 0) {
            if let firstPin = pinnedList.items.first {
                Button {
                    if let target = firstPin.message(in: messages) {
                        withAnimation { proxy.scrollTo(target.id, anchor: .center) }
                    } else if firstPin.kind == .poll {
                        CardActionCenter.shared.poll = PollRequest(conversationId: conversationId, pollId: firstPin.ref)
                    } else {
                        showChatInfo = true
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "pin.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(firstPin.label)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.orange)
                            Text(firstPin.title)
                                .font(.caption)
                                .lineLimit(1)
                        }
                        Spacer()
                        if pinnedList.items.count > 1 {
                            Text("+\(pinnedList.items.count - 1)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.bar)
                }
                .buttonStyle(.plain)
                Divider()
            }

            if let undo = engine.deleteUndo, undo.conversationId == conversationId {
                HStack(spacing: 10) {
                    Text("\(undo.count) tin nhắn đã xóa")
                        .font(.footnote)
                    Spacer()
                    Button("Khôi phục") { engine.undoDelete() }
                        .font(.footnote.weight(.semibold))
                    Button { engine.dismissDeleteUndo() } label: {
                        Image(systemName: "xmark")
                            .font(.caption)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(ZaloTheme.blueTonal)
            }

            if let cardNotice = CardActionCenter.shared.notice,
               cardNotice.conversation == nil || cardNotice.conversation == conversationId {
                Text(cardNotice.text)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.75), in: Capsule())
                    .padding(.vertical, 4)
            }
        }
    }

    private func daySeparator(_ date: Date) -> some View {
        Text(Self.dayFormatter.string(from: date))
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color(.tertiarySystemFill), in: Capsule())
            .padding(.vertical, 6)
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "vi_VN")
        f.dateFormat = "dd/MM/yyyy"
        return f
    }()
}

struct ReactionDetailRequest: Identifiable {
    let conversationId: String
    let messageId: String
    var id: String { "\(conversationId)|\(messageId)" }
}
