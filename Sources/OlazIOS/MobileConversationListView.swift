import PhotosUI
import SwiftUI

struct MobileConversationListView: View {
    @Bindable var engine: ZaloEngine
    @Binding var groupComposeRequest: GroupComposeRequest?
    var onOpenConversation: (String) -> Void

    @State private var searchText = ""
    @State private var selectedTabFilter: ConversationTypeFilter = .all
    @State private var selectedLabelId: String?
    @State private var pinSearchMatches: [String] = []
    @State private var showCreateLabel = false
    @State private var showStrangerFolder = false

    private var summaryById: [String: ZaloEngine.ConversationSummary] {
        Dictionary(engine.conversations.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var isPinQuery: Bool {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count == 4 && trimmed.allSatisfy(\.isNumber) && engine.conversationActions.hiddenEnabled
    }

    private var filteredConversations: [ZaloEngine.ConversationSummary] {
        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !needle.isEmpty {
            let visible = engine.visibleConversations
            return visible.filter {
                $0.displayName.localizedCaseInsensitiveContains(needle)
                    || ($0.preview?.text.localizedCaseInsensitiveContains(needle) ?? false)
            }
        }

        let extras = engine.conversationExtras
        if extras.loaded, !extras.listIds.isEmpty {
            var ordered: [ZaloEngine.ConversationSummary] = []
            var seen = Set<String>()
            for id in extras.listIds where id != ConversationExtras.strangerBoxId {
                guard !engine.conversationActions.isHidden(id),
                      let item = summaryById[id],
                      seen.insert(id).inserted else { continue }
                ordered.append(item)
            }
            if !ordered.isEmpty { return ordered }
        }

        var list = engine.visibleConversations
        if selectedTabFilter == .unread {
            list = list.filter { $0.unread > 0 || engine.conversationActions.hasUnreadMark($0.id) }
        } else if selectedTabFilter == .other {
            list = list.filter { engine.conversationActions.flags(for: $0.id).contains(.archived) }
        } else if engine.conversationExtras.archivedEnabled {
            list = list.filter { !engine.conversationActions.flags(for: $0.id).contains(.archived) }
        }
        if let labelId = selectedLabelId {
            list = list.filter { engine.conversationExtras.labelByConversation[$0.id] == labelId }
        }
        return list
    }

    var body: some View {
        List {
            if !engine.conversationActions.hiddenKnown {
                Section {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Đang đồng bộ danh sách hội thoại...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }
            } else {
                filterStripSection

                if !pinSearchMatches.isEmpty {
                    Section("Trò chuyện ẩn (đã mở khóa tạm thời bằng PIN)") {
                        ForEach(pinSearchMatches, id: \.self) { id in
                            if let conv = summaryById[id] {
                                Button {
                                    if engine.unlockFromPINSearch(id) {
                                        searchText = ""
                                        pinSearchMatches = []
                                        onOpenConversation(id)
                                    }
                                } label: {
                                    conversationRow(conv, isLockedRow: true)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                if searchText.isEmpty && selectedLabelId == nil && engine.conversationExtras.strangerBox.chats > 0 && !engine.conversationExtras.unboxStranger {
                    Section {
                        Button {
                            showStrangerFolder = true
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(Color.orange.opacity(0.16))
                                        .frame(width: 48, height: 48)
                                    Image(systemName: "envelope.badge.fill")
                                        .foregroundStyle(.orange)
                                        .font(.title3)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Tin nhắn từ người lạ")
                                        .font(.body.weight(.semibold))
                                    Text("\(engine.conversationExtras.strangerBox.chats) hội thoại chưa trả lời")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if engine.conversationExtras.strangerBox.unreadChats > 0 {
                                    Text("\(engine.conversationExtras.strangerBox.unreadChats)")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background(Color.red, in: Capsule())
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section {
                    if filteredConversations.isEmpty {
                        ContentUnavailableView(
                            searchText.isEmpty ? "Chưa có hội thoại nào" : "Không tìm thấy kết quả",
                            systemImage: searchText.isEmpty ? "bubble.left.and.bubble.right" : "magnifyingglass",
                            description: Text(searchText.isEmpty ? "Các cuộc trò chuyện của bạn sẽ hiển thị tại đây." : "Thử tìm với tên hoặc từ khóa khác.")
                        )
                    } else {
                        ForEach(filteredConversations) { conv in
                            rowWithActions(conv)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Tin nhắn")
        .searchable(text: $searchText, prompt: "Tìm kiếm hoặc nhập PIN ẩn")
        .onChange(of: searchText) { _, newValue in
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count == 4 && trimmed.allSatisfy(\.isNumber) && engine.conversationActions.hiddenEnabled {
                Task {
                    pinSearchMatches = await engine.hiddenConversations(matching: trimmed) ?? []
                }
            } else {
                pinSearchMatches = []
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        groupComposeRequest = GroupComposeRequest()
                    } label: {
                        Label("Tạo nhóm mới", systemImage: "person.3.fill")
                    }
                    Button {
                        showCreateLabel = true
                    } label: {
                        Label("Tạo nhãn phân loại", systemImage: "tag.fill")
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }
            }
        }
        .onAppear {
            selectedTabFilter = engine.conversationExtras.defaultTab
        }
        .sheet(isPresented: $showCreateLabel) {
            MobileCreateLabelSheet(engine: engine)
        }
        .sheet(isPresented: $showStrangerFolder) {
            MobileStrangerFolderSheet(engine: engine, summaryById: summaryById) { id in
                showStrangerFolder = false
                onOpenConversation(id)
            }
        }
        .sheet(item: Binding(
            get: {
                if case .pinBoard(let id) = engine.conversationPrompt {
                    return MobilePromptID(id: id)
                }
                return nil
            },
            set: { if $0 == nil { engine.conversationPrompt = nil } }
        )) { prompt in
            MobilePinBoardSheet(engine: engine, targetConversationId: prompt.id, summaryById: summaryById)
        }
        .sheet(item: Binding(
            get: {
                switch engine.conversationPrompt {
                case .hide(let id): return MobileHiddenPrompt(id: id, mode: .hide)
                case .unhide(let id): return MobileHiddenPrompt(id: id, mode: .unhide)
                case .unlock(let id): return MobileHiddenPrompt(id: id, mode: .unlock)
                default: return nil
                }
            },
            set: { if $0 == nil { engine.conversationPrompt = nil } }
        )) { prompt in
            MobileHiddenChatPINSheet(engine: engine, prompt: prompt) { unlockedId in
                onOpenConversation(unlockedId)
            }
        }
        .alert(
            ConversationActionText.deleteLine1,
            isPresented: Binding(
                get: {
                    if case .delete = engine.conversationPrompt { return true }
                    return false
                },
                set: { if !$0 { engine.conversationPrompt = nil } }
            )
        ) {
            Button(ConversationActionText.deleteConfirm, role: .destructive) {
                if case .delete(let id) = engine.conversationPrompt {
                    engine.conversationPrompt = nil
                    engine.confirmDeleteConversation(id)
                }
            }
            Button(ConversationActionText.deleteCancel, role: .cancel) {
                engine.conversationPrompt = nil
            }
        } message: {
            Text(ConversationActionText.deleteLine2)
        }
    }

    private var filterStripSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(engine.conversationExtras.tabs) { tab in
                        let selected = selectedTabFilter == tab && selectedLabelId == nil
                        Button {
                            selectedTabFilter = tab
                            selectedLabelId = nil
                            engine.setConversationFilter(tab, labelIds: [])
                        } label: {
                            Text(tab.title)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(selected ? ZaloTheme.blue : Color(.tertiarySystemFill), in: Capsule())
                                .foregroundStyle(selected ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }

                    ForEach(engine.conversationExtras.labels) { label in
                        let active = selectedLabelId == label.id
                        Button {
                            if active {
                                selectedLabelId = nil
                                engine.setConversationFilter(selectedTabFilter, labelIds: [])
                            } else {
                                selectedLabelId = label.id
                                engine.setConversationFilter(selectedTabFilter, labelIds: [label.id])
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(active ? Color.white : label.color)
                                    .frame(width: 7, height: 7)
                                Text(label.name)
                                    .font(.caption.weight(.medium))
                            }
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .background(active ? label.color : label.color.opacity(0.14), in: Capsule())
                            .foregroundStyle(active ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            .listRowSeparator(.hidden)
        }
    }

    private func rowWithActions(_ conv: ZaloEngine.ConversationSummary) -> some View {
        let plan = ConversationMenuPlan.make(
            id: conv.id,
            preset: .thread,
            state: engine.conversationActions,
            unread: conv.unread,
            muted: engine.isConversationMuted(conv.id)
        )
        return Button {
            if engine.isConversationLocked(conv.id) {
                engine.conversationPrompt = .unlock(id: conv.id)
            } else {
                onOpenConversation(conv.id)
            }
        } label: {
            conversationRow(conv, isLockedRow: false)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if let readAction = plan.read {
                Button {
                    switch readAction {
                    case .markRead: engine.markConversationRead(conv.id)
                    case .markUnread: engine.markConversationUnread(conv.id)
                    }
                } label: {
                    Label(
                        readAction == .markRead ? "Đã đọc" : "Chưa đọc",
                        systemImage: readAction == .markRead ? "envelope.open.fill" : "envelope.badge.fill"
                    )
                }
                .tint(ZaloTheme.blue)
            }
            if let pinAction = plan.pin {
                Button {
                    switch pinAction {
                    case .pin: engine.pinConversation(conv.id)
                    case .unpin: engine.unpinConversation(conv.id)
                    }
                } label: {
                    Label(pinAction == .pin ? "Ghim" : "Bỏ ghim", systemImage: pinAction == .pin ? "pin.fill" : "pin.slash.fill")
                }
                .tint(.orange)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if plan.canDelete {
                Button(role: .destructive) {
                    engine.requestDeleteConversation(conv.id)
                } label: {
                    Label("Xóa", systemImage: "trash.fill")
                }
            }
            if let muteAction = plan.mute {
                Button {
                    if muteAction == .unmute {
                        engine.unmuteConversation(conv.id)
                    } else {
                        engine.muteConversation(conv.id, .fourHours)
                    }
                } label: {
                    Label(muteAction == .unmute ? "Bật TB" : "Tắt TB", systemImage: muteAction == .unmute ? "bell.fill" : "bell.slash.fill")
                }
                .tint(.indigo)
            }
        }
        .contextMenu {
            conversationContextMenu(conv, plan: plan)
        }
    }

    @ViewBuilder
    private func conversationContextMenu(_ conv: ZaloEngine.ConversationSummary, plan: ConversationMenuPlan) -> some View {
        if let pin = plan.pin {
            Button {
                if pin == .pin { engine.pinConversation(conv.id) } else { engine.unpinConversation(conv.id) }
            } label: {
                Label(pin == .pin ? "Ghim hội thoại" : "Bỏ ghim", systemImage: pin == .pin ? "pin" : "pin.slash")
            }
        }
        if let archive = plan.archive {
            Button {
                engine.moveConversation(conv.id, toOther: archive == .moveToOther)
            } label: {
                Label(archive == .moveToOther ? "Chuyển sang Khác" : "Chuyển sang Tin nhắn", systemImage: "tray.and.arrow.down")
            }
        }
        if let read = plan.read {
            Button {
                if read == .markRead { engine.markConversationRead(conv.id) } else { engine.markConversationUnread(conv.id) }
            } label: {
                Label(read == .markRead ? "Đánh dấu đã đọc" : "Đánh dấu chưa đọc", systemImage: "envelope.open")
            }
        }
        if let mute = plan.mute {
            if mute == .unmute {
                Button {
                    engine.unmuteConversation(conv.id)
                } label: {
                    Label("Bật thông báo", systemImage: "bell")
                }
            } else {
                Menu("Tắt thông báo") {
                    ForEach(MuteDuration.allCases) { duration in
                        Button(duration.title) {
                            engine.muteConversation(conv.id, duration)
                        }
                    }
                }
            }
        }
        if plan.showsLabel && !engine.conversationExtras.labels.isEmpty {
            Menu("Phân loại") {
                if engine.conversationExtras.label(of: conv.id) != nil {
                    Button("Bỏ phân loại") {
                        engine.setConversationLabel(conv.id, labelId: nil)
                    }
                }
                ForEach(engine.conversationExtras.labels) { label in
                    Button {
                        engine.setConversationLabel(conv.id, labelId: label.id)
                    } label: {
                        Label(label.name, systemImage: "tag")
                    }
                }
            }
        }
        if let hide = plan.hide {
            Button {
                engine.conversationPrompt = (hide == .hide) ? .hide(id: conv.id) : .unhide(id: conv.id)
            } label: {
                Label(hide == .hide ? "Ẩn trò chuyện" : "Hiện trò chuyện", systemImage: hide == .hide ? "eye.slash" : "eye")
            }
        }
        if plan.canDelete {
            Button(role: .destructive) {
                engine.requestDeleteConversation(conv.id)
            } label: {
                Label("Xóa hội thoại", systemImage: "trash")
            }
        }
    }

    private func conversationRow(_ conv: ZaloEngine.ConversationSummary, isLockedRow: Bool) -> some View {
        let isMuted = engine.isConversationMuted(conv.id)
        let label = engine.conversationExtras.label(of: conv.id)
        let unreadMark = engine.conversationActions.hasUnreadMark(conv.id)
        return HStack(spacing: 12) {
            MobileAvatarView(url: conv.avatar, name: conv.displayName, size: 50, isGroup: conv.isGroup)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if conv.pinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    Text(conv.displayName)
                        .font(.body.weight((conv.unread > 0 || unreadMark) ? .semibold : .regular))
                        .lineLimit(1)
                    if isLockedRow {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    if let date = conv.preview?.date {
                        Text(Self.formatTime(date))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 6) {
                    if let label {
                        Image(systemName: "tag.fill")
                            .font(.caption2)
                            .foregroundStyle(label.color)
                    }
                    Text(conv.preview.map { ($0.fromMe ? "Bạn: " : "") + $0.text } ?? " ")
                        .font(.subheadline)
                        .foregroundStyle((conv.unread > 0 || unreadMark) ? .primary : .secondary)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    if isMuted {
                        Image(systemName: "bell.slash.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if conv.unread > 0 {
                        Text(conv.unread > 99 ? "99+" : "\(conv.unread)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(isMuted ? Color.secondary : Color.red, in: Capsule())
                    } else if unreadMark {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 9, height: 9)
                    }
                }
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    private static let sameDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd/MM"
        return f
    }()

    private static func formatTime(_ date: Date) -> String {
        Calendar.current.isDateInToday(date) ? sameDayFormatter.string(from: date) : shortDateFormatter.string(from: date)
    }
}

private struct MobilePromptID: Identifiable {
    let id: String
}

private struct MobileHiddenPrompt: Identifiable {
    enum Mode { case hide, unhide, unlock }
    let id: String
    let mode: Mode
}

private struct MobilePinBoardSheet: View {
    let engine: ZaloEngine
    let targetConversationId: String
    let summaryById: [String: ZaloEngine.ConversationSummary]

    @Environment(\.dismiss) private var dismiss
    @State private var board: PinBoard?
    @State private var selectedUnpins: Set<String> = []
    @State private var loading = true
    @State private var busy = false

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView("Đang tải danh sách ghim...")
                } else if let board {
                    List {
                        Section {
                            Text("Giới hạn \(board.limit) ghim đã đầy. Chọn ít nhất \(max(1, board.need)) hội thoại để bỏ ghim và ghim hội thoại mới.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Section("Đang ghim (\(board.items.count))") {
                            ForEach(board.items, id: \.self) { id in
                                let selected = selectedUnpins.contains(id)
                                Button {
                                    if selected { selectedUnpins.remove(id) } else { selectedUnpins.insert(id) }
                                } label: {
                                    HStack {
                                        let conv = summaryById[id]
                                        MobileAvatarView(url: conv?.avatar, name: conv?.displayName ?? id, size: 36, isGroup: conv?.isGroup ?? false)
                                        Text(conv?.displayName ?? id)
                                        Spacer()
                                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(selected ? .red : .secondary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                } else {
                    ContentUnavailableView("Không đọc được danh sách ghim", systemImage: "pin.slash")
                }
            }
            .navigationTitle("Bảng ghim hội thoại")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if let board {
                        Button("Xác nhận") {
                            busy = true
                            Task {
                                _ = await engine.pinReplacing(Array(selectedUnpins), pinning: targetConversationId)
                                busy = false
                                dismiss()
                            }
                        }
                        .disabled(!board.freesSlot(removing: selectedUnpins.count) || busy)
                    }
                }
            }
        }
        .task {
            board = await engine.pinBoard(for: targetConversationId)
            loading = false
        }
    }
}

private struct MobileHiddenChatPINSheet: View {
    let engine: ZaloEngine
    let prompt: MobileHiddenPrompt
    var onUnlocked: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var pin = ""
    @State private var confirmPin = ""
    @State private var errorText: String?
    @State private var busy = false

    private var needsNewPIN: Bool {
        prompt.mode == .hide && !engine.conversationActions.hasHiddenPIN
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField(needsNewPIN ? "Nhập mã PIN 4 số mới" : "Nhập mã PIN 4 số", text: $pin)
                        .keyboardType(.numberPad)
                    if needsNewPIN {
                        SecureField("Nhập lại mã PIN", text: $confirmPin)
                            .keyboardType(.numberPad)
                    }
                } header: {
                    Text(headerTitle)
                } footer: {
                    if let errorText {
                        Text(errorText).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Trò chuyện ẩn")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(busy ? "Đang xử lý..." : "Xác nhận") {
                        submit()
                    }
                    .disabled(pin.count != 4 || (needsNewPIN && confirmPin != pin) || busy)
                }
            }
        }
    }

    private var headerTitle: String {
        switch prompt.mode {
        case .hide: needsNewPIN ? "Tạo mã PIN bảo vệ" : "Nhập mã PIN để ẩn"
        case .unhide: "Nhập mã PIN để hiện trò chuyện"
        case .unlock: "Nhập mã PIN để mở khóa"
        }
    }

    private func submit() {
        busy = true
        errorText = nil
        Task {
            switch prompt.mode {
            case .hide:
                let result = needsNewPIN
                    ? await engine.hideConversation(prompt.id, settingNewPIN: pin)
                    : await engine.hideConversation(prompt.id, pin: pin)
                if result.ok {
                    engine.report(result)
                    dismiss()
                } else {
                    errorText = result.text.isEmpty ? "Mã PIN không đúng." : result.text
                }
            case .unhide:
                let result = await engine.unhideConversation(prompt.id, pin: pin)
                if result.ok {
                    engine.report(result)
                    dismiss()
                } else {
                    errorText = result.text.isEmpty ? "Mã PIN không đúng." : result.text
                }
            case .unlock:
                let valid = await engine.checkHiddenChatPIN(pin)
                if valid {
                    engine.unlockHiddenConversation(prompt.id)
                    dismiss()
                    onUnlocked(prompt.id)
                } else {
                    errorText = "Mã PIN không chính xác."
                }
            }
            busy = false
        }
    }
}

private struct MobileCreateLabelSheet: View {
    let engine: ZaloEngine
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var selectedHex = "#0068FF"

    var body: some View {
        NavigationStack {
            Form {
                Section("Tên phân loại") {
                    TextField("Ví dụ: Công việc, Gia đình...", text: $name)
                }
                Section("Màu sắc") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 14) {
                        ForEach(engine.conversationExtras.limits.palette, id: \.self) { hex in
                            Button {
                                selectedHex = hex
                            } label: {
                                Circle()
                                    .fill(Color(hex: hex) ?? ZaloTheme.blue)
                                    .frame(width: 34, height: 34)
                                    .overlay {
                                        if selectedHex == hex {
                                            Image(systemName: "checkmark")
                                                .font(.caption.bold())
                                                .foregroundStyle(.white)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            .navigationTitle("Tạo phân loại")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Hủy") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") {
                        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(engine.conversationExtras.limits.maxNameLength))
                        guard !trimmed.isEmpty else { return }
                        engine.createConversationLabel(name: trimmed, colorHex: selectedHex)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct MobileStrangerFolderSheet: View {
    let engine: ZaloEngine
    let summaryById: [String: ZaloEngine.ConversationSummary]
    var onOpen: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(engine.conversationExtras.strangerFolderIds, id: \.self) { id in
                if let conv = summaryById[id] {
                    Button {
                        onOpen(id)
                    } label: {
                        HStack(spacing: 12) {
                            MobileAvatarView(url: conv.avatar, name: conv.displayName, size: 42)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(conv.displayName).font(.body.weight(.medium))
                                Text(conv.preview?.text ?? "")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if conv.unread > 0 {
                                Text("\(conv.unread)")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(Color.red, in: Capsule())
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Tin nhắn từ người lạ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Đóng") { dismiss() } }
            }
        }
    }
}

struct MobileCreateGroupSheet: View {
    let engine: ZaloEngine
    let initialMembers: [String]

    @Environment(\.dismiss) private var dismiss
    @State private var limits = GroupCreateLimits()
    @State private var selection: GroupComposeSelection
    @State private var groupName = ""
    @State private var query = ""
    @State private var avatarPhotoItem: PhotosPickerItem?
    @State private var groupAvatar: GroupAvatarImage?
    @State private var notice: String?
    @State private var busy = false

    init(engine: ZaloEngine, initialMembers: [String] = []) {
        self.engine = engine
        self.initialMembers = initialMembers
        _selection = State(initialValue: GroupComposeSelection(initialMembers))
    }

    private var roster: GroupComposeRoster {
        GroupComposeRoster(
            friends: engine.visibleFriends,
            conversations: engine.visibleConversations,
            selfId: engine.selfConversationId,
            officialAccounts: limits.officialAccounts
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    let avatarPreview = groupAvatar.map { SendableImage(image: $0.image) }
                    PhotosPicker(selection: $avatarPhotoItem, matching: .images) {
                        if let avatarPreview {
                            Image(platformImage: avatarPreview.image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 48, height: 48)
                                .clipShape(Circle())
                        } else {
                            ZStack {
                                Circle()
                                    .fill(ZaloTheme.blueTonal)
                                    .frame(width: 48, height: 48)
                                Image(systemName: "camera.fill")
                                    .foregroundStyle(ZaloTheme.blue)
                            }
                        }
                    }
                    TextField("Đặt tên nhóm", text: $groupName)
                        .onChange(of: groupName) { _, val in
                            let clamped = limits.clampedName(val)
                            if clamped != val { groupName = clamped }
                        }
                }
                .padding()

                if let notice {
                    Text(notice)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                        .padding(.bottom, 6)
                }

                List {
                    let people = roster.matching(query)
                    ForEach(people) { person in
                        let checked = selection.contains(person.id)
                        Button {
                            let res = selection.toggle(person.id, limits: limits)
                            switch res {
                            case .blocked: notice = GroupCreateLimits.blockedText
                            case .overLimit: notice = limits.overLimitText
                            case .added, .removed: notice = nil
                            }
                        } label: {
                            HStack(spacing: 12) {
                                MobileAvatarView(url: person.avatar, name: person.name, size: 38)
                                Text(person.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(checked ? ZaloTheme.blue : .secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.plain)
                .searchable(text: $query, prompt: "Tìm tên bạn bè")
            }
            .navigationTitle("Tạo nhóm (\(selection.ids.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Hủy") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(busy ? "Đang tạo..." : "Tạo") { create() }
                        .disabled(!selection.canConfirm || busy)
                }
            }
            .task {
                if let fetched = await engine.groupCreateLimitsWhenReady() {
                    limits = fetched
                    selection.keep { !limits.blocked.contains($0) }
                }
            }
            .onChange(of: avatarPhotoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("grp-av-\(UUID().uuidString).jpg")
                        try? data.write(to: tmp)
                        defer { try? FileManager.default.removeItem(at: tmp) }
                        switch GroupAvatarImage.make(from: tmp) {
                        case .success(let avatar):
                            groupAvatar = avatar
                            notice = nil
                        case .failure(let err):
                            notice = err.text
                        }
                    }
                }
            }
        }
    }

    private func create() {
        let trimmed = groupName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && !limits.isValidName(trimmed) {
            notice = GroupCreateLimits.invalidNameText
            return
        }
        busy = true
        notice = nil
        Task {
            let outcome = await engine.createGroup(name: trimmed, members: selection.ids, avatar: groupAvatar)
            busy = false
            switch outcome {
            case .created, .exists, .pending:
                dismiss()
            case .invalid(let msg, let dropped):
                notice = msg
                selection.keep { !dropped.contains($0) }
            case .failed(_, let msg, let closes):
                notice = msg
                if closes { dismiss() }
            }
        }
    }
}
