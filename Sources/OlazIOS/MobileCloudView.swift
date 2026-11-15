import SwiftUI

struct MobileCloudView: View {
    @Bindable var engine: ZaloEngine
    var onOpenConversation: (String) -> Void

    @State private var selectedKind: CloudItemKind?
    @State private var sortBySize = false
    @State private var items: [CloudItem] = []
    @State private var hasMore = false
    @State private var loading = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            List {
                if let myCloudId = engine.cloud.selfId ?? engine.selfConversationId {
                    Section {
                        Button {
                            onOpenConversation(myCloudId)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "cloud.fill")
                                    .font(.title2)
                                    .foregroundStyle(ZaloTheme.blue)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Cloud của tôi")
                                        .font(.body.weight(.semibold))
                                    Text("Ghi chú, gửi nhanh ảnh/file cho chính mình")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let plan = engine.cloud.plan {
                    Section("Dung lượng zCloud (\(plan.name))") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(ByteCountFormatter.string(fromByteCount: plan.usage, countStyle: .file))
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                if plan.quota > 0 {
                                    Text("/ \(ByteCountFormatter.string(fromByteCount: plan.quota, countStyle: .file))")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            if plan.quota > 0 {
                                ProgressView(value: min(1.0, Double(plan.usage) / Double(plan.quota)))
                            }
                            HStack(spacing: 12) {
                                Label(ByteCountFormatter.string(fromByteCount: engine.cloud.media.photo, countStyle: .file), systemImage: "photo")
                                Label(ByteCountFormatter.string(fromByteCount: engine.cloud.media.video, countStyle: .file), systemImage: "video")
                                Label(ByteCountFormatter.string(fromByteCount: engine.cloud.media.file, countStyle: .file), systemImage: "doc")
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)

                        if engine.cloud.settings.offloadAvailable {
                            Toggle("Tự động giải phóng dung lượng", isOn: Binding(
                                get: { engine.cloud.settings.offloadEnabled },
                                set: { value in
                                    Task {
                                        let res = await engine.cloudSetOffload(value)
                                        if !res.ok, let msg = res.error { errorText = msg }
                                    }
                                }
                            ))
                        }
                    }
                }

                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            filterChip("Tất cả", kind: nil)
                            ForEach([CloudItemKind.photo, .video, .file, .voice], id: \.rawValue) { kind in
                                filterChip(kind.title, kind: kind)
                            }
                        }
                        .padding(.vertical, 2)
                    }

                    Toggle("Sắp xếp theo dung lượng", isOn: $sortBySize)

                    if let errorText {
                        Text(errorText)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    if loading && items.isEmpty {
                        ProgressView("Đang tải dữ liệu zCloud...")
                    } else if items.isEmpty {
                        Text("Không có dữ liệu phù hợp.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(items) { item in
                            Button {
                                fetchAndShare(item)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: item.kind.symbol)
                                        .foregroundStyle(ZaloTheme.blue)
                                        .frame(width: 28)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.title.isEmpty ? item.conversationName : item.title)
                                            .font(.subheadline.weight(.medium))
                                            .lineLimit(1)
                                        HStack(spacing: 6) {
                                            Text(item.conversationName)
                                            Text("·")
                                            Text(ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file))
                                        }
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                    }
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing) {
                                Button("Xóa", role: .destructive) {
                                    deleteItem(item)
                                }
                            }
                        }
                        if hasMore {
                            Button("Tải thêm") {
                                Task { await loadPage(reset: false) }
                            }
                        }
                    }
                } header: {
                    Text("Tệp trên zCloud")
                }
            }
            .navigationTitle("zCloud")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        engine.refreshCloud()
                        Task { await loadPage(reset: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
        .task {
            engine.ensureBackgroundWorker()
            engine.refreshCloud()
            await loadPage(reset: true)
        }
        .onChange(of: selectedKind) { _, _ in
            Task { await loadPage(reset: true) }
        }
        .onChange(of: sortBySize) { _, _ in
            Task { await loadPage(reset: true) }
        }
    }

    private func filterChip(_ title: String, kind: CloudItemKind?) -> some View {
        let active = selectedKind == kind
        return Button {
            selectedKind = kind
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(active ? ZaloTheme.blue : Color(.tertiarySystemFill), in: Capsule())
                .foregroundStyle(active ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    private func loadPage(reset: Bool) async {
        loading = true
        errorText = nil
        defer { loading = false }
        let offset = reset ? 0 : items.count
        let page = await engine.cloudList(
            conversationId: nil,
            kind: selectedKind,
            sortBySize: sortBySize,
            ascending: false,
            offset: offset,
            limit: 40
        )
        if reset { items = page.items } else { items.append(contentsOf: page.items) }
        hasMore = page.hasMore
        if let err = page.error { errorText = err }
    }

    private func fetchAndShare(_ item: CloudItem) {
        Task {
            switch await engine.cloudFetch(item.id) {
            case .ready(let file):
                NotificationCenter.default.post(name: .olazShareFileRequested, object: file.url)
            case .expired:
                errorText = "Tệp này đã hết hạn trên zCloud."
            case .failed(let msg):
                errorText = msg
            }
        }
    }

    private func deleteItem(_ item: CloudItem) {
        Task {
            let res = await engine.cloudDelete([item.id])
            if res.ok {
                items.removeAll { $0.id == item.id }
            } else {
                errorText = res.error ?? "Không thể xóa mục này."
            }
        }
    }
}
