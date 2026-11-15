import SwiftUI

struct MobileProfileSheet: View {
    let engine: ZaloEngine
    let request: ProfileRequest

    @Environment(\.dismiss) private var dismiss
    @State private var profile: ContactProfile?
    @State private var friendPrep: FriendRequestPrep?
    @State private var friendMessage = ""
    @State private var showFriendComposer = false
    @State private var busy = false
    @State private var feedbackText: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        MobileAvatarView(
                            url: profile?.avatar ?? request.avatar,
                            name: displayName,
                            size: 64
                        )
                        VStack(alignment: .leading, spacing: 4) {
                            Text(displayName)
                                .font(.title3.weight(.semibold))
                            if let zaloName = profile?.zaloName, !zaloName.isEmpty, zaloName != displayName {
                                Text("Tên Zalo: \(zaloName)")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            if !request.phone.isEmpty {
                                Text(request.phone)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 6)

                    if let bio = profile?.bio, !bio.isEmpty {
                        Text(bio)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                if let feedbackText {
                    Section {
                        Text(feedbackText)
                            .font(.footnote)
                            .foregroundStyle(ZaloTheme.blue)
                    }
                }

                Section {
                    if profile?.isSelf != true {
                        Button {
                            let targetId = request.uid
                            dismiss()
                            engine.navigationRequest = targetId
                        } label: {
                            Label("Nhắn tin", systemImage: "bubble.left.fill")
                        }

                        if !(profile?.isOfficialAccount ?? request.isOfficialAccount),
                           let prep = friendPrep, prep.state == .ready || showFriendComposer {
                            if showFriendComposer {
                                VStack(alignment: .leading, spacing: 10) {
                                    TextField("Lời mời kết bạn", text: $friendMessage, axis: .vertical)
                                        .lineLimit(2...4)
                                    Button(busy ? "Đang gửi..." : "Gửi lời mời kết bạn") {
                                        sendFriendRequest()
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(busy)
                                }
                                .padding(.vertical, 4)
                            } else {
                                Button {
                                    showFriendComposer = true
                                } label: {
                                    Label("Kết bạn", systemImage: "person.badge.plus")
                                }
                            }
                        } else if let prep = friendPrep {
                            switch prep.state {
                            case .requested:
                                Label("Đã gửi lời mời kết bạn", systemImage: "checkmark.circle")
                                    .foregroundStyle(.secondary)
                            case .requesting:
                                Label("Người này đã gửi lời mời kết bạn", systemImage: "person.crop.circle.badge.questionmark")
                                    .foregroundStyle(.secondary)
                            case .friend:
                                Label("Đã là bạn bè", systemImage: "person.2.fill")
                                    .foregroundStyle(.secondary)
                            default:
                                EmptyView()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Hồ sơ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
            }
        }
        .task(id: request.id) {
            profile = await engine.contactProfile(request.uid)
            let prep = await engine.prepareFriendRequest(to: request.uid, from: request.conversationId, via: request.origin)
            friendPrep = prep
            friendMessage = prep.defaultMessage
            if request.startWithFriendRequest && prep.state == .ready {
                showFriendComposer = true
            }
        }
    }

    private var displayName: String {
        if let name = profile?.name, !name.isEmpty { return name }
        if !request.name.isEmpty { return request.name }
        return "Người dùng Zalo"
    }

    private func sendFriendRequest() {
        busy = true
        Task {
            let trimmed = String(friendMessage.prefix(friendPrep?.maxMessage ?? 150))
            let result = await engine.submitFriendRequest(to: request.uid, message: trimmed)
            busy = false
            feedbackText = result.text
            if result.ok || result.pending {
                showFriendComposer = false
            }
        }
    }
}

struct MobileAliasSheet: View {
    let engine: ZaloEngine
    let request: AliasRequest

    @Environment(\.dismiss) private var dismiss
    @State private var aliasText: String
    @State private var busy = false
    @State private var errorText: String?

    init(engine: ZaloEngine, request: AliasRequest) {
        self.engine = engine
        self.request = request
        _aliasText = State(initialValue: request.draft.suggest)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Tên gợi nhớ cho \(request.draft.name)") {
                    TextField(request.draft.placeholder.isEmpty ? "Nhập tên gợi nhớ" : request.draft.placeholder, text: $aliasText)
                        .onChange(of: aliasText) { _, val in
                            let clean = AliasDraft.sanitized(val)
                            if clean != val { aliasText = clean }
                        }
                }
                if let errorText {
                    Section {
                        Text(errorText).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Đặt tên gợi nhớ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Hủy") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(busy ? "Đang lưu..." : "Lưu") {
                        busy = true
                        Task {
                            let res = await engine.saveAlias(uid: request.draft.uid, name: String(aliasText.prefix(request.draft.max)))
                            busy = false
                            if res.ok {
                                dismiss()
                            } else {
                                errorText = res.text
                            }
                        }
                    }
                    .disabled(busy)
                }
            }
        }
    }
}

struct MobileGroupInviteSheet: View {
    let engine: ZaloEngine
    let request: GroupInviteRequest

    @Environment(\.dismiss) private var dismiss
    @State private var preview: GroupInvitePreview?
    @State private var loading = true
    @State private var busy = false
    @State private var joinNotice: String?

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView("Đang đọc thông tin nhóm...")
                } else if let preview {
                    switch preview.state {
                    case .member:
                        VStack(spacing: 16) {
                            Image(systemName: "person.3.fill")
                                .font(.largeTitle)
                                .foregroundStyle(ZaloTheme.blue)
                            Text("Bạn đã là thành viên của nhóm này")
                                .font(.headline)
                            Button("Mở cuộc trò chuyện") {
                                let id = preview.groupId
                                dismiss()
                                engine.navigationRequest = id
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding()

                    case .preview:
                        List {
                            Section {
                                HStack(spacing: 14) {
                                    MobileAvatarView(url: preview.avatar, name: preview.name, size: 58, isGroup: true)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(preview.name).font(.headline)
                                        Text("\(preview.totalMember) thành viên")
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                if !preview.desc.isEmpty {
                                    Text(preview.desc)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            if let joinNotice {
                                Section {
                                    Text(joinNotice).foregroundStyle(.orange)
                                }
                            }
                            Section {
                                Button(busy ? "Đang tham gia..." : "Tham gia nhóm") {
                                    join()
                                }
                                .buttonStyle(.borderedProminent)
                                .frame(maxWidth: .infinity)
                                .disabled(busy)
                            }
                        }

                    case .error:
                        ContentUnavailableView(
                            "Không mở được liên kết nhóm",
                            systemImage: "exclamationmark.triangle",
                            description: Text(preview.text)
                        )
                    }
                }
            }
            .navigationTitle("Lời mời vào nhóm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Đóng") { dismiss() } }
            }
        }
        .task(id: request.id) {
            preview = await engine.groupInvitePreview(request.url)
            loading = false
        }
    }

    private func join() {
        busy = true
        Task {
            let result = await engine.joinGroup(request.url)
            busy = false
            switch result.state {
            case .joined, .already:
                dismiss()
                engine.navigationRequest = result.groupId
            case .pending, .error:
                joinNotice = result.text
            }
        }
    }
}

struct MobileStickerCategorySheet: View {
    let engine: ZaloEngine
    let request: StickerCategoryRequest

    @Environment(\.dismiss) private var dismiss
    @State private var category: StickerCategory?
    @State private var loading = true

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView("Đang tải bộ sticker...")
                } else if let category {
                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 12) {
                            ForEach(category.stickers) { item in
                                Button {
                                    Task {
                                        _ = await engine.sendCategorySticker(
                                            in: request.conversationId,
                                            category: category.id,
                                            sticker: item.stickerId
                                        )
                                        dismiss()
                                    }
                                } label: {
                                    MobileAsyncPhotoView(url: item.url, maxPixelSize: 220, contentMode: .fit)
                                        .frame(width: 72, height: 72)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding()
                    }
                } else {
                    ContentUnavailableView("Không tải được bộ sticker", systemImage: "face.smiling")
                }
            }
            .navigationTitle(category?.name ?? "Bộ sticker")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Đóng") { dismiss() } }
            }
        }
        .task(id: request.id) {
            category = await engine.stickerCategory(request.cateId)
            loading = false
        }
    }
}

struct MobileReminderDetailSheet: View {
    let engine: ZaloEngine
    let request: ReminderRequest

    @Environment(\.dismiss) private var dismiss
    @State private var snapshot: ReminderSnapshot?
    @State private var responders: ReminderResponders?
    @State private var loading = true
    @State private var busy = false

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView("Đang tải nhắc hẹn...")
                } else {
                    List {
                        if let snapshot {
                            Section("Nhắc hẹn") {
                                Text(snapshot.title.isEmpty ? "Nhắc hẹn" : snapshot.title)
                                    .font(.headline)
                                if let start = snapshot.start {
                                    Label(start.formatted(date: .complete, time: .shortened), systemImage: "calendar")
                                        .font(.subheadline)
                                }
                                if !snapshot.repeatLabel.isEmpty {
                                    Label(snapshot.repeatLabel, systemImage: "repeat")
                                        .font(.subheadline)
                                }
                                if !snapshot.creatorName.isEmpty {
                                    Label("Người tạo: \(snapshot.creatorName)", systemImage: "person")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            if snapshot.canRsvp && !snapshot.deleted {
                                Section {
                                    HStack(spacing: 12) {
                                        Button("Tham gia") { rsvp(accept: true) }
                                            .buttonStyle(.borderedProminent)
                                            .disabled(busy)
                                        Button("Từ chối") { rsvp(accept: false) }
                                            .buttonStyle(.bordered)
                                            .disabled(busy)
                                    }
                                }
                            }
                        }

                        if let responders {
                            if !responders.accept.isEmpty {
                                Section("Tham gia (\(responders.acceptTotal))") {
                                    ForEach(responders.accept) { p in
                                        HStack(spacing: 10) {
                                            MobileAvatarView(url: p.avatar, name: p.name, size: 32)
                                            Text(p.isMe ? "Bạn" : p.name)
                                        }
                                    }
                                }
                            }
                            if !responders.reject.isEmpty {
                                Section("Từ chối (\(responders.rejectTotal))") {
                                    ForEach(responders.reject) { p in
                                        HStack(spacing: 10) {
                                            MobileAvatarView(url: p.avatar, name: p.name, size: 32)
                                            Text(p.isMe ? "Bạn" : p.name)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Chi tiết nhắc hẹn")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Đóng") { dismiss() } }
            }
        }
        .task(id: request.id) {
            snapshot = await engine.reminderWatch(in: request.conversationId, message: request.messageId, signature: "")
            responders = await engine.reminderResponders(in: request.conversationId, message: request.messageId)
            loading = false
        }
    }

    private func rsvp(accept: Bool) {
        busy = true
        Task {
            let res = await engine.respondToReminder(in: request.conversationId, message: request.messageId, accept: accept)
            busy = false
            if let snap = res.snapshot { snapshot = snap }
            responders = await engine.reminderResponders(in: request.conversationId, message: request.messageId)
        }
    }
}

struct MobilePollDetailSheet: View {
    @Bindable var engine: ZaloEngine
    let request: PollRequest

    @Environment(\.dismiss) private var dismiss
    @State private var draft: PollVoteDraft?
    @State private var pinState = PollPinState()
    @State private var voters: PollVoters?
    @State private var busy = false
    @State private var notice: String?

    private var detail: PollDetail? {
        engine.polls.details[request.pollId]
    }

    var body: some View {
        NavigationStack {
            Group {
                if let detail {
                    List {
                        Section {
                            Text(detail.question)
                                .font(.headline)
                            Text("\(detail.voterCount) người bình chọn · \(detail.closed ? "Đã khóa" : "Đang mở")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let notice {
                            Section {
                                Text(notice).foregroundStyle(.red).font(.caption)
                            }
                        }

                        Section("Phương án") {
                            let activeDraft = draft ?? PollVoteDraft(detail)
                            ForEach(detail.options) { option in
                                let ticked = activeDraft.selected.contains(option.id)
                                Button {
                                    guard !detail.isVotingLocked() else { return }
                                    var next = activeDraft
                                    next.toggle(option.id)
                                    draft = next
                                } label: {
                                    HStack {
                                        Image(systemName: ticked ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(ticked ? ZaloTheme.blue : .secondary)
                                        Text(option.content)
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        if !detail.resultsHidden {
                                            Text("\(option.votes)")
                                                .font(.footnote.monospacedDigit())
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }

                            if !detail.isVotingLocked() && detail.allowAdd {
                                ForEach(activeDraft.added) { added in
                                    HStack {
                                        TextField("Phương án mới...", text: Binding(
                                            get: { added.text },
                                            set: { val in
                                                var next = draft ?? PollVoteDraft(detail)
                                                if let idx = next.added.firstIndex(where: { $0.id == added.id }) {
                                                    next.added[idx].text = val
                                                    next.added[idx].voted = true
                                                    draft = next
                                                }
                                            }
                                        ))
                                    }
                                }
                                Button("Thêm phương án") {
                                    var next = activeDraft
                                    next.addRow()
                                    draft = next
                                }
                            }
                        }

                        if !detail.isVotingLocked(), let d = draft, d.canSubmit, !d.hasDuplicates(in: detail) {
                            Section {
                                Button(busy ? "Đang gửi..." : "Bình chọn") {
                                    submitVote(detail: detail, draft: d)
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(busy)
                            }
                        }

                        Section("Thao tác") {
                            Button("Chia sẻ vào nhóm") {
                                Task {
                                    let res = await engine.sharePoll(detail.id, in: request.conversationId)
                                    notice = res.ok ? nil : res.message(for: .share)
                                }
                            }
                            if pinState.offersPin {
                                Button(pinState.pinned ? "Bỏ ghim bình chọn" : "Ghim bình chọn") {
                                    togglePin(detail: detail)
                                }
                            }
                            if detail.canClose && !detail.closed {
                                Button("Khóa bình chọn", role: .destructive) {
                                    Task {
                                        let res = await engine.lockPoll(detail.id, in: request.conversationId)
                                        notice = res.ok ? nil : res.message(for: .lock)
                                    }
                                }
                            }
                        }

                        if let voters, !voters.restricted, !voters.groups.isEmpty {
                            Section("Chi tiết người chọn") {
                                ForEach(voters.groups) { grp in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("\(grp.content) (\(grp.votes))")
                                            .font(.caption.weight(.semibold))
                                        Text(grp.users.map { $0.isMe ? "Bạn" : $0.name }.joined(separator: ", "))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                } else {
                    ProgressView("Đang tải bình chọn...")
                }
            }
            .navigationTitle("Bình chọn")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Đóng") { dismiss() } }
            }
        }
        .task(id: request.id) {
            engine.watchPoll(request.pollId, in: request.conversationId)
            engine.refreshPoll(request.pollId)
            pinState = await engine.refreshPollPin(request.pollId, in: request.conversationId)
            voters = await engine.pollVoters(request.pollId)
        }
        .onChange(of: detail) { _, updated in
            if let updated, draft == nil {
                draft = PollVoteDraft(updated)
            }
        }
    }

    private func submitVote(detail: PollDetail, draft: PollVoteDraft) {
        busy = true
        Task {
            let res = await engine.votePoll(detail.id, in: request.conversationId, draft: draft, detail: detail)
            busy = false
            if res.ok {
                self.draft = nil
                voters = await engine.pollVoters(detail.id)
            } else {
                notice = res.message(for: .vote)
            }
        }
    }

    private func togglePin(detail: PollDetail) {
        Task {
            if pinState.pinned {
                let res = await engine.unpinPoll(detail.id, in: request.conversationId)
                if res.ok { pinState.pinned = false } else { notice = res.message(for: .unpin) }
            } else {
                let outcome = await engine.pinPoll(detail.id, in: request.conversationId)
                switch outcome {
                case .done: pinState.pinned = true
                case .needsConfirmation(let confirm):
                    let nextOutcome = await engine.pinPoll(detail.id, in: request.conversationId, confirming: confirm.ref)
                    if case .done = nextOutcome { pinState.pinned = true }
                case .failed(let res): notice = res.message(for: .pin)
                }
            }
        }
    }
}

struct MobileForwardSheet: View {
    let engine: ZaloEngine
    let request: ForwardRequest

    @Environment(\.dismiss) private var dismiss
    @State private var selectedIds: Set<String> = []
    @State private var searchText = ""
    @State private var busy = false

    private var targets: [ZaloEngine.ConversationSummary] {
        let base = engine.visibleConversations
        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return base }
        return base.filter { $0.displayName.localizedCaseInsensitiveContains(needle) }
    }

    var body: some View {
        NavigationStack {
            List(targets) { conv in
                let checked = selectedIds.contains(conv.id)
                Button {
                    if checked { selectedIds.remove(conv.id) } else { selectedIds.insert(conv.id) }
                } label: {
                    HStack(spacing: 12) {
                        MobileAvatarView(url: conv.avatar, name: conv.displayName, size: 40, isGroup: conv.isGroup)
                        Text(conv.displayName)
                        Spacer()
                        Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(checked ? ZaloTheme.blue : .secondary)
                    }
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .searchable(text: $searchText, prompt: "Tìm cuộc trò chuyện")
            .navigationTitle("Chia sẻ (\(selectedIds.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Hủy") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(busy ? "Đang gửi..." : "Gửi") {
                        busy = true
                        Task {
                            let outcome = await engine.forward(request.message, to: Array(selectedIds))
                            busy = false
                            switch outcome {
                            case .done(let text):
                                if let text { CardActionCenter.shared.show(text, in: request.conversationId) }
                                dismiss()
                            case .failed(let text), .pending(let text):
                                CardActionCenter.shared.show(text, in: request.conversationId)
                            case .confirm:
                                break
                            }
                        }
                    }
                    .disabled(selectedIds.isEmpty || busy)
                }
            }
        }
    }
}

struct MobileReactionDetailSheet: View {
    let engine: ZaloEngine
    let conversationId: String
    let messageId: String

    @Environment(\.dismiss) private var dismiss
    @State private var detail: ReactionDetail?
    @State private var selectedType: String?
    @State private var loading = true

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView("Đang tải...")
                } else if let detail {
                    VStack(spacing: 0) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                Button {
                                    selectedType = nil
                                } label: {
                                    Text("Tất cả \(ReactionDetail.shortCount(detail.total))")
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(selectedType == nil ? ZaloTheme.blue : Color(.tertiarySystemFill), in: Capsule())
                                        .foregroundStyle(selectedType == nil ? .white : .primary)
                                }
                                .buttonStyle(.plain)

                                ForEach(detail.tabs) { tab in
                                    Button {
                                        selectedType = tab.icon.type
                                    } label: {
                                        Text("\(tab.icon.emoji) \(ReactionDetail.shortCount(tab.total))")
                                            .font(.caption.weight(.semibold))
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(selectedType == tab.icon.type ? ZaloTheme.blue : Color(.tertiarySystemFill), in: Capsule())
                                            .foregroundStyle(selectedType == tab.icon.type ? .white : .primary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                        }
                        Divider()
                        List(detail.rows(for: selectedType)) { user in
                            HStack(spacing: 12) {
                                MobileAvatarView(url: user.avatar, name: user.name, size: 36)
                                Text(user.isMe ? "Bạn" : user.name)
                                    .font(.body)
                                Spacer()
                                HStack(spacing: 4) {
                                    ForEach(user.icons, id: \.icon.id) { entry in
                                        Text(entry.icon.emoji)
                                    }
                                }
                                if user.total > 1 {
                                    Text("\(user.total)")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .listStyle(.plain)
                    }
                } else {
                    ContentUnavailableView("Chưa có lượt cảm xúc", systemImage: "heart")
                }
            }
            .navigationTitle("Biểu cảm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Đóng") { dismiss() } }
            }
        }
        .task {
            detail = await engine.reactors(for: messageId, in: conversationId)
            loading = false
        }
    }
}
