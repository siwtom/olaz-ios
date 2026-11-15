import SwiftUI

struct MobileContactsView: View {
    enum Segment: String, CaseIterable, Identifiable {
        case friends = "Bạn bè"
        case groups = "Nhóm"
        case requests = "Lời mời"
        var id: String { rawValue }
    }

    @Bindable var engine: ZaloEngine
    @Binding var groupComposeRequest: GroupComposeRequest?
    var onOpenConversation: (String) -> Void

    @State private var segment: Segment = .friends
    @State private var searchText = ""
    @State private var showAddFriend = false

    private var filteredFriends: [ContactsState.Friend] {
        let base = engine.visibleFriends
        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return base }
        let folded = ZaloEngine.contactFold(needle)
        return base.filter { $0.sortKey.contains(folded) || $0.name.localizedCaseInsensitiveContains(needle) }
    }

    private var filteredGroups: [ContactsState.Group] {
        let base = engine.visibleGroups
        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return base }
        let folded = ZaloEngine.contactFold(needle)
        return base.filter { $0.sortKey.contains(folded) || $0.name.localizedCaseInsensitiveContains(needle) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Mục", selection: $segment) {
                    ForEach(Segment.allCases) { item in
                        if item == .requests && engine.contacts.pendingRequestCount > 0 {
                            Text("\(item.rawValue) (\(engine.contacts.pendingRequestCount))").tag(item)
                        } else {
                            Text(item.rawValue).tag(item)
                        }
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)

                List {
                    switch segment {
                    case .friends:
                        friendsContent
                    case .groups:
                        groupsContent
                    case .requests:
                        requestsContent
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Danh bạ")
            .searchable(text: $searchText, prompt: "Tìm trong danh bạ")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 14) {
                        Button {
                            showAddFriend = true
                        } label: {
                            Image(systemName: "person.badge.plus")
                        }
                        Button {
                            groupComposeRequest = GroupComposeRequest()
                        } label: {
                            Image(systemName: "person.3")
                        }
                    }
                }
            }
            .onAppear {
                if SectionRouter.wantsGroupList {
                    SectionRouter.wantsGroupList = false
                    segment = .groups
                }
                engine.refreshContacts()
            }
            .onReceive(NotificationCenter.default.publisher(for: SectionRouter.notification)) { note in
                if let raw = note.object as? String, raw == SidebarTarget.groups.rawValue {
                    SectionRouter.wantsGroupList = false
                    segment = .groups
                }
            }
            .sheet(isPresented: $showAddFriend) {
                MobileFindFriendSheet(engine: engine) { id in
                    showAddFriend = false
                    onOpenConversation(id)
                }
            }
        }
    }

    @ViewBuilder
    private var friendsContent: some View {
        if !engine.conversationActions.hiddenKnown {
            ProgressView("Đang đồng bộ bạn bè...")
        } else if filteredFriends.isEmpty {
            ContentUnavailableView("Không có bạn bè phù hợp", systemImage: "person.2")
        } else {
            let grouped = Dictionary(grouping: filteredFriends, by: \.section)
            let keys = grouped.keys.sorted { a, b in
                if a == "#" { return false }
                if b == "#" { return true }
                return a < b
            }
            ForEach(keys, id: \.self) { section in
                Section(section) {
                    ForEach(grouped[section] ?? []) { friend in
                        Button {
                            onOpenConversation(friend.id)
                        } label: {
                            HStack(spacing: 12) {
                                MobileAvatarView(url: friend.avatar, name: friend.name, size: 42)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(friend.name).font(.body.weight(.medium))
                                    if friend.online {
                                        Text("Đang hoạt động")
                                            .font(.caption)
                                            .foregroundStyle(.green)
                                    }
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var groupsContent: some View {
        if !engine.conversationActions.hiddenKnown {
            ProgressView("Đang đồng bộ nhóm...")
        } else if filteredGroups.isEmpty {
            ContentUnavailableView("Chưa có nhóm nào", systemImage: "person.3")
        } else {
            ForEach(filteredGroups) { group in
                Button {
                    onOpenConversation(group.id)
                } label: {
                    HStack(spacing: 12) {
                        MobileAvatarView(url: group.avatar, name: group.name, size: 44, isGroup: true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.name).font(.body.weight(.medium))
                            Text("\(group.members) thành viên")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var requestsContent: some View {
        if engine.contacts.loadingRequests && engine.contacts.received.isEmpty && engine.contacts.sent.isEmpty {
            ProgressView("Đang tải lời mời...")
        } else {
            if !engine.contacts.received.isEmpty {
                Section("Lời mời đã nhận (\(engine.contacts.received.count))") {
                    ForEach(engine.contacts.received) { req in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 12) {
                                MobileAvatarView(url: req.avatar, name: req.name, size: 42)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(req.name).font(.body.weight(.semibold))
                                    if !req.message.isEmpty {
                                        Text(req.message)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            HStack(spacing: 10) {
                                Button("Đồng ý") { engine.acceptFriendRequest(req.id) }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                Button("Từ chối") { engine.declineFriendRequest(req.id) }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            if !engine.contacts.sent.isEmpty {
                Section("Lời mời đã gửi (\(engine.contacts.sent.count))") {
                    ForEach(engine.contacts.sent) { req in
                        HStack(spacing: 12) {
                            MobileAvatarView(url: req.avatar, name: req.name, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(req.name).font(.body.weight(.medium))
                                if !req.message.isEmpty {
                                    Text(req.message).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            Spacer()
                            Button("Thu hồi") {
                                engine.cancelFriendRequest(req.id)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
            }

            if engine.contacts.received.isEmpty && engine.contacts.sent.isEmpty {
                ContentUnavailableView("Không có lời mời kết bạn nào", systemImage: "person.crop.circle.badge.checkmark")
            }
        }
    }
}

private struct MobileFindFriendSheet: View {
    @Bindable var engine: ZaloEngine
    var onOpenConversation: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var phone = ""
    @State private var greeting = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Số điện thoại") {
                    HStack {
                        TextField("Nhập số điện thoại...", text: $phone)
                            .keyboardType(.phonePad)
                        Button("Tìm") {
                            engine.findFriend(byPhone: phone)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                switch engine.contacts.search.status {
                case .idle:
                    EmptyView()
                case .searching:
                    Section {
                        HStack {
                            ProgressView()
                            Text("Đang tìm...")
                        }
                    }
                case .error:
                    Section {
                        Text(engine.contacts.search.error ?? "Không tìm thấy tài khoản.")
                            .foregroundStyle(.red)
                    }
                case .found:
                    if let user = engine.contacts.search.user {
                        Section("Kết quả") {
                            HStack(spacing: 12) {
                                MobileAvatarView(url: user.avatar, name: user.name, size: 50)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(user.name).font(.headline)
                                    if !user.bio.isEmpty {
                                        Text(user.bio).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            if !user.isSelf {
                                Button("Nhắn tin") {
                                    onOpenConversation(user.id)
                                }
                                if !user.isFriend && !user.requested {
                                    TextField("Lời mời kết bạn", text: $greeting, axis: .vertical)
                                    Button("Kết bạn") {
                                        let msg = String((greeting.isEmpty ? user.defaultMessage : greeting).prefix(user.maxMessage))
                                        engine.sendFriendRequest(to: user.id, message: msg)
                                    }
                                    .buttonStyle(.borderedProminent)
                                } else if user.requested {
                                    Text("Đã gửi lời mời kết bạn")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                if let notice = engine.contacts.notice, !notice.text.isEmpty {
                    Section {
                        Text(notice.text)
                            .foregroundStyle(notice.ok ? .green : .red)
                    }
                }
            }
            .navigationTitle("Thêm bạn")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") {
                        engine.resetFriendSearch()
                        dismiss()
                    }
                }
            }
        }
    }
}
