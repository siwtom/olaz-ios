import SwiftUI

struct MobileMessageBubble: View {
    let engine: ZaloEngine
    let message: ChatMessage
    let showsSenderName: Bool
    var onReply: (ChatMessage) -> Void
    var onOpenPhoto: (URL?) -> Void
    var onOpenVideo: (URL?) -> Void
    var onShowReactions: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var cardActions: CardActions {
        CardActions(
            conversationId: message.conversationId,
            messageId: message.id,
            center: CardActionCenter.shared,
            engine: engine
        )
    }

    var body: some View {
        Group {
            if message.kind.isStandalone {
                standaloneContent
            } else {
                standardBubbleRow
            }
        }
    }

    @ViewBuilder
    private var standaloneContent: some View {
        switch message.kind {
        case .system:
            Text(message.text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .background(Color(.tertiarySystemFill).opacity(0.7), in: Capsule())
                .padding(.vertical, 4)

        case .notice(let symbol, let text):
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: symbol.isEmpty ? "info.circle.fill" : symbol)
                        .foregroundStyle(.secondary)
                    Text(text.isEmpty ? message.text : text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !message.cardButtons.isEmpty {
                    cardButtonsRow
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
            .padding(.vertical, 4)

        case .ecard(let card):
            MobileECardView(engine: engine, message: message, card: card, actions: cardActions)
                .padding(.vertical, 4)

        default:
            standardBubbleRow
        }
    }

    private var standardBubbleRow: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.isMine {
                Spacer(minLength: 48)
            } else {
                MobileAvatarView(url: message.senderAvatar, name: message.senderName, size: 30)
                    .onTapGesture {
                        if !message.senderId.isEmpty {
                            CardActionCenter.shared.profile = ProfileRequest(
                                uid: message.senderId,
                                conversationId: message.conversationId,
                                name: message.senderName,
                                avatar: message.senderAvatar
                            )
                        }
                    }
            }

            VStack(alignment: message.isMine ? .trailing : .leading, spacing: 4) {
                if showsSenderName && !message.senderName.isEmpty {
                    Text(message.senderName)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }

                bubbleContainer
                    .contextMenu {
                        messageContextMenu
                    }

                if !message.reactions.isEmpty {
                    Button {
                        onShowReactions()
                    } label: {
                        HStack(spacing: 4) {
                            ForEach(message.reactions.prefix(4)) { r in
                                HStack(spacing: 2) {
                                    Text(r.emoji)
                                        .font(.caption2)
                                    if r.count > 1 {
                                        Text("\(r.count)")
                                            .font(.caption2.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(.secondarySystemGroupedBackground), in: Capsule())
                        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
                    }
                    .buttonStyle(.plain)
                }
            }

            if !message.isMine {
                Spacer(minLength: 48)
            }
        }
    }

    private var isTransparentMedia: Bool {
        switch message.kind {
        case .sticker, .gif: true
        default: false
        }
    }

    private var bubbleBackground: Color {
        if isTransparentMedia { return .clear }
        return ZaloTheme.bubble(message.isMine, dark: colorScheme == .dark)
    }

    private var primaryTextColor: Color {
        message.isMine ? .white : .primary
    }

    private var bubbleContainer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let quote = message.quote {
                VStack(alignment: .leading, spacing: 2) {
                    Text(quote.senderName)
                        .font(.caption2.weight(.semibold))
                    Text(quote.text)
                        .font(.caption)
                        .lineLimit(2)
                        .opacity(0.85)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background((message.isMine ? Color.white : Color.primary).opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
            }

            kindBody

            if !message.cardButtons.isEmpty {
                cardButtonsRow
            }

            HStack(spacing: 4) {
                Text(Self.timeFormatter.string(from: message.date))
                    .font(.caption2)
                    .opacity(0.75)
                if message.isMine {
                    Text(statusSymbol)
                        .font(.caption2)
                        .opacity(0.8)
                }
            }
            .foregroundStyle(isTransparentMedia ? AnyShapeStyle(.secondary) : AnyShapeStyle(primaryTextColor))
        }
        .padding(isTransparentMedia ? 0 : 10)
        .background(bubbleBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private var kindBody: some View {
        switch message.kind {
        case .text:
            Text(attributedBody)
                .font(.body)
                .foregroundStyle(primaryTextColor)
                .textSelection(.enabled)

        case .photo(let url, let width, let height):
            let aspect = (width > 0 && height > 0) ? min(max(CGFloat(width) / CGFloat(height), 0.55), 1.8) : 1.0
            MobileAsyncPhotoView(url: url, maxPixelSize: 960, contentMode: .fill)
                .frame(width: min(240, 220 * max(1, aspect)), height: min(280, 220 / max(0.6, aspect)))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .onTapGesture { onOpenPhoto(url) }
            if let caption = message.caption {
                Text(caption)
                    .font(.subheadline)
                    .foregroundStyle(primaryTextColor)
            }

        case .sticker(let url), .gif(let url):
            MobileAnimatedStickerView(url: url, size: 132)
                .onTapGesture {
                    if case .gif = message.kind {
                        onOpenPhoto(url)
                    }
                }

        case .video(let thumb, let duration, let url):
            ZStack(alignment: .center) {
                MobileAsyncPhotoView(url: thumb ?? url, maxPixelSize: 800, contentMode: .fill)
                    .frame(width: 220, height: 156)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                Circle()
                    .fill(Color.black.opacity(0.55))
                    .frame(width: 44, height: 44)
                    .overlay {
                        Image(systemName: "play.fill")
                            .foregroundStyle(.white)
                    }
                if duration > 0 {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Text(String(format: "%d:%02d", duration / 60, duration % 60))
                                .font(.caption2.monospacedDigit().weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.black.opacity(0.6), in: Capsule())
                                .padding(6)
                        }
                    }
                }
            }
            .onTapGesture { onOpenVideo(url) }

        case .voice(let url, let duration):
            MobileVoiceBubblePlayer(
                engine: engine,
                conversationId: message.conversationId,
                messageId: message.id,
                url: url,
                duration: duration,
                isMine: message.isMine
            )

        case .file(let name, let size, let url):
            Button {
                openFile(url: url)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "doc.fill")
                        .font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(2)
                        Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                            .font(.caption2)
                            .opacity(0.8)
                    }
                }
                .foregroundStyle(primaryTextColor)
            }
            .buttonStyle(.plain)

        case .link(let title, let url, let thumb, let desc, let source):
            Button {
                WebLink.open(url)
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    if let thumb {
                        MobileAsyncPhotoView(url: thumb, maxPixelSize: 640, contentMode: .fill)
                            .frame(maxWidth: 230, maxHeight: 130)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    Text(title.isEmpty ? (url?.absoluteString ?? message.text) : title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                    if !desc.isEmpty {
                        Text(desc)
                            .font(.caption)
                            .opacity(0.85)
                            .lineLimit(2)
                    }
                    if !source.isEmpty {
                        Text(source)
                            .font(.caption2)
                            .opacity(0.7)
                    }
                }
                .foregroundStyle(primaryTextColor)
            }
            .buttonStyle(.plain)

        case .contactCard(let card):
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    MobileAvatarView(url: card.avatar, name: card.name, size: 42)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(card.name)
                            .font(.subheadline.weight(.semibold))
                        if !card.phone.isEmpty {
                            Text(card.phone)
                                .font(.caption)
                                .opacity(0.8)
                        }
                    }
                }
                HStack(spacing: 8) {
                    if !card.uid.isEmpty {
                        Button("Xem hồ sơ") {
                            cardActions.showProfile(ProfileRequest(
                                uid: card.uid,
                                conversationId: message.conversationId,
                                name: card.name,
                                avatar: card.avatar,
                                phone: card.phone,
                                isOfficialAccount: card.isOfficialAccount,
                                origin: .card
                            ))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    } else if let oa = URL(string: card.oaLink), WebLink.sanitized(oa) != nil {
                        Button("Mở liên kết") { cardActions.openLink(oa) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
            }
            .foregroundStyle(primaryTextColor)

        case .location(let loc):
            Button {
                WebLink.open(loc.mapURL)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    if let thumb = loc.thumbnail {
                        MobileAsyncPhotoView(url: thumb, maxPixelSize: 640, contentMode: .fill)
                            .frame(width: 220, height: 110)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    Label(loc.title.isEmpty ? "Vị trí" : loc.title, systemImage: "mappin.and.ellipse")
                        .font(.subheadline.weight(.semibold))
                    if !loc.address.isEmpty {
                        Text(loc.address)
                            .font(.caption)
                            .opacity(0.85)
                    }
                }
                .foregroundStyle(primaryTextColor)
            }
            .buttonStyle(.plain)

        case .call(let video, let missed, let duration, let title, let detail):
            HStack(spacing: 8) {
                Image(systemName: video ? "video.fill" : "phone.fill")
                    .foregroundStyle(missed ? .red : primaryTextColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title.isEmpty ? (missed ? "Cuộc gọi nhỡ" : (video ? "Cuộc gọi video" : "Cuộc gọi thoại")) : title)
                        .font(.subheadline.weight(.medium))
                    if !detail.isEmpty {
                        Text(detail)
                            .font(.caption)
                            .opacity(0.8)
                    } else if duration > 0 {
                        Text("\(duration / 60)m \(duration % 60)s")
                            .font(.caption)
                            .opacity(0.8)
                    }
                }
            }
            .foregroundStyle(primaryTextColor)

        case .poll(let pollInfo):
            MobilePollCardView(engine: engine, message: message, info: pollInfo)

        case .oaMessage(let parts):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                    Button {
                        cardActions.openLink(part.url)
                    } label: {
                        HStack(spacing: 8) {
                            if let thumb = part.thumb {
                                MobileAsyncPhotoView(url: thumb, maxPixelSize: 240, contentMode: .fill)
                                    .frame(width: part.isHeader ? 54 : 40, height: part.isHeader ? 54 : 40)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(part.title)
                                    .font(part.isHeader ? .subheadline.weight(.semibold) : .footnote.weight(.medium))
                                    .multilineTextAlignment(.leading)
                                if !part.description.isEmpty {
                                    Text(part.description)
                                        .font(.caption)
                                        .opacity(0.8)
                                        .lineLimit(2)
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .foregroundStyle(primaryTextColor)

        case .stickerSet(let title, let thumb):
            HStack(spacing: 8) {
                if let thumb {
                    MobileAsyncPhotoView(url: thumb, maxPixelSize: 240, contentMode: .fit)
                        .frame(width: 48, height: 48)
                }
                Text(title.isEmpty ? "Bộ sticker" : title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(primaryTextColor)
            }

        case .zinstant(let title, let body, let thumb):
            VStack(alignment: .leading, spacing: 4) {
                if let thumb {
                    MobileAsyncPhotoView(url: thumb, maxPixelSize: 480, contentMode: .fill)
                        .frame(width: 210, height: 100)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                if !title.isEmpty { Text(title).font(.subheadline.weight(.semibold)) }
                if !body.isEmpty { Text(body).font(.caption) }
            }
            .foregroundStyle(primaryTextColor)

        case .placeholder(let symbol, let text):
            Label(text, systemImage: symbol.isEmpty ? "lock.shield" : symbol)
                .font(.caption)
                .foregroundStyle(primaryTextColor.opacity(0.85))

        case .recalled:
            Text("Tin nhắn đã được thu hồi")
                .font(.subheadline.italic())
                .foregroundStyle(primaryTextColor.opacity(0.75))

        case .unsupported:
            Text(message.text.isEmpty ? "[Tin nhắn chưa hỗ trợ]" : message.text)
                .font(.subheadline)
                .foregroundStyle(primaryTextColor.opacity(0.85))

        case .system, .notice, .ecard:
            Text(message.text)
                .font(.subheadline)
                .foregroundStyle(primaryTextColor)
        }
    }

    private var cardButtonsRow: some View {
        HStack(spacing: 8) {
            ForEach(message.cardButtons) { button in
                Button(button.label) {
                    cardActions.run(button.ref)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!button.enabled || cardActions.isBusy(button.ref))
            }
        }
    }

    @ViewBuilder
    private var messageContextMenu: some View {
        Section {
            ForEach(["❤️", "👍", "😆", "😮", "😢", "😡"], id: \.self) { emoji in
                Button("Thả \(emoji)") {
                    engine.react(emoji, to: message.id, in: message.conversationId)
                }
            }
        }

        Button {
            onReply(message)
        } label: {
            Label("Trả lời", systemImage: "arrowshape.turn.up.left")
        }

        if let text = message.copyableText {
            Button {
                engine.copyText(text, in: message.conversationId)
            } label: {
                Label("Sao chép tin nhắn", systemImage: "doc.on.doc")
            }
        }

        if case .photo = message.kind {
            Button {
                engine.copyPhoto(message)
            } label: {
                Label("Sao chép ảnh", systemImage: "photo.on.rectangle")
            }
        }

        if message.menu.forward != .hidden {
            Button {
                engine.requestForward(message)
            } label: {
                Label("Chia sẻ", systemImage: "arrowshape.turn.up.right")
            }
        }

        if message.menu.pin {
            Button {
                if message.menu.pinned {
                    engine.requestUnpin(message)
                } else {
                    engine.pin(message)
                }
            } label: {
                Label(message.menu.pinned ? "Bỏ ghim tin nhắn" : "Ghim tin nhắn", systemImage: message.menu.pinned ? "pin.slash" : "pin")
            }
        }

        if let star = message.menu.star {
            Button {
                engine.setStarred(message, star == .star)
            } label: {
                Label(star == .unstar ? "Bỏ đánh dấu" : "Đánh dấu tin nhắn", systemImage: star == .unstar ? "star.slash" : "star")
            }
        }

        if message.menu.recall {
            Button(role: .destructive) {
                engine.recall(message)
            } label: {
                Label("Thu hồi", systemImage: "arrow.uturn.backward")
            }
        }

        if let del = message.menu.delete {
            Button(role: .destructive) {
                engine.deleteForMe(message)
            } label: {
                Label(del == .plain ? "Xóa" : "Xóa chỉ ở phía tôi", systemImage: "trash")
            }
        }
    }

    private func openFile(url: URL?) {
        guard let url else {
            CardActionCenter.shared.show("Tệp không còn đường dẫn tải.", in: message.conversationId)
            return
        }
        Task {
            do {
                let localURL = try await MediaLoader.shared.localFile(for: url)
                NotificationCenter.default.post(name: .olazShareFileRequested, object: localURL)
            } catch {
                WebLink.open(url)
            }
        }
    }

    private var attributedBody: AttributedString {
        var attributed = AttributedString(message.text)
        let utf16 = message.text.utf16
        for mention in message.mentions {
            guard mention.pos >= 0, mention.len > 0, mention.pos + mention.len <= utf16.count else { continue }
            let start = utf16.index(utf16.startIndex, offsetBy: mention.pos)
            let end = utf16.index(start, offsetBy: mention.len)
            if let range = Range<AttributedString.Index>(NSRange(start..<end, in: message.text), in: attributed) {
                attributed[range].font = .body.weight(.semibold)
            }
        }
        return attributed
    }

    private var statusSymbol: String {
        switch message.status {
        case .sending: "…"
        case .sent: "✓"
        case .delivered, .seen: "✓✓"
        case .failed: "!"
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
}

private struct MobileECardView: View {
    let engine: ZaloEngine
    let message: ChatMessage
    let card: ChatMessage.ECard
    let actions: CardActions

    @State private var reminder: ReminderSnapshot?
    @State private var suggested: [SuggestedSticker] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if card.style == .reminder {
                let title = reminder?.title.isEmpty == false ? (reminder?.title ?? card.title) : card.title
                HStack(spacing: 8) {
                    Image(systemName: "bell.badge.fill")
                        .foregroundStyle(.orange)
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                }
                if let start = reminder?.start ?? card.reminderStart {
                    Text(start.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let summary = reminder?.responderSummary {
                    Button(summary) {
                        actions.showReminder(openList: true)
                    }
                    .font(.caption)
                }
                if let snap = reminder, snap.showsRsvpButtons {
                    HStack(spacing: 8) {
                        Button("Tham gia") {
                            actions.respond(accept: true, reminder: snap.id)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(actions.isRsvpBusy(snap.id))
                        Button("Từ chối") {
                            actions.respond(accept: false, reminder: snap.id)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(actions.isRsvpBusy(snap.id))
                    }
                } else {
                    Button("Xem chi tiết") { actions.showReminder() }
                        .font(.caption.weight(.medium))
                }
            } else {
                if let img = card.image ?? card.thumb {
                    MobileAsyncPhotoView(url: img, maxPixelSize: 600, contentMode: .fill)
                        .frame(maxWidth: 280, maxHeight: 140)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                if !card.title.isEmpty {
                    Text(card.title).font(.subheadline.weight(.semibold))
                }
                if !card.description.isEmpty {
                    Text(card.description).font(.caption).foregroundStyle(.secondary)
                }
                if !message.cardButtons.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(message.cardButtons) { b in
                            Button(b.label) { actions.run(b.ref) }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(!b.enabled || actions.isBusy(b.ref))
                        }
                    }
                }
            }

            if !suggested.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggested) { item in
                            Button {
                                actions.run(item.ref)
                            } label: {
                                MobileAsyncPhotoView(url: item.url, maxPixelSize: 200, contentMode: .fit)
                                    .frame(width: 56, height: 56)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: 300, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .task(id: message.id) {
            if card.style == .reminder {
                reminder = await engine.reminderWatch(in: message.conversationId, message: message.id, signature: "")
            }
            if message.suggestsStickers {
                suggested = await engine.suggestedStickers(in: message.conversationId, message: message.id)
            }
        }
    }
}

private struct MobilePollCardView: View {
    @Bindable var engine: ZaloEngine
    let message: ChatMessage
    let info: ChatMessage.PollInfo

    private var pollId: String { info.pollId }
    private var detail: PollDetail? { engine.polls.details[pollId] }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "chart.bar.doc.horizontal")
                    .foregroundStyle(ZaloTheme.blue)
                Text(detail?.question ?? info.question)
                    .font(.subheadline.weight(.semibold))
            }

            if let detail {
                ForEach(detail.options.prefix(3)) { option in
                    HStack {
                        Image(systemName: option.voted ? "checkmark.circle.fill" : "circle")
                            .font(.caption)
                            .foregroundStyle(option.voted ? ZaloTheme.blue : .secondary)
                        Text(option.content)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                        if !detail.resultsHidden {
                            Text("\(option.votes)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if detail.options.count > 3 {
                    Text("Còn \(detail.options.count - 3) lựa chọn khác")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else if engine.polls.failed.contains(pollId) {
                Button("Tải lại bình chọn") {
                    engine.retryPoll(pollId, in: message.conversationId)
                }
                .font(.caption)
            }

            Button("Xem bình chọn") {
                CardActionCenter.shared.poll = PollRequest(conversationId: message.conversationId, pollId: pollId)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(4)
        .task(id: pollId) {
            engine.watchPoll(pollId, in: message.conversationId)
        }
    }
}
