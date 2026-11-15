import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct MobileComposerBar: View {
    @Bindable var engine: ZaloEngine
    let conversationId: String
    let isGroup: Bool
    @Binding var replyTo: ChatMessage?

    @State private var text = ""
    @State private var mentions: [Mention] = []
    @State private var mentionCandidates: [MentionCandidate] = []
    @State private var activeMentionRange: NSRange?
    @State private var typingStickers = TypingStickerState()
    @State private var stickerDebounceTask: Task<Void, Never>?

    @State private var pickedPhotos: [PhotosPickerItem] = []
    @State private var showFileImporter = false
    @State private var showStickerSheet = false
    @State private var showPollCreate = false
    @State private var showReminderCreate = false
    @State private var showMyCardSheet = false
    @State private var sendingMedia = false

    @State private var pollCapabilities = PollCapabilities()
    @State private var reminderInfo: ReminderComposeInfo?

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            if let replyTo {
                HStack(spacing: 10) {
                    Rectangle()
                        .fill(ZaloTheme.blue)
                        .frame(width: 3, height: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Trả lời \(replyTo.senderName)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ZaloTheme.blue)
                        Text(replyTo.text)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button {
                        self.replyTo = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.bar)
                Divider()
            }

            if !mentionCandidates.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(mentionCandidates) { candidate in
                            Button {
                                insertMention(candidate)
                            } label: {
                                HStack(spacing: 6) {
                                    MobileAvatarView(url: candidate.avatar, name: candidate.name, size: 22)
                                    Text(candidate.isAll ? "Cả nhóm (@All)" : candidate.name)
                                        .font(.caption.weight(.medium))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color(.tertiarySystemFill), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                .background(.bar)
                Divider()
            }

            if typingStickers.isVisible(draft: text, mentionListOpen: !mentionCandidates.isEmpty, settingEnabled: StickerSuggestState.shared.setting?.enabled) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(typingStickers.stickers.enumerated()), id: \.element.id) { index, sticker in
                            Button {
                                let taken = typingStickers.take(ComposerDraft(text: text, mentions: mentions, replyTo: replyTo))
                                text = ""
                                mentions = []
                                replyTo = nil
                                Task {
                                    _ = await engine.sendSticker(sticker, in: conversationId, source: .suggestion, typed: taken.typed, index: index)
                                }
                            } label: {
                                MobileAnimatedStickerView(url: sticker.url, size: 54)
                            }
                            .buttonStyle(.plain)
                        }
                        Button {
                            typingStickers.dismissed = true
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                .background(.bar)
                Divider()
            }

            HStack(alignment: .bottom, spacing: 8) {
                Menu {
                    Button {
                        showFileImporter = true
                    } label: {
                        Label("Gửi tệp", systemImage: "doc")
                    }
                    if isGroup && pollCapabilities.ready && pollCapabilities.canCreate {
                        Button {
                            showPollCreate = true
                        } label: {
                            Label("Tạo bình chọn", systemImage: "chart.bar")
                        }
                    }
                    if reminderInfo?.hidden != true {
                        Button {
                            showReminderCreate = true
                        } label: {
                            Label("Tạo nhắc hẹn", systemImage: "bell.badge")
                        }
                    }
                    Button {
                        showMyCardSheet = true
                    } label: {
                        Label("Gửi danh thiếp", systemImage: "person.text.rectangle")
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 5)

                let isSendingMedia = sendingMedia
                PhotosPicker(selection: $pickedPhotos, maxSelectionCount: 9, matching: .any(of: [.images, .videos])) {
                    if isSendingMedia {
                        ProgressView()
                            .frame(width: 26, height: 26)
                    } else {
                        Image(systemName: "photo")
                            .font(.system(size: 22))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.bottom, 6)

                Button {
                    showStickerSheet = true
                } label: {
                    Image(systemName: "face.smiling")
                        .font(.system(size: 22))
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 6)

                TextField("Tin nhắn...", text: $text, axis: .vertical)
                    .lineLimit(1...5)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .onChange(of: text) { _, newValue in
                        handleDraftChanged(newValue)
                    }

                Button {
                    sendCurrentText()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(canSend ? ZaloTheme.blue : Color(.quaternaryLabel))
                }
                .disabled(!canSend)
                .padding(.bottom, 4)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.bar)
        }
        .task(id: conversationId) {
            restoreFailedDraft()
            await StickerSuggestState.shared.loadIfNeeded(from: engine)
            if isGroup {
                pollCapabilities = await engine.pollCapabilities(in: conversationId)
            }
            reminderInfo = await engine.reminderComposeInfo(for: conversationId)
        }
        .onChange(of: engine.failedDrafts.revision) { _, _ in
            restoreFailedDraft()
        }
        .onChange(of: pickedPhotos) { _, items in
            guard !items.isEmpty else { return }
            pickedPhotos = []
            sendPickedPhotos(items)
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                sendImportedFiles(urls)
            }
        }
        .sheet(isPresented: $showStickerSheet) {
            MobileStickerPickerSheet(engine: engine, conversationId: conversationId)
        }
        .sheet(isPresented: $showPollCreate) {
            MobileCreatePollSheet(engine: engine, conversationId: conversationId, capabilities: pollCapabilities)
        }
        .sheet(isPresented: $showReminderCreate) {
            MobileCreateReminderSheet(engine: engine, conversationId: conversationId, info: reminderInfo)
        }
        .sheet(isPresented: $showMyCardSheet) {
            MobileSendMyCardSheet(engine: engine, conversationId: conversationId)
        }
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sendCurrentText() {
        let draftText = text
        let quoteId = replyTo?.id
        let draftMentions = mentions
        text = ""
        mentions = []
        replyTo = nil
        mentionCandidates = []
        typingStickers.clear()
        Task {
            let ok = await engine.sendText(draftText, to: conversationId, quoting: quoteId, mentions: draftMentions)
            if !ok {
                let recovered = ComposerDraft(text: draftText, mentions: draftMentions, replyTo: nil)
                engine.failedDrafts.stash(recovered, for: conversationId)
            }
        }
    }

    private func restoreFailedDraft() {
        guard let taken = engine.failedDrafts.takeWithNotice(for: conversationId) else { return }
        text = taken.draft.text
        mentions = taken.draft.mentions
        if let r = taken.draft.replyTo { replyTo = r }
    }

    private func handleDraftChanged(_ newValue: String) {
        updateMentions(for: newValue)
        scheduleStickerSuggest(for: newValue)
    }

    private func updateMentions(for newValue: String) {
        guard isGroup, let atIndex = newValue.lastIndex(of: "@") else {
            mentionCandidates = []
            activeMentionRange = nil
            return
        }
        let after = String(newValue[newValue.index(after: atIndex)...])
        if after.contains("\n") || after.count > 24 {
            mentionCandidates = []
            activeMentionRange = nil
            return
        }
        activeMentionRange = NSRange(atIndex..<newValue.endIndex, in: newValue)
        Task {
            let excluded = mentions.map(\.uid)
            mentionCandidates = await engine.mentionCandidates(in: conversationId, query: after, excluding: excluded)
        }
    }

    private func insertMention(_ candidate: MentionCandidate) {
        guard let nsRange = activeMentionRange else { return }
        let tag = "@\(candidate.name)"
        let nsText = text as NSString
        let replaced = nsText.replacingCharacters(in: nsRange, with: tag + " ")
        let entry = Mention(uid: candidate.id, pos: nsRange.location, len: (tag as NSString).length, isAll: candidate.isAll)
        mentions.append(entry)
        text = replaced
        mentionCandidates = []
        activeMentionRange = nil
    }

    private func scheduleStickerSuggest(for value: String) {
        stickerDebounceTask?.cancel()
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, StickerSuggestState.shared.setting?.enabled != false else {
            typingStickers.clear()
            return
        }
        let delayMs = StickerSuggestState.shared.delay
        stickerDebounceTask = Task {
            try? await Task.sleep(for: .milliseconds(delayMs))
            guard !Task.isCancelled else { return }
            let list = await engine.typingStickerSuggestions(in: conversationId, text: trimmed)
            typingStickers.offer(list, for: trimmed)
        }
    }

    private func sendPickedPhotos(_ items: [PhotosPickerItem]) {
        sendingMedia = true
        Task {
            defer { sendingMedia = false }
            var urls: [URL] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    let isVideo = item.supportedContentTypes.contains { $0.conforms(to: .movie) }
                    let ext = isVideo ? "mp4" : "jpg"
                    let url = FileManager.default.temporaryDirectory.appendingPathComponent("olaz-pick-\(UUID().uuidString).\(ext)")
                    if (try? data.write(to: url)) != nil {
                        urls.append(url)
                    }
                }
            }
            guard !urls.isEmpty else { return }
            let outcome = await engine.sendMedia(urls, to: conversationId)
            engine.report(outcome, in: conversationId)
            for u in urls { try? FileManager.default.removeItem(at: u) }
        }
    }

    private func sendImportedFiles(_ picked: [URL]) {
        sendingMedia = true
        Task {
            defer { sendingMedia = false }
            var tempURLs: [URL] = []
            for url in picked {
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                let dest = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-\(url.lastPathComponent)")
                if (try? FileManager.default.copyItem(at: url, to: dest)) != nil {
                    tempURLs.append(dest)
                }
            }
            guard !tempURLs.isEmpty else { return }
            let outcome = await engine.sendFiles(tempURLs, to: conversationId)
            engine.report(outcome, in: conversationId)
            for u in tempURLs { try? FileManager.default.removeItem(at: u) }
        }
    }
}

private struct MobileStickerPickerSheet: View {
    let engine: ZaloEngine
    let conversationId: String

    @Environment(\.dismiss) private var dismiss
    @State private var tabs: [StickerTab] = []
    @State private var selectedTabId: Int?
    @State private var stickers: [StickerEntry] = []
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !tabs.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(tabs) { tab in
                                Button {
                                    selectedTabId = tab.id
                                    loadTab(tab.id)
                                } label: {
                                    Text(tab.name.isEmpty ? "Gói #\(tab.id)" : tab.name)
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(selectedTabId == tab.id ? ZaloTheme.blue : Color(.tertiarySystemFill), in: Capsule())
                                        .foregroundStyle(selectedTabId == tab.id ? .white : .primary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    }
                    Divider()
                }

                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 12) {
                        ForEach(stickers) { sticker in
                            Button {
                                Task {
                                    let source: StickerSource = !searchText.isEmpty ? .search : (selectedTabId == StickerTab.recentId ? .recent : .category)
                                    _ = await engine.sendSticker(sticker, in: conversationId, source: source)
                                    dismiss()
                                }
                            } label: {
                                MobileAsyncPhotoView(url: sticker.url, maxPixelSize: 220, contentMode: .fit)
                                    .frame(width: 72, height: 72)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Sticker")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Tìm sticker")
            .onSubmit(of: .search) {
                Task {
                    if let hits = await engine.searchStickers(searchText) { stickers = hits }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Đóng") { dismiss() } }
            }
            .task {
                tabs = await engine.stickerTabs() ?? []
                if let first = tabs.first {
                    selectedTabId = first.id
                    loadTab(first.id)
                }
            }
        }
    }

    private func loadTab(_ id: Int) {
        Task {
            stickers = await engine.stickers(inTab: id) ?? []
        }
    }
}

private struct MobileCreatePollSheet: View {
    let engine: ZaloEngine
    let conversationId: String
    let capabilities: PollCapabilities

    @Environment(\.dismiss) private var dismiss
    @State private var draft = PollCreateDraft()
    @State private var errorText: String?
    @State private var busy = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Câu hỏi bình chọn") {
                    TextField("Đặt câu hỏi...", text: $draft.question, axis: .vertical)
                }
                Section("Các lựa chọn") {
                    ForEach(draft.options.indices, id: \.self) { index in
                        TextField("Lựa chọn \(index + 1)", text: $draft.options[index])
                    }
                    if draft.options.count < capabilities.config.maxOptions {
                        Button("Thêm lựa chọn") { draft.options.append("") }
                    }
                }
                Section("Thiết lập") {
                    Toggle("Chọn nhiều phương án", isOn: $draft.multi)
                    Toggle("Cho phép thêm phương án", isOn: $draft.allowAdd)
                        .disabled(draft.hidePreview)
                    if capabilities.config.enableAnonymous {
                        Toggle("Bình chọn ẩn danh", isOn: $draft.anonymous)
                    }
                    if capabilities.config.enableHidePreview {
                        Toggle("Ẩn kết quả khi chưa bình chọn", isOn: $draft.hidePreview)
                    }
                    if capabilities.canPin {
                        Toggle("Ghim lên đầu trò chuyện", isOn: $draft.pin)
                    }
                }
                if let errorText {
                    Section {
                        Text(errorText).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Tạo bình chọn")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Hủy") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(busy ? "Đang tạo..." : "Tạo") {
                        createPoll()
                    }
                    .disabled(draft.issue(config: capabilities.config) != nil || busy)
                }
            }
        }
    }

    private func createPoll() {
        busy = true
        Task {
            let result = await engine.createPoll(in: conversationId, draft: draft, config: capabilities.config, canPin: capabilities.canPin)
            busy = false
            if result.ok {
                dismiss()
            } else {
                errorText = result.message(for: .create)
            }
        }
    }
}

private struct MobileCreateReminderSheet: View {
    let engine: ZaloEngine
    let conversationId: String
    let info: ReminderComposeInfo?

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var start = Date.now.addingTimeInterval(3600)
    @State private var repeatRule: ReminderRepeat = .none
    @State private var pin = true
    @State private var busy = false

    var body: some View {
        NavigationStack {
            Form {
                if let info, !info.allowed {
                    Text(info.text.isEmpty ? "Không thể tạo nhắc hẹn trong hội thoại này." : info.text)
                        .foregroundStyle(.red)
                } else {
                    Section("Nội dung") {
                        TextField("Nhập nội dung nhắc hẹn", text: $title, axis: .vertical)
                    }
                    Section("Thời gian") {
                        DatePicker("Chọn thời gian", selection: $start, in: Date.now...)
                        Picker("Lặp lại", selection: $repeatRule) {
                            ForEach(ReminderRepeat.allCases) { rule in
                                Text(rule.title).tag(rule)
                            }
                        }
                        if info?.pinToggle == true && info?.canPin == true {
                            Toggle("Ghim nhắc hẹn", isOn: $pin)
                        }
                    }
                }
            }
            .navigationTitle("Tạo nhắc hẹn")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Hủy") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(busy ? "Đang tạo..." : "Tạo") {
                        busy = true
                        Task {
                            let res = await engine.createReminder(
                                in: conversationId,
                                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                                start: start,
                                repeat: repeatRule,
                                pin: pin && (info?.canPin ?? false)
                            )
                            busy = false
                            engine.report(res, in: conversationId)
                            if case .done = res { dismiss() }
                        }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || info?.allowed == false || busy)
                }
            }
        }
    }
}

private struct MobileSendMyCardSheet: View {
    let engine: ZaloEngine
    let conversationId: String

    @Environment(\.dismiss) private var dismiss
    @State private var card: MyCardInfo?
    @State private var withPhone = true
    @State private var loading = true
    @State private var busy = false

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView("Đang tải danh thiếp...")
                } else if let card {
                    Form {
                        Section {
                            HStack(spacing: 12) {
                                MobileAvatarView(url: card.avatar, name: card.name, size: 52)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(card.name).font(.headline)
                                    if !card.phone.isEmpty && withPhone {
                                        Text(card.phone).font(.subheadline).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        if !card.phone.isEmpty {
                            Toggle("Gửi kèm số điện thoại", isOn: $withPhone)
                        }
                    }
                } else {
                    ContentUnavailableView("Không tải được danh thiếp", systemImage: "person.text.rectangle")
                }
            }
            .navigationTitle("Gửi danh thiếp")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Hủy") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(busy ? "Đang gửi..." : "Gửi") {
                        busy = true
                        Task {
                            let res = await engine.sendMyCard(to: conversationId, withPhone: withPhone)
                            busy = false
                            engine.report(res, in: conversationId)
                            dismiss()
                        }
                    }
                    .disabled(card == nil || busy)
                }
            }
            .task {
                if let loaded = await engine.myCard() {
                    card = loaded
                    withPhone = loaded.withPhone
                }
                loading = false
            }
        }
    }
}
