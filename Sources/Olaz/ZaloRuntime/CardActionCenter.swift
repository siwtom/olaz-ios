import Foundation

enum CardActionText {
    static let callUnsupported = "Chưa hỗ trợ gọi"
}

struct ProfileRequest: Identifiable, Equatable {
    var uid: String
    var conversationId: String
    var name: String = ""
    var avatar: URL?
    var phone: String = ""
    var isOfficialAccount = false
    /// How the profile was reached; decides the friend-request source the official client records.
    var origin: FriendRequestOrigin = .none
    /// Open straight on the add-friend form (the contact card's "KẾT BẠN").
    var startWithFriendRequest = false
    var id: String { "\(uid)|\(origin.rawValue)|\(startWithFriendRequest)" }
}

struct ReminderRequest: Identifiable, Equatable {
    var conversationId: String
    var messageId: String
    /// Open straight on "Danh sách tham gia" (the card's attendee row).
    var openList = false
    var id: String { conversationId + "|" + messageId }
}

struct AliasRequest: Identifiable, Equatable {
    var conversationId: String
    var draft: AliasDraft
    var id: String { conversationId + "|" + draft.uid }
}

struct GroupInviteRequest: Identifiable, Equatable {
    var url: URL
    var conversationId: String
    var id: String { url.absoluteString }
}

struct StickerCategoryRequest: Identifiable, Equatable {
    var conversationId: String
    var cateId: Int
    var id: String { "\(conversationId)|\(cateId)" }
}

struct PollRequest: Identifiable, Equatable {
    var conversationId: String
    var pollId: String
    var id: String { "\(conversationId)|\(pollId)" }
}

/// Per-app state of card actions that must survive the message list recycling its rows.
@MainActor @Observable
final class CardActionCenter {
    static let shared = CardActionCenter()

    struct Notice: Identifiable, Equatable {
        let id = UUID()
        let text: String
        /// Shown only while this conversation is open (nil = anywhere).
        var conversation: String?
    }

    private(set) var busy: Set<String> = []
    var profile: ProfileRequest?
    var reminder: ReminderRequest?
    var alias: AliasRequest?
    var groupInvite: GroupInviteRequest?
    var stickers: StickerCategoryRequest?
    var poll: PollRequest?
    private(set) var notice: Notice?

    /// Drops every sheet and the toast. Called when another conversation opens and on logout, so nothing from one
    /// conversation / account re-presents in the next. (Busy buttons finish on their own.)
    func reset() {
        profile = nil
        reminder = nil
        alias = nil
        groupInvite = nil
        stickers = nil
        poll = nil
        notice = nil
    }

    private func key(_ conversation: String, _ message: String, _ ref: String) -> String { conversation + "|" + message + "|" + ref }

    /// `ref` nil = any button of that message.
    func isBusy(conversation: String, message: String, ref: String?) -> Bool {
        if let ref { return busy.contains(key(conversation, message, ref)) }
        let prefix = key(conversation, message, "")
        return busy.contains { $0.hasPrefix(prefix) }
    }

    /// Runs the button once at a time; a second click while it is in flight is ignored.
    func run(engine: ZaloEngine, conversation: String, message: String, ref: String) {
        exclusive(conversation: conversation, message: message, ref: ref) { [self] in
            let outcome = await engine.performCardAction(in: conversation, message: message, ref: ref)
            switch outcome {
            case .openProfile(let uid):
                // The sheet belongs to the conversation on screen; a late answer for another one is dropped.
                if engine.openConversationId == conversation { profile = ProfileRequest(uid: uid, conversationId: conversation) }
            case .copy: show("Đã sao chép", in: conversation)
            case .unsupported(let text), .locked(let text), .failed(let text), .pending(let text): show(text, in: conversation)
            case .present(let sheet):
                // Like the profile sheet: it belongs to the conversation on screen, a late answer for another one is dropped.
                guard engine.openConversationId == conversation else { break }
                switch sheet {
                case .alias(let draft): alias = AliasRequest(conversationId: conversation, draft: draft)
                case .groupInvite(let url): groupInvite = GroupInviteRequest(url: url, conversationId: conversation)
                case .stickers(let id): stickers = StickerCategoryRequest(conversationId: conversation, cateId: id)
                case .poll(let id): poll = PollRequest(conversationId: conversation, pollId: id)
                case .tab: break   // applied by the engine
                }
            case .done, .openChat, .openURL: break
            }
        }
    }

    /// Stands in for the message in the busy keys of a reminder's RSVP: the alert and the invite card of one reminder are different
    /// messages but must not both send an answer.
    static func reminderScope(_ reminderId: String) -> String { "reminder:" + reminderId }

    /// RSVP to a reminder through the official controller. Busy state is per reminder (`reminder` = its id; "" falls back to the message).
    func respond(engine: ZaloEngine, conversation: String, message: String, reminder: String = "", accept: Bool) {
        let scope = reminder.isEmpty ? message : Self.reminderScope(reminder)
        exclusive(conversation: conversation, message: scope, ref: accept ? "rsvp:accept" : "rsvp:reject") { [self] in
            let result = await engine.respondToReminder(in: conversation, message: message, accept: accept)
            if !result.ok { show(result.text.isEmpty ? "Có lỗi xảy ra" : result.text, in: conversation) }
        }
    }

    private func exclusive(conversation: String, message: String, ref: String, _ work: @escaping @MainActor () async -> Void) {
        let key = key(conversation, message, ref)
        guard !isBusy(conversation: conversation, message: message, ref: nil) else { return }
        busy.insert(key)
        Task {
            await work()
            busy.remove(key)
        }
    }

    func show(_ text: String, in conversation: String? = nil) {
        let next = Notice(text: text, conversation: conversation)
        notice = next
        Task {
            try? await Task.sleep(for: .seconds(4))
            if notice == next { notice = nil }
        }
    }
}

/// What a card needs to run its buttons.
@MainActor
struct CardActions {
    var conversationId = ""
    var messageId = ""
    var center: CardActionCenter?
    var engine: ZaloEngine?

    func isBusy(_ ref: String) -> Bool { center?.isBusy(conversation: conversationId, message: messageId, ref: ref) ?? false }
    var anyBusy: Bool { center?.isBusy(conversation: conversationId, message: messageId, ref: nil) ?? false }

    func run(_ ref: String) {
        guard let center, let engine else { return }
        center.run(engine: engine, conversation: conversationId, message: messageId, ref: ref)
    }

    func respond(accept: Bool, reminder: String = "") {
        guard let center, let engine else { return }
        center.respond(engine: engine, conversation: conversationId, message: messageId, reminder: reminder, accept: accept)
    }

    /// RSVP busy state of a reminder (shared by all its cards); `ref` nil = any answer.
    func isRsvpBusy(_ reminder: String, ref: String? = nil) -> Bool {
        guard !reminder.isEmpty else { return ref.map(isBusy) ?? anyBusy }
        return center?.isBusy(conversation: conversationId, message: CardActionCenter.reminderScope(reminder), ref: ref) ?? false
    }

    func showProfile(_ request: ProfileRequest) { center?.profile = request }

    /// Opens a link from a card: a group invite link shows the group sheet (official GROUP_PREVIEW), anything else goes to the browser
    /// (http/https only, through `WebLink`).
    func openLink(_ url: URL?) {
        if let url = WebLink.sanitized(url), GroupInviteLink.isInvite(url), let center {
            center.groupInvite = GroupInviteRequest(url: url, conversationId: conversationId)
        } else {
            WebLink.open(url)
        }
    }
    func showReminder(openList: Bool = false) {
        center?.reminder = ReminderRequest(conversationId: conversationId, messageId: messageId, openList: openList)
    }
}
