import Foundation
import Postbox
import SwiftSignalKit

public struct MiraFakeGift: Codable, Equatable {
    /// Telegram charges 25 Stars when a collectible gift is transferred.
    /// Keep this in the local model so old entries and every projection use
    /// one authoritative default instead of silently creating free transfers.
    public static let defaultNFTTransferStars: Int64 = 25

    public enum Kind: String, Codable {
        case regular
        case uniqueBySlug
        case uniqueById
    }

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case giftId
        case slug
        case uniqueNumber
        case fromPeerId
        case fromPeerIdIsPacked
        case fromName
        case caption
        case ownerPeerId
        case pendingTransferRecipientPeerId
        case date
        case isHidden
        case isSaved
        case showInChat
        case collectionIds
        case transferStars
        case chatMessagePeerId
        case chatMessageId
        case giftSnapshot
    }

    public var id: String
    public var kind: Kind
    public var giftId: Int64?
    public var slug: String?
    public var uniqueNumber: Int32?
    public var fromPeerId: Int64?
    // nil denotes legacy entries that mixed raw user ids and packed PeerIds.
    public var fromPeerIdIsPacked: Bool?
    public var fromName: String?
    public var caption: String?
    /// Packed local owner used by transferred fake NFTs. It is optional so
    /// older entries continue to resolve to the current account owner.
    public var ownerPeerId: Int64?
    /// Durable transfer intent. It is set before the destination projection or
    /// Stars debit so an interrupted transfer can only be resumed for the
    /// originally selected recipient.
    public var pendingTransferRecipientPeerId: Int64?
    public var date: Int32
    public var isHidden: Bool
    public var isSaved: Bool
    public var showInChat: Bool
    /// Server collection ids that this local gift is shown in. The ids are
    /// only a local projection; collection mutations never send this gift to
    /// Telegram's payments API.
    public var collectionIds: [Int32]
    /// Legacy persisted field. Local collectible transfers use Telegram's
    /// standard 25-Star fee; older builds could persist an accidental value.
    public var transferStars: Int64?

    // Local "gift received" message location, set after insertion so it can be deleted again.
    public var chatMessagePeerId: Int64?
    public var chatMessageId: Int32?

    // Resolved gift data cached at add-time (or after first successful resolution),
    // so the profile shelf renders without any extra network requests.
    public var giftSnapshot: StarGift?

    /// The persisted kind is authoritative for fake gifts.  The snapshot can
    /// be missing while a catalog item is being resolved, so callers should
    /// use this instead of inferring NFT state from optional fields.
    public var isUnique: Bool {
        switch self.kind {
        case .regular:
            return false
        case .uniqueBySlug, .uniqueById:
            return true
        }
    }

    public init(
        id: String = UUID().uuidString,
        kind: Kind,
        giftId: Int64? = nil,
        slug: String? = nil,
        uniqueNumber: Int32? = nil,
        fromPeerId: Int64? = nil,
        fromPeerIdIsPacked: Bool? = nil,
        fromName: String? = nil,
        caption: String? = nil,
        ownerPeerId: Int64? = nil,
        pendingTransferRecipientPeerId: Int64? = nil,
        date: Int32,
        isHidden: Bool = false,
        isSaved: Bool = false,
        showInChat: Bool = true,
        collectionIds: [Int32] = [],
        transferStars: Int64? = nil,
        chatMessagePeerId: Int64? = nil,
        chatMessageId: Int32? = nil,
        giftSnapshot: StarGift? = nil
    ) {
        self.id = id
        self.kind = kind
        self.giftId = giftId
        self.slug = slug
        self.uniqueNumber = uniqueNumber
        self.fromPeerId = fromPeerId
        self.fromPeerIdIsPacked = fromPeerIdIsPacked
        self.fromName = fromName
        self.caption = caption
        self.ownerPeerId = ownerPeerId
        self.pendingTransferRecipientPeerId = pendingTransferRecipientPeerId
        self.date = date
        self.isHidden = isHidden
        self.isSaved = isSaved
        self.showInChat = showInChat
        self.collectionIds = Array(Set(collectionIds)).sorted()
        if kind == .regular {
            self.transferStars = nil
        } else {
            self.transferStars = Self.defaultNFTTransferStars
        }
        self.chatMessagePeerId = chatMessagePeerId
        self.chatMessageId = chatMessageId
        self.giftSnapshot = giftSnapshot
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.kind = try container.decode(Kind.self, forKey: .kind)
        self.giftId = try container.decodeIfPresent(Int64.self, forKey: .giftId)
        self.slug = try container.decodeIfPresent(String.self, forKey: .slug)
        self.uniqueNumber = try container.decodeIfPresent(Int32.self, forKey: .uniqueNumber)
        self.fromPeerId = try container.decodeIfPresent(Int64.self, forKey: .fromPeerId)
        self.fromPeerIdIsPacked = try container.decodeIfPresent(Bool.self, forKey: .fromPeerIdIsPacked)
        self.fromName = try container.decodeIfPresent(String.self, forKey: .fromName)
        self.caption = try container.decodeIfPresent(String.self, forKey: .caption)
        self.ownerPeerId = try container.decodeIfPresent(Int64.self, forKey: .ownerPeerId)
        self.pendingTransferRecipientPeerId = try container.decodeIfPresent(Int64.self, forKey: .pendingTransferRecipientPeerId)
        self.date = try container.decodeIfPresent(Int32.self, forKey: .date) ?? 0
        self.isHidden = try container.decodeIfPresent(Bool.self, forKey: .isHidden) ?? false
        self.isSaved = try container.decodeIfPresent(Bool.self, forKey: .isSaved) ?? false
        self.showInChat = try container.decodeIfPresent(Bool.self, forKey: .showInChat) ?? true
        self.collectionIds = Array(Set(try container.decodeIfPresent([Int32].self, forKey: .collectionIds) ?? [])).sorted()
        _ = try container.decodeIfPresent(Int64.self, forKey: .transferStars)
        if self.kind == .regular {
            self.transferStars = nil
        } else {
            // The field was user editable in an earlier build and could
            // retain bogus amounts (for example 1000 Stars). Local collectible
            // transfers follow Telegram's fixed transfer fee.
            self.transferStars = Self.defaultNFTTransferStars
        }
        self.chatMessagePeerId = try container.decodeIfPresent(Int64.self, forKey: .chatMessagePeerId)
        self.chatMessageId = try container.decodeIfPresent(Int32.self, forKey: .chatMessageId)
        self.giftSnapshot = try container.decodeIfPresent(StarGift.self, forKey: .giftSnapshot)
    }

    // Deterministic, collision-safe savedId for StarGiftReference.peer (Swift's hashValue is randomized per launch).
    public var stableSavedId: Int64 {
        var hash: UInt64 = 14695981039346656037
        for byte in self.id.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211
        }
        return Int64(bitPattern: (hash & 0x0000ffffffffffff) | 0x1111000000000000)
    }

    public static func isLocalSavedId(_ id: Int64) -> Bool {
        return UInt64(bitPattern: id) & 0xffff000000000000 == 0x1111000000000000
    }

    /// Settings historically persisted a raw Telegram user id while newer
    /// entries may contain the packed PeerId value. Normalize both forms
    /// before looking up a sender so malformed values never reach PeerId's
    /// packed initializer in the message/profile projection.
    public static func peerId(fromStoredValue value: Int64, isPacked: Bool? = nil) -> PeerId? {
        guard value > 0 else {
            return nil
        }
        if isPacked == false || (isPacked == nil && value <= Int64(Int32.max)) {
            guard value <= 0x00ffffffffffffff else {
                return nil
            }
            return PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(value))
        }
        let bits = UInt64(bitPattern: value)
        let namespaceBits = UInt32((bits >> 32) & 0x7)
        let namespace = PeerId.Namespace._internalFromInt32Value(Int32(bitPattern: namespaceBits))
        guard namespace == Namespaces.Peer.CloudUser || namespace == Namespaces.Peer.CloudGroup || namespace == Namespaces.Peer.CloudChannel || namespace == Namespaces.Peer.SecretChat else {
            return nil
        }
        let idValue: Int64
        if namespace == Namespaces.Peer.SecretChat && ((bits >> 35) & 0xffffffff) == 0 {
            // Match Postbox's legacy namespace-3 codec: its low word is a
            // signed Int32, including negative ids.
            idValue = Int64(Int32(bitPattern: UInt32(bits & 0xffffffff)))
        } else {
            let idBits = ((bits >> 35) << 32) | (bits & 0xffffffff)
            idValue = Int64(bitPattern: idBits)
        }
        guard idValue >= -0x007fffffffffffff && idValue <= 0x00ffffffffffffff else {
            return nil
        }
        return PeerId(namespace: namespace, id: PeerId.Id._internalFromInt64Value(idValue))
    }
}

public struct MiraFakeGiftsSnapshot: Codable, Equatable {
    public static let currentSchemaVersion = 2
    public let schemaVersion: Int
    public let gifts: [MiraFakeGift]
    public let collections: [MiraFakeGiftCollection]

    public init(schemaVersion: Int = MiraFakeGiftsSnapshot.currentSchemaVersion, gifts: [MiraFakeGift] = [], collections: [MiraFakeGiftCollection] = []) {
        self.schemaVersion = schemaVersion
        self.gifts = gifts
        self.collections = collections
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case gifts
        case collections
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 0
        self.gifts = try container.decodeIfPresent([MiraFakeGift].self, forKey: .gifts) ?? []
        self.collections = try container.decodeIfPresent([MiraFakeGiftCollection].self, forKey: .collections) ?? []
    }
}

/// A collection that exists only in this account's local gift projection.
/// Negative ids are reserved for local collections and cannot be mistaken for
/// Telegram collection ids.
public struct MiraFakeGiftCollection: Codable, Equatable {
    public let id: Int32
    public let ownerPeerId: Int64
    public var title: String
    public var gifts: [ProfileGiftsContext.State.StarGift]

    public init(id: Int32, ownerPeerId: Int64, title: String, gifts: [ProfileGiftsContext.State.StarGift]) {
        self.id = id
        self.ownerPeerId = ownerPeerId
        self.title = title
        self.gifts = gifts
    }
}

public final class MiraFakeGiftsStore {
    private static let registryQueue = DispatchQueue(label: "org.telegram.mira.fakeGiftsStore.registry")
    private static var registeredStores: [Int64: MiraFakeGiftsStore] = [:]

    public static func register(accountPeerId: PeerId, store: MiraFakeGiftsStore) {
        self.registryQueue.sync {
            self.registeredStores[accountPeerId.toInt64()] = store
        }
    }

    public static func store(for accountPeerId: PeerId) -> MiraFakeGiftsStore? {
        return self.registryQueue.sync {
            return self.registeredStores[accountPeerId.toInt64()]
        }
    }

    private let queue = DispatchQueue(label: "org.telegram.mira.fakeGiftsStore", qos: .utility)
    // ValuePromise delivers synchronously on the thread that calls `set`. Never
    // publish while holding `queue`: subscribers commonly call `list()` from
    // their callback, and that would synchronously wait on this queue again.
    private let publicationQueue = DispatchQueue(label: "org.telegram.mira.fakeGiftsStore.publication", qos: .utility)
    private let filePath: String
    private let accountPeerId: PeerId?
    private var cache: [MiraFakeGift] = []
    private var collectionsCache: [MiraFakeGiftCollection] = []
    private var didLoad = false
    private var needsMigrationWrite = false
    private var readOnly = false

    private let changesPromise = ValuePromise<[MiraFakeGift]>([], ignoreRepeated: true)
    private let collectionsChangesPromise = ValuePromise<[MiraFakeGiftCollection]>([], ignoreRepeated: true)

    /// Keep the local editor and every persisted projection on one transfer
    /// contract. Older builds allowed an arbitrary Stars amount (including
    /// 1000) to leak into a fake NFT; Telegram's local emulation uses the
    /// standard 25-Star transfer price instead.
    private func normalizedForStorage(_ gift: MiraFakeGift) -> MiraFakeGift {
        var normalized = gift
        if normalized.isUnique {
            normalized.transferStars = MiraFakeGift.defaultNFTTransferStars
        } else {
            normalized.transferStars = nil
        }
        normalized.collectionIds = Array(Set(normalized.collectionIds)).sorted()
        return normalized
    }

    private func publishLocked() {
        let snapshot = self.cache
        let collectionsSnapshot = self.collectionsCache
        self.publicationQueue.async { [weak self] in
            self?.changesPromise.set(snapshot)
            self?.collectionsChangesPromise.set(collectionsSnapshot)
        }
    }

    public init(basePath: String, accountPeerId: PeerId? = nil) {
        self.filePath = basePath + "/mira-fake-gifts.json"
        self.accountPeerId = accountPeerId
    }

    private func loadIfNeeded() {
        if self.didLoad {
            return
        }
        self.didLoad = true
        guard let data = FileManager.default.contents(atPath: self.filePath) else {
            self.publishLocked()
            return
        }
        if let snapshot = try? JSONDecoder().decode(MiraFakeGiftsSnapshot.self, from: data) {
            self.readOnly = snapshot.schemaVersion > MiraFakeGiftsSnapshot.currentSchemaVersion
            var normalizedGifts = snapshot.gifts
            for index in normalizedGifts.indices where normalizedGifts[index].isUnique {
                if normalizedGifts[index].transferStars != MiraFakeGift.defaultNFTTransferStars {
                    normalizedGifts[index].transferStars = MiraFakeGift.defaultNFTTransferStars
                }
            }
            self.needsMigrationWrite = snapshot.schemaVersion < MiraFakeGiftsSnapshot.currentSchemaVersion || normalizedGifts != snapshot.gifts
            self.cache = normalizedGifts
            self.collectionsCache = snapshot.collections.filter { $0.id < 0 }
        } else if let gifts = try? JSONDecoder().decode([MiraFakeGift].self, from: data) {
            // Older builds could append the same entry more than once when an edit
            // raced an asynchronous insert. Keep the newest copy by id so the
            // profile and chat projections remain one-to-one.
            var uniqueGifts: [MiraFakeGift] = []
            var indexes: [String: Int] = [:]
            for gift in gifts {
                if let index = indexes[gift.id] {
                    uniqueGifts[index] = gift
                } else {
                    indexes[gift.id] = uniqueGifts.count
                    uniqueGifts.append(gift)
                }
            }
            // Legacy array snapshots predate the versioned envelope and can
            // contain user-edited transfer fees (including the old 1000-Star
            // value). Normalize before exposing the cache so a transfer can
            // never charge a stale fee during this migration window.
            self.cache = uniqueGifts.map { self.normalizedForStorage($0) }
            self.collectionsCache = []
            self.needsMigrationWrite = true
        } else {
            // Never overwrite an unreadable local file with an empty cache.
            // Keeping the store read-only preserves recovery data and mirrors
            // the future-schema behavior used by the other local stores.
            self.readOnly = true
        }
        if self.needsMigrationWrite && !self.readOnly {
            self.saveLocked()
            self.needsMigrationWrite = false
        }
        self.publishLocked()
    }

    @discardableResult
    private func saveLocked() -> Bool {
        guard let data = try? JSONEncoder().encode(MiraFakeGiftsSnapshot(gifts: self.cache, collections: self.collectionsCache)) else {
            return false
        }
        do {
            try data.write(to: URL(fileURLWithPath: self.filePath), options: [.atomic])
            return true
        } catch {
            return false
        }
    }

    public func list() -> [MiraFakeGift] {
        return self.queue.sync {
            self.loadIfNeeded()
            return self.cache
        }
    }

    public var changes: Signal<[MiraFakeGift], NoError> {
        return Signal { [weak self] subscriber in
            guard let self else {
                return EmptyDisposable
            }
            let disposable = self.changesPromise.get().start(next: { value in
                subscriber.putNext(value)
            })
            self.queue.async {
                self.loadIfNeeded()
            }
            return disposable
        }
    }

    public var collectionsChanges: Signal<[MiraFakeGiftCollection], NoError> {
        return Signal { [weak self] subscriber in
            guard let self else {
                return EmptyDisposable
            }
            let disposable = self.collectionsChangesPromise.get().start(next: { value in
                subscriber.putNext(value)
            })
            self.queue.async {
                self.loadIfNeeded()
            }
            return disposable
        }
    }

    public func localCollections(ownerPeerId: PeerId) -> [MiraFakeGiftCollection] {
        return self.queue.sync {
            self.loadIfNeeded()
            return self.collectionsCache.filter { $0.ownerPeerId == ownerPeerId.toInt64() }
        }
    }

    public func localCollection(id: Int32, ownerPeerId: PeerId) -> MiraFakeGiftCollection? {
        return self.queue.sync {
            self.loadIfNeeded()
            return self.collectionsCache.first(where: { $0.id == id && $0.ownerPeerId == ownerPeerId.toInt64() })
        }
    }

    @discardableResult
    public func createLocalCollection(ownerPeerId: PeerId, title: String, gifts: [ProfileGiftsContext.State.StarGift]) -> MiraFakeGiftCollection? {
        return self.queue.sync { () -> MiraFakeGiftCollection? in
            self.loadIfNeeded()
            guard !self.readOnly else {
                return nil
            }
            let trimmedTitle = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(12))
            guard !trimmedTitle.isEmpty else {
                return nil
            }
            let ownerCollections = self.collectionsCache.filter { $0.ownerPeerId == ownerPeerId.toInt64() }
            let smallestId = ownerCollections.map(\.id).filter { $0 < 0 }.min() ?? 0
            guard smallestId > Int32.min else {
                return nil
            }
            let collectionId = smallestId - 1
            let normalizedGifts = self.uniqueCollectionGifts(gifts).map { gift in
                var collectionIds = gift.collectionIds ?? []
                if !collectionIds.contains(collectionId) {
                    collectionIds.append(collectionId)
                }
                return gift.withCollectionIds(collectionIds)
            }
            let collection = MiraFakeGiftCollection(id: collectionId, ownerPeerId: ownerPeerId.toInt64(), title: trimmedTitle, gifts: normalizedGifts)
            let previousCollections = self.collectionsCache
            let previousGifts = self.cache
            self.collectionsCache.append(collection)
            self.updateStoredFakeGiftCollectionMembership(ownerPeerId: ownerPeerId, collectionId: collectionId, gifts: normalizedGifts)
            guard self.saveLocked() else {
                self.collectionsCache = previousCollections
                self.cache = previousGifts
                return nil
            }
            self.publishLocked()
            return collection
        }
    }

    @discardableResult
    public func updateLocalCollection(ownerPeerId: PeerId, collectionId: Int32, title: String? = nil, gifts: [ProfileGiftsContext.State.StarGift]? = nil) -> MiraFakeGiftCollection? {
        return self.queue.sync { () -> MiraFakeGiftCollection? in
            self.loadIfNeeded()
            guard !self.readOnly,
                  let index = self.collectionsCache.firstIndex(where: { $0.id == collectionId && $0.ownerPeerId == ownerPeerId.toInt64() }) else {
                return nil
            }
            let previousCollections = self.collectionsCache
            let previousGifts = self.cache
            let oldCollection = self.collectionsCache[index]
            let updatedTitle = title.map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(12)) } ?? oldCollection.title
            guard !updatedTitle.isEmpty else {
                return nil
            }
            let updatedGifts = self.uniqueCollectionGifts(gifts ?? oldCollection.gifts).map { gift in
                var collectionIds = (gift.collectionIds ?? []).filter { $0 != collectionId }
                collectionIds.append(collectionId)
                return gift.withCollectionIds(collectionIds)
            }
            let collection = MiraFakeGiftCollection(id: collectionId, ownerPeerId: ownerPeerId.toInt64(), title: updatedTitle, gifts: updatedGifts)
            self.collectionsCache[index] = collection
            self.updateStoredFakeGiftCollectionMembership(ownerPeerId: ownerPeerId, collectionId: collectionId, gifts: oldCollection.gifts, remove: true)
            self.updateStoredFakeGiftCollectionMembership(ownerPeerId: ownerPeerId, collectionId: collectionId, gifts: updatedGifts)
            guard self.saveLocked() else {
                self.collectionsCache = previousCollections
                self.cache = previousGifts
                return nil
            }
            self.publishLocked()
            return collection
        }
    }

    @discardableResult
    public func deleteLocalCollection(ownerPeerId: PeerId, collectionId: Int32) -> Bool {
        return self.queue.sync { () -> Bool in
            self.loadIfNeeded()
            guard !self.readOnly,
                  let index = self.collectionsCache.firstIndex(where: { $0.id == collectionId && $0.ownerPeerId == ownerPeerId.toInt64() }) else {
                return false
            }
            let previousCollections = self.collectionsCache
            let previousGifts = self.cache
            let collection = self.collectionsCache.remove(at: index)
            self.updateStoredFakeGiftCollectionMembership(ownerPeerId: ownerPeerId, collectionId: collectionId, gifts: collection.gifts, remove: true)
            guard self.saveLocked() else {
                self.collectionsCache = previousCollections
                self.cache = previousGifts
                return false
            }
            self.publishLocked()
            return true
        }
    }

    public func reorderLocalCollections(ownerPeerId: PeerId, ids: [Int32]) {
        self.queue.async {
            self.loadIfNeeded()
            guard !self.readOnly else {
                return
            }
            let ownerValue = ownerPeerId.toInt64()
            let ownerCollections = self.collectionsCache.filter { $0.ownerPeerId == ownerValue }
            let ownerMap = Dictionary(uniqueKeysWithValues: ownerCollections.map { ($0.id, $0) })
            var ordered = ids.compactMap { ownerMap[$0] }
            let included = Set(ordered.map(\.id))
            ordered.append(contentsOf: ownerCollections.filter { !included.contains($0.id) })
            var iterator = ordered.makeIterator()
            self.collectionsCache = self.collectionsCache.map { collection in
                collection.ownerPeerId == ownerValue ? (iterator.next() ?? collection) : collection
            }
            guard self.saveLocked() else {
                self.loadIfNeeded()
                return
            }
            self.publishLocked()
        }
    }

    @discardableResult
    public func updateFakeGiftCollectionMembership(ownerPeerId: PeerId, collectionId: Int32, references: [StarGiftReference], added: Bool) -> Bool {
        return self.queue.sync {
            self.loadIfNeeded()
            guard !self.readOnly else {
                return false
            }
            let ids = Set(references.compactMap { reference -> Int64? in
                guard case let .peer(peerId, savedId) = reference,
                      peerId == self.accountPeerId,
                      MiraFakeGift.isLocalSavedId(savedId) else {
                    return nil
                }
                return savedId
            })
            guard !ids.isEmpty else {
                return true
            }
            let previous = self.cache
            for index in self.cache.indices where ids.contains(self.cache[index].stableSavedId) {
                let storedOwner = self.cache[index].ownerPeerId ?? self.accountPeerId?.toInt64()
                guard let storedOwner, storedOwner == ownerPeerId.toInt64() else {
                    continue
                }
                if added {
                    if !self.cache[index].collectionIds.contains(collectionId) {
                        self.cache[index].collectionIds.append(collectionId)
                    }
                } else {
                    self.cache[index].collectionIds.removeAll(where: { $0 == collectionId })
                }
            }
            guard self.cache != previous else {
                return true
            }
            guard self.saveLocked() else {
                self.cache = previous
                return false
            }
            self.publishLocked()
            return true
        }
    }

    private func uniqueCollectionGifts(_ gifts: [ProfileGiftsContext.State.StarGift]) -> [ProfileGiftsContext.State.StarGift] {
        var seen = Set<String>()
        return gifts.filter { gift in
            guard let reference = gift.reference else {
                return false
            }
            return seen.insert(reference.stringValue).inserted
        }
    }

    private func updateStoredFakeGiftCollectionMembership(ownerPeerId: PeerId, collectionId: Int32, gifts: [ProfileGiftsContext.State.StarGift], remove: Bool = false) {
        let savedIds = Set(gifts.compactMap { gift -> Int64? in
            guard case let .peer(peerId, savedId)? = gift.reference,
                  peerId == self.accountPeerId,
                  MiraFakeGift.isLocalSavedId(savedId) else {
                return nil
            }
            return savedId
        })
        for index in self.cache.indices {
            let entryOwner = self.cache[index].ownerPeerId ?? self.accountPeerId?.toInt64()
            guard entryOwner == ownerPeerId.toInt64(), savedIds.contains(self.cache[index].stableSavedId) else {
                continue
            }
            if remove {
                self.cache[index].collectionIds.removeAll(where: { $0 == collectionId })
            } else if !self.cache[index].collectionIds.contains(collectionId) {
                self.cache[index].collectionIds.append(collectionId)
            }
        }
    }

    private func pruneDeletedFakeGiftsFromCollectionsLocked() {
        guard let accountPeerId = self.accountPeerId else {
            return
        }
        let entriesBySavedId = Dictionary(uniqueKeysWithValues: self.cache.map { ($0.stableSavedId, $0) })
        for collectionIndex in self.collectionsCache.indices {
            let ownerPeerId = self.collectionsCache[collectionIndex].ownerPeerId
            self.collectionsCache[collectionIndex].gifts.removeAll { gift in
                guard case let .peer(peerId, savedId)? = gift.reference,
                      peerId == accountPeerId,
                      MiraFakeGift.isLocalSavedId(savedId) else {
                    return false
                }
                guard let entry = entriesBySavedId[savedId] else {
                    return true
                }
                return (entry.ownerPeerId ?? accountPeerId.toInt64()) != ownerPeerId
            }
        }
    }

    public var isReadOnly: Bool {
        return self.queue.sync {
            self.loadIfNeeded()
            return self.readOnly
        }
    }

    public func add(_ gift: MiraFakeGift) {
        self.upsert(gift)
    }

    public func update(_ gift: MiraFakeGift) {
        self.upsert(gift)
    }

    /// Inserts a new entry or replaces the existing entry with the same stable id.
    /// Fake gift settings are edited from an asynchronous UI flow, so treating
    /// update as a strict "must already exist" operation can silently lose edits.
    public func upsert(_ gift: MiraFakeGift) {
        let normalizedGift = self.normalizedForStorage(gift)
        self.queue.async {
            self.loadIfNeeded()
            guard !self.readOnly else { return }
            if let index = self.cache.firstIndex(where: { $0.id == normalizedGift.id }) {
                self.cache[index] = normalizedGift
            } else {
                self.cache.append(normalizedGift)
            }
            self.saveLocked()
            self.publishLocked()
        }
    }

    /// Persists an upsert and completes only after the atomic JSON write has
    /// finished.  Transfer/conversion workflows use this barrier before
    /// deleting their source entry so a process interruption cannot lose the
    /// recipient copy after the source has been removed.
    private func upsertSignal(_ gift: MiraFakeGift) -> Signal<Void, NoError> {
        let normalizedGift = self.normalizedForStorage(gift)
        return Signal { [weak self] subscriber in
            guard let self else {
                subscriber.putCompletion()
                return EmptyDisposable
            }
            self.queue.async {
                self.loadIfNeeded()
                guard !self.readOnly else {
                    subscriber.putCompletion()
                    return
                }
                if let index = self.cache.firstIndex(where: { $0.id == normalizedGift.id }) {
                    self.cache[index] = normalizedGift
                } else {
                    self.cache.append(normalizedGift)
                }
                self.saveLocked()
                self.publishLocked()
                subscriber.putCompletion()
            }
            return EmptyDisposable
        }
    }

    /// Persists a gift before returning.  Most UI edits can use the
    /// asynchronous `upsert`, but multi-step operations such as a local NFT
    /// transfer must make the recipient record durable before removing the
    /// source record.  Keeping this on the store queue also preserves the
    /// same idempotent replacement semantics as `upsert`.
    @discardableResult
    public func upsertAndWait(_ gift: MiraFakeGift) -> Bool {
        let normalizedGift = self.normalizedForStorage(gift)
        return self.queue.sync {
            self.loadIfNeeded()
            guard !self.readOnly else { return false }
            let previousCache = self.cache
            if let index = self.cache.firstIndex(where: { $0.id == normalizedGift.id }) {
                // A pending transfer intent is a compare-and-set value. Two
                // UI taps can race before either callback returns; once the
                // first tap binds a recipient, a second tap may only replay
                // that same recipient and cannot redirect the gift.
                let existing = self.cache[index]
                if let existingRecipient = existing.pendingTransferRecipientPeerId,
                   existingRecipient != normalizedGift.pendingTransferRecipientPeerId {
                    return false
                }
                self.cache[index] = normalizedGift
            } else {
                self.cache.append(normalizedGift)
            }
            guard self.saveLocked() else {
                self.cache = previousCache
                return false
            }
            self.publishLocked()
            return true
        }
    }

    public func remove(id: String) {
        self.queue.async {
            self.loadIfNeeded()
            guard !self.readOnly else { return }
            self.cache.removeAll(where: { $0.id == id })
            self.pruneDeletedFakeGiftsFromCollectionsLocked()
            self.saveLocked()
            self.publishLocked()
        }
    }

    /// Removes an entry and completes after the durable write.  Keeping this
    /// separate from the fire-and-forget UI helper makes multi-step local
    /// operations restart-safe.
    private func removeSignal(id: String) -> Signal<Void, NoError> {
        return Signal { [weak self] subscriber in
            guard let self else {
                subscriber.putCompletion()
                return EmptyDisposable
            }
            self.queue.async {
                self.loadIfNeeded()
                guard !self.readOnly else {
                    subscriber.putCompletion()
                    return
                }
                let previousCount = self.cache.count
                let previousCollections = self.collectionsCache
                self.cache.removeAll(where: { $0.id == id })
                if self.cache.count != previousCount {
                    self.pruneDeletedFakeGiftsFromCollectionsLocked()
                    self.saveLocked()
                    self.publishLocked()
                } else {
                    self.collectionsCache = previousCollections
                }
                subscriber.putCompletion()
            }
            return EmptyDisposable
        }
    }

    /// Removes one entry and waits until the new snapshot is durable. This is
    /// used only by multi-step local transfers; ordinary UI cleanup remains
    /// asynchronous.
    @discardableResult
    public func removeAndWait(id: String) -> Bool {
        return self.queue.sync {
            self.loadIfNeeded()
            guard !self.readOnly else { return false }
            let previousCache = self.cache
            let previousCollections = self.collectionsCache
            self.cache.removeAll(where: { $0.id == id })
            guard self.cache != previousCache else { return true }
            self.pruneDeletedFakeGiftsFromCollectionsLocked()
            guard self.saveLocked() else {
                self.cache = previousCache
                self.collectionsCache = previousCollections
                return false
            }
            self.publishLocked()
            return true
        }
    }

    /// Removes local gift records whose Postbox action was deleted. The
    /// message row and this durable projection are intentionally cleaned up
    /// together so a normal chat delete cannot resurrect the gift on restart.
    public func remove(chatMessageIds: Set<MessageId>) {
        guard !chatMessageIds.isEmpty else {
            return
        }
        self.queue.async {
            self.loadIfNeeded()
            guard !self.readOnly else { return }
            let previousCount = self.cache.count
            self.cache.removeAll { entry in
                guard let packedPeerId = entry.chatMessagePeerId,
                      let messageId = entry.chatMessageId,
                      let peerId = MiraMessageHistoryStore.peerId(fromPackedValue: packedPeerId) else {
                    return false
                }
                return chatMessageIds.contains(MessageId(peerId: peerId, namespace: Namespaces.Message.Local, id: messageId))
            }
            guard self.cache.count != previousCount else {
                return
            }
            self.pruneDeletedFakeGiftsFromCollectionsLocked()
            self.saveLocked()
            self.publishLocked()
        }
    }

    public func updateSnapshot(id: String, snapshot: StarGift) {
        self.queue.async {
            self.loadIfNeeded()
            guard !self.readOnly else { return }
            if let index = self.cache.firstIndex(where: { $0.id == id }), self.cache[index].giftSnapshot == nil {
                self.cache[index].giftSnapshot = snapshot
                self.saveLocked()
                self.publishLocked()
            }
        }
    }

    /// Returns true when a saved-gift reference belongs to this local store.
    /// Synthetic gifts must never be sent to the Telegram payments API: their
    /// saved ids only exist in the local profile projection.
    public func isLocalReference(_ reference: StarGiftReference, accountPeerId: PeerId) -> Bool {
        guard case let .peer(peerId, savedId) = reference, peerId == accountPeerId else {
            return false
        }
        // Keep stale references local after deletion as well: an already-open
        // gift sheet must not send its synthetic id to the payments API.
        return MiraFakeGift.isLocalSavedId(savedId)
    }

    /// Returns whether a Postbox local message is owned by the fake-gift
    /// projection. Telegram also uses the Local namespace for its own
    /// service rows, so callers must not treat every Local message as fake.
    public func isLocalChatMessage(_ messageId: MessageId) -> Bool {
        guard messageId.namespace == Namespaces.Message.Local else {
            return false
        }
        return self.queue.sync {
            self.loadIfNeeded()
            return self.cache.contains { entry in
                guard let packedPeerId = entry.chatMessagePeerId,
                      let peerId = MiraMessageHistoryStore.peerId(fromPackedValue: packedPeerId),
                      let chatMessageId = entry.chatMessageId else {
                    return false
                }
                return MessageId(peerId: peerId, namespace: Namespaces.Message.Local, id: chatMessageId) == messageId
            }
        }
    }

    public func localChatMessageIds() -> Set<MessageId> {
        return self.queue.sync {
            self.loadIfNeeded()
            var result = Set<MessageId>()
            result.reserveCapacity(self.cache.count)
            for entry in self.cache {
                guard let packedPeerId = entry.chatMessagePeerId,
                      let peerId = MiraMessageHistoryStore.peerId(fromPackedValue: packedPeerId),
                      let messageId = entry.chatMessageId else {
                    continue
                }
                result.insert(MessageId(peerId: peerId, namespace: Namespaces.Message.Local, id: messageId))
            }
            return result
        }
    }

    /// Applies a local profile change without touching the network.
    public func updateLocalReference(_ reference: StarGiftReference, accountPeerId: PeerId, added: Bool? = nil, pinned: Bool? = nil) {
        guard case let .peer(peerId, savedId) = reference, peerId == accountPeerId else {
            return
        }
        self.queue.async {
            self.loadIfNeeded()
            guard !self.readOnly else { return }
            guard let index = self.cache.firstIndex(where: { $0.stableSavedId == savedId }) else {
                return
            }
            var gift = self.cache[index]
            if let added {
                gift.isHidden = !added
                if !added {
                    gift.isSaved = false
                }
            }
            if let pinned {
                gift.isSaved = pinned
                if pinned {
                    gift.isHidden = false
                }
            }
            guard gift != self.cache[index] else {
                return
            }
            self.cache[index] = gift
            self.saveLocked()
            self.publishLocked()
        }
    }

    public func clear() {
        self.queue.async {
            self.loadIfNeeded()
            guard !self.readOnly else { return }
            self.didLoad = true
            self.cache.removeAll()
            self.collectionsCache.removeAll()
            try? FileManager.default.removeItem(atPath: self.filePath)
            self.publishLocked()
        }
    }

    /// Clears fake gifts and their local-only chat projections together. The
    /// plain `clear()` method remains for callers that only need to reset data.
    public func clear(account: Account) {
        guard !self.isReadOnly else {
            return
        }
        let entries = self.list()
        let messageIds = entries.compactMap { entry -> MessageId? in
            guard let value = entry.chatMessagePeerId, let peerId = MiraMessageHistoryStore.peerId(fromPackedValue: value), let id = entry.chatMessageId else {
                return nil
            }
            return MessageId(peerId: peerId, namespace: Namespaces.Message.Local, id: id)
        }
        let _ = account.postbox.transaction { transaction in
            if !messageIds.isEmpty {
                transaction.deleteMessages(messageIds, forEachMedia: nil)
            }
        }.start(completed: { [weak self] in
            self?.clear()
        })
    }
}

extension MiraFakeGiftsStore {
    public func resolvedProfileGifts(account: Account) -> Signal<[ProfileGiftsContext.State.StarGift], NoError> {
        return self.resolvedProfileGifts(account: account, entries: self.list(), ownerPeerId: account.peerId)
    }

    public func resolvedProfileGifts(account: Account, entries: [MiraFakeGift]) -> Signal<[ProfileGiftsContext.State.StarGift], NoError> {
        return self.resolvedProfileGifts(account: account, entries: entries, ownerPeerId: account.peerId)
    }

    /// Resolves local gifts for the profile currently being viewed. The store
    /// is account-local, but a fake transfer can assign ownership to another
    /// peer on this device; filtering by the requested profile keeps the
    /// recipient's gift shelf and the account's own shelf consistent.
    public func resolvedProfileGifts(account: Account, entries: [MiraFakeGift], ownerPeerId: PeerId, collectionId: Int32? = nil) -> Signal<[ProfileGiftsContext.State.StarGift], NoError> {
        let ownedEntries = entries.filter { entry in
            guard let storedOwnerPeerId = entry.ownerPeerId else {
                return ownerPeerId == account.peerId
            }
            guard let owner = MiraFakeGift.peerId(fromStoredValue: storedOwnerPeerId, isPacked: true) else {
                return false
            }
            guard owner == ownerPeerId else {
                return false
            }
            if let collectionId {
                return entry.collectionIds.contains(collectionId)
            }
            return true
        }
        if ownedEntries.isEmpty {
            return .single([])
        }
        return combineLatest(ownedEntries.map { self.resolveEntry($0, account: account) })
        |> map { values in
            return values.compactMap { $0 }
        }
    }

    private func resolveEntry(_ entry: MiraFakeGift, account: Account) -> Signal<ProfileGiftsContext.State.StarGift?, NoError> {
        let giftSignal: Signal<StarGift?, NoError>
        if let snapshot = entry.giftSnapshot {
            giftSignal = .single(snapshot)
        } else {
            switch entry.kind {
            case .regular:
                if let giftId = entry.giftId {
                    giftSignal = _internal_cachedStarGifts(postbox: account.postbox)
                    |> take(1)
                    |> map { list -> StarGift? in
                        return list?.items.first(where: { $0.giftId == giftId })
                    }
                } else {
                    giftSignal = .single(nil)
                }
            case .uniqueBySlug:
                if let slug = entry.slug, !slug.isEmpty {
                    giftSignal = _internal_getUniqueStarGift(account: account, slug: slug)
                    |> map { gift -> StarGift? in
                        return .unique(gift)
                    }
                    |> `catch` { _ -> Signal<StarGift?, NoError> in
                        // A local fake gift must remain inspectable while the
                        // catalog is unavailable. Keep the stored slug and
                        // number visible through the same local-only
                        // projection used by uniqueById entries.
                        return .single(self.offlineUniqueGift(for: entry, account: account))
                    }
                } else {
                    giftSignal = .single(nil)
                }
            case .uniqueById:
                // Older local entries can contain only the collectible ids.
                // Keep them visible without a network request by projecting a
                // minimal Telegram-shaped unique gift.  It intentionally has
                // no media attributes or server actions; the local profile
                // and chat can still render the title/number and retain the
                // synthetic reference while offline.
                giftSignal = .single(self.offlineUniqueGift(for: entry, account: account))
            }
        }

        return giftSignal
        |> mapToSignal { gift -> Signal<ProfileGiftsContext.State.StarGift?, NoError> in
            guard let gift else {
                return .single(nil)
            }
            let shouldCacheResolvedSnapshot: Bool
            switch entry.kind {
            case .regular:
                shouldCacheResolvedSnapshot = true
            case .uniqueBySlug:
                // The offline fallback uses the stable local reference id;
                // never persist that placeholder over a missing server
                // snapshot, otherwise a later reconnect could not refresh it.
                // A resolved server gift is cacheable; the deterministic
                // offline fallback must not be written over the local
                // reference or it would hide catalog data after reconnect.
                shouldCacheResolvedSnapshot = gift != self.offlineUniqueGift(for: entry, account: account)
            case .uniqueById:
                shouldCacheResolvedSnapshot = false
            }
            if entry.giftSnapshot == nil && shouldCacheResolvedSnapshot {
                self.updateSnapshot(id: entry.id, snapshot: gift)
            }
            return account.postbox.transaction { transaction -> ProfileGiftsContext.State.StarGift in
                var fromPeer: EnginePeer?
                if let fromPeerId = entry.fromPeerId, let normalizedPeerId = MiraFakeGift.peerId(fromStoredValue: fromPeerId, isPacked: entry.fromPeerIdIsPacked) {
                    fromPeer = transaction.getPeer(normalizedPeerId).flatMap { EnginePeer($0) }
                }
                if entry.fromPeerIdIsPacked == nil, let rawId = entry.fromPeerId, let userId = MiraFakeGift.peerId(fromStoredValue: rawId, isPacked: false), let user = transaction.getPeer(userId).flatMap(EnginePeer.init), case .user = user {
                    fromPeer = user
                }

                // A gift sender is rendered as a user in Telegram's gift
                // bubble. Treat groups/channels/secret chats as unresolved so
                // a malformed sender id cannot produce an invalid local
                // message author or peer projection.
                if let resolvedFromPeer = fromPeer {
                    switch resolvedFromPeer {
                    case .user:
                        break
                    case .legacyGroup, .channel, .community, .secretChat:
                        fromPeer = nil
                    }
                }
                var projectedGift = gift
                if case let .unique(uniqueGift) = gift {
                    let ownerPeerId = entry.ownerPeerId.flatMap { MiraFakeGift.peerId(fromStoredValue: $0, isPacked: true) } ?? account.peerId
                    // `originalInfo` is server-authored gift metadata. Do not
                    // synthesize it from the local editor's sender/caption:
                    // Telegram legitimately omits the signature for private or
                    // transferred gifts, and the UI should preserve that fact.
                    let attributes = uniqueGift.attributes
                    // Keep Telegram's model/pattern/backdrop assets and its
                    // originalInfo exactly as received. Ownership is carried
                    // by the unique-gift owner field below.
                    projectedGift = .unique(StarGift.UniqueGift(
                        id: uniqueGift.id, giftId: uniqueGift.giftId, title: uniqueGift.title, number: uniqueGift.number, slug: uniqueGift.slug,
                        owner: .peerId(ownerPeerId), attributes: attributes, availability: uniqueGift.availability,
                        giftAddress: nil, resellAmounts: nil, resellForTonOnly: false, releasedBy: uniqueGift.releasedBy,
                        valueAmount: uniqueGift.valueAmount, valueCurrency: uniqueGift.valueCurrency, valueUsdAmount: uniqueGift.valueUsdAmount,
                        flags: uniqueGift.flags, themePeerId: uniqueGift.themePeerId, peerColor: uniqueGift.peerColor, hostPeerId: nil,
                        minOfferStars: nil, craftChancePermille: uniqueGift.craftChancePermille
                    ))
                }
                let reference: StarGiftReference
                switch gift {
                case .unique:
                    // Both regular and unique fake gifts are local objects.
                    // A slug reference would be interpreted as a real server
                    // gift by GiftViewScreen and could trigger network actions.
                    reference = .peer(peerId: account.peerId, id: entry.stableSavedId)
                case .generic:
                    reference = .peer(peerId: account.peerId, id: entry.stableSavedId)
                }
                // Keep the server-provided values for ordinary gifts.  These
                // values drive Telegram's "keep or convert" copy and the
                // conversion action; leaving them nil made local regular
                // gifts look like NFTs and silently removed that UI.
                let genericGift: StarGift.Gift? = {
                    if case let .generic(genericGift) = projectedGift {
                        return genericGift
                    }
                    return nil
                }()
                return ProfileGiftsContext.State.StarGift(
                    gift: projectedGift,
                    reference: reference,
                    fromPeer: fromPeer,
                    date: entry.date,
                    text: entry.caption,
                    entities: nil,
                    nameHidden: false,
                    savedToProfile: !entry.isHidden || entry.isSaved,
                    pinnedToTop: entry.isSaved,
                    convertStars: genericGift.flatMap { $0.convertStars > 0 ? $0.convertStars : nil },
                    canUpgrade: genericGift?.upgradeStars != nil,
                    canExportDate: nil,
                    upgradeStars: genericGift?.upgradeStars,
                    // Local NFTs use the same 25-Star transfer price as a
                    // Telegram NFT. The synthetic reference still stays
                    // account-local and never reaches the payments API.
                    transferStars: entry.isUnique ? (entry.transferStars ?? MiraFakeGift.defaultNFTTransferStars) : nil,
                    canTransferDate: nil,
                    canResaleDate: nil,
                    collectionIds: entry.collectionIds.isEmpty ? nil : entry.collectionIds,
                    prepaidUpgradeHash: nil,
                    upgradeSeparate: false,
                    dropOriginalDetailsStars: nil,
                    number: {
                        if case let .unique(uniqueGift) = projectedGift {
                            return uniqueGift.number
                        }
                        return nil
                    }(),
                    isRefunded: false,
                    canCraftAt: nil
                )
            }
        }
    }

    /// Builds a deterministic placeholder for a persisted unique gift whose
    /// server snapshot is unavailable.  This is a local projection only: no
    /// catalog metadata, media, ownership signature or network action is
    /// invented beyond the ids already stored in the fake-gift record.
    private func offlineUniqueGift(for entry: MiraFakeGift, account: Account) -> StarGift {
        let identifier = entry.giftId ?? entry.stableSavedId
        let slug = entry.slug ?? ""
        let title = slug.isEmpty ? "Collectible Gift" : slug
        let number = entry.uniqueNumber ?? 0
        let ownerPeerId = entry.ownerPeerId.flatMap { MiraFakeGift.peerId(fromStoredValue: $0, isPacked: true) } ?? account.peerId
        return .unique(StarGift.UniqueGift(
            id: identifier,
            giftId: identifier,
            title: title,
            number: number,
            slug: slug,
            owner: .peerId(ownerPeerId),
            attributes: [],
            availability: StarGift.UniqueGift.Availability(issued: 0, total: 0),
            giftAddress: nil,
            resellAmounts: nil,
            resellForTonOnly: false,
            releasedBy: nil,
            valueAmount: nil,
            valueCurrency: nil,
            valueUsdAmount: nil,
            flags: [],
            themePeerId: nil,
            peerColor: nil,
            hostPeerId: nil,
            minOfferStars: nil,
            craftChancePermille: nil
        ))
    }
}

extension MiraFakeGiftsStore {
    // Inserts a local-only "gift received" action message (same TelegramMediaAction payload as a real one)
    // into the sender's chat, or into Saved Messages when there is no resolvable sender.
    // Returns the entry updated with chatMessagePeerId/chatMessageId for later deletion.
    public func insertChatMessage(account: Account, entry: MiraFakeGift, forcedChatPeerId: PeerId? = nil) -> Signal<MiraFakeGift, NoError> {
        // A persisted entry can outlive its Postbox message (for example after
        // history cleanup, an interrupted migration, or a previous build that
        // used a different local id). Do not trust the cached id blindly: a
        // missing message leaves the chat list with a stale projection and the
        // next fake-gift edit can never repair it.
        if let chatMessageId = entry.chatMessageId,
           let storedPeerId = entry.chatMessagePeerId,
           let chatMessagePeerId = MiraMessageHistoryStore.peerId(fromPackedValue: storedPeerId) {
            let messageId = MessageId(peerId: chatMessagePeerId, namespace: Namespaces.Message.Local, id: chatMessageId)
            return account.postbox.transaction { transaction -> Bool in
                return transaction.getMessage(messageId)?.globallyUniqueId == entry.stableSavedId
            }
            |> mapToSignal { exists -> Signal<MiraFakeGift, NoError> in
                if exists {
                    return .single(entry)
                }
                var repairedEntry = entry
                repairedEntry.chatMessagePeerId = nil
                repairedEntry.chatMessageId = nil
                // Preserve the destination selected by a local transfer when
                // repairing a missing Postbox row after restart. Dropping it
                // here silently re-routes the gift to Saved Messages.
                return self.insertChatMessage(account: account, entry: repairedEntry, forcedChatPeerId: forcedChatPeerId)
            }
        } else if entry.chatMessageId != nil || entry.chatMessagePeerId != nil {
            // Clear malformed legacy references before attempting a fresh
            // insertion. This also prevents invalid packed PeerIds from
            // reaching Postbox's debug assertions.
            var repairedEntry = entry
            repairedEntry.chatMessagePeerId = nil
            repairedEntry.chatMessageId = nil
            return self.insertChatMessage(account: account, entry: repairedEntry, forcedChatPeerId: forcedChatPeerId)
        }
        return self.resolveEntry(entry, account: account)
        |> mapToSignal { resolved -> Signal<MiraFakeGift, NoError> in
            guard let resolved else {
                return .single(entry)
            }
            var entry = entry
            return account.postbox.transaction { transaction -> MiraFakeGift in
                var fromPeer: EnginePeer?
                if let fromPeerId = entry.fromPeerId, let normalizedPeerId = MiraFakeGift.peerId(fromStoredValue: fromPeerId, isPacked: entry.fromPeerIdIsPacked) {
                    fromPeer = transaction.getPeer(normalizedPeerId).flatMap { EnginePeer($0) }
                }
                if entry.fromPeerIdIsPacked == nil, let rawId = entry.fromPeerId, let userId = MiraFakeGift.peerId(fromStoredValue: rawId, isPacked: false), let user = transaction.getPeer(userId).flatMap(EnginePeer.init), case .user = user {
                    fromPeer = user
                }

                if let resolvedFromPeer = fromPeer {
                    switch resolvedFromPeer {
                    case .user:
                        break
                    case .legacyGroup, .channel, .community, .secretChat:
                        fromPeer = nil
                    }
                }

                let chatPeerId: PeerId
                let authorId: PeerId
                if let forcedChatPeerId {
                    // Transfers are authored by the local account but belong
                    // in the selected recipient chat, not Saved Messages.
                    chatPeerId = forcedChatPeerId
                    authorId = account.peerId
                } else if let fromPeer, fromPeer.id != account.peerId {
                    chatPeerId = fromPeer.id
                    authorId = fromPeer.id
                } else {
                    chatPeerId = account.peerId
                    authorId = fromPeer?.id ?? account.peerId
                }

                let senderId: EnginePeer.Id? = authorId == account.peerId ? nil : authorId
                let action: TelegramMediaActionType
                switch resolved.gift {
                case .generic:
                    let genericGift: StarGift.Gift? = {
                        if case let .generic(value) = resolved.gift {
                            return value
                        }
                        return nil
                    }()
                    action = .starGift(
                        gift: resolved.gift,
                        // Preserve the catalog's conversion value in the
                        // action message as well as in the profile projection.
                        // GiftViewScreen reads this field when opened from a
                        // chat, so fake regular gifts behave like Telegram
                        // gifts in both entry points.
                        convertStars: genericGift.flatMap { $0.convertStars > 0 ? $0.convertStars : nil },
                        text: entry.caption,
                        entities: nil,
                        nameHidden: false,
                        savedToProfile: !entry.isHidden || entry.isSaved,
                        converted: false,
                        upgraded: false,
                        canUpgrade: genericGift?.upgradeStars != nil,
                        upgradeStars: genericGift?.upgradeStars,
                        isRefunded: false,
                        isPrepaidUpgrade: false,
                        upgradeMessageId: nil,
                        peerId: account.peerId,
                        senderId: senderId,
                        savedId: entry.stableSavedId,
                        prepaidUpgradeHash: nil,
                        giftMessageId: nil,
                        upgradeSeparate: false,
                        isAuctionAcquired: false,
                        toPeerId: nil,
                        number: nil
                    )
                case .unique:
                    let ownerPeerId = entry.ownerPeerId.flatMap { MiraFakeGift.peerId(fromStoredValue: $0, isPacked: true) } ?? account.peerId
                    action = .starGiftUnique(
                        gift: resolved.gift,
                        isUpgrade: false,
                        isTransferred: forcedChatPeerId != nil,
                        savedToProfile: !entry.isHidden || entry.isSaved,
                        canExportDate: nil,
                        transferStars: entry.isUnique ? (entry.transferStars ?? MiraFakeGift.defaultNFTTransferStars) : nil,
                        isRefunded: false,
                        isPrepaidUpgrade: false,
                        peerId: ownerPeerId,
                        senderId: senderId,
                        savedId: entry.stableSavedId,
                        resaleAmount: nil,
                        canTransferDate: nil,
                        canResaleDate: nil,
                        dropOriginalDetailsStars: nil,
                        assigned: true,
                        fromOffer: false,
                        canCraftAt: nil,
                        isCrafted: false
                    )
                }

                var flags = StoreMessageFlags()
                if authorId != account.peerId {
                    flags.insert(.Incoming)
                }
                let message = StoreMessage(
                    peerId: chatPeerId,
                    namespace: Namespaces.Message.Local,
                    customStableId: nil,
                    globallyUniqueId: entry.stableSavedId,
                    groupingKey: nil,
                    threadId: nil,
                    timestamp: entry.date,
                    flags: flags,
                    tags: [],
                    globalTags: [],
                    localTags: [],
                    forwardInfo: nil,
                    authorId: authorId,
                    text: "",
                    attributes: [],
                    media: [TelegramMediaAction(action: action)]
                )
                // If an earlier process was interrupted after adding the
                // Postbox row but before persisting its ids, the cached
                // reference is empty and a retry would otherwise leave two
                // identical gift actions in the chat. Remove only our local
                // stable-id projection before inserting the replacement.
                var staleMessageIds: [MessageId] = []
                transaction.withAllMessages(peerId: chatPeerId, namespace: Namespaces.Message.Local) { existingMessage in
                    if existingMessage.globallyUniqueId == entry.stableSavedId {
                        staleMessageIds.append(existingMessage.id)
                    }
                    return true
                }
                if !staleMessageIds.isEmpty {
                    transaction.deleteMessages(staleMessageIds, forEachMedia: nil)
                }
                let mapping = transaction.addMessages([message], location: .Random)
                if let messageId = mapping[entry.stableSavedId] {
                    entry.chatMessagePeerId = messageId.peerId.toInt64()
                    entry.chatMessageId = messageId.id
                }
                if [Namespaces.Peer.CloudUser, Namespaces.Peer.CloudGroup, Namespaces.Peer.CloudChannel].contains(chatPeerId.namespace),
                   transaction.getPeer(chatPeerId) != nil,
                   case .notIncluded = transaction.getPeerChatListInclusion(chatPeerId) {
                    transaction.updatePeerChatListInclusion(chatPeerId, inclusion: .ifHasMessagesOrOneOf(groupId: .root, pinningIndex: nil, minTimestamp: nil))
                }
                return entry
            }
        }
    }

    public func deleteChatMessageSignal(account: Account, entry: MiraFakeGift) -> Signal<Void, NoError> {
        guard let chatMessageId = entry.chatMessageId, let storedPeerId = entry.chatMessagePeerId, let chatMessagePeerId = MiraMessageHistoryStore.peerId(fromPackedValue: storedPeerId) else {
            return .single(())
        }
        return account.postbox.transaction { transaction in
            transaction.deleteMessages([MessageId(peerId: chatMessagePeerId, namespace: Namespaces.Message.Local, id: chatMessageId)], forEachMedia: nil)
        }
    }

    public func deleteChatMessage(account: Account, entry: MiraFakeGift) {
        let _ = self.deleteChatMessageSignal(account: account, entry: entry).start()
    }

    /// Converts a local regular gift without ever sending its synthetic
    /// reference to Telegram. The chat projection and profile entry are
    /// removed together so a conversion cannot leave a stale gift bubble.
    public func convertLocalReference(account: Account, reference: StarGiftReference) {
        guard case let .peer(peerId, savedId) = reference,
              peerId == account.peerId,
              MiraFakeGift.isLocalSavedId(savedId) else {
            return
        }
        let entry = self.list().first(where: { $0.stableSavedId == savedId })
        if let entry {
            // A regular gift can be converted only when its catalog snapshot
            // contains the authoritative conversion value. Do not remove a
            // profile item on a partially loaded/legacy entry: doing so would
            // lose the gift without crediting the local Stars ledger.
            guard !entry.isUnique,
                  case let .generic(gift)? = entry.giftSnapshot,
                   gift.convertStars > 0,
                  account.miraFakeStarsLedger.recordGiftConversion(
                      id: entry.id,
                      peerId: account.peerId.toInt64(),
                      stars: gift.convertStars,
                      date: entry.date
                  ) else {
                return
            }
            let _ = self.deleteChatMessageSignal(account: account, entry: entry).start(completed: { [weak self] in
                self?.remove(id: entry.id)
            })
        } else {
            self.queue.async { [weak self] in
                self?.loadIfNeeded()
                self?.cache.removeAll(where: { $0.stableSavedId == savedId })
                self?.pruneDeletedFakeGiftsFromCollectionsLocked()
                self?.saveLocked()
                self?.publishLocked()
            }
        }
    }

    /// Moves a local fake NFT into the recipient's local chat. The operation is
    /// deliberately account-local: no synthetic reference is sent to Telegram
    /// and the original profile entry is removed only after its chat projection
    /// has been deleted.
    public func transferLocalReference(account: Account, reference: StarGiftReference, recipientPeerId: PeerId) -> Signal<Never, TransferStarGiftError> {
        guard case let .peer(peerId, savedId) = reference,
              peerId == account.peerId,
              MiraFakeGift.isLocalSavedId(savedId),
              let source = self.list().first(where: { $0.stableSavedId == savedId }),
              source.isUnique else {
            return .fail(.generic)
        }
        // A persisted uniqueById entry may not have a catalog snapshot after
        // restart or while offline. Use the same deterministic local
        // projection as the profile path so transfer still produces a
        // Telegram-shaped local action and remains fully account-local.
        let resolvedSnapshot = source.giftSnapshot ?? self.offlineUniqueGift(for: source, account: account)
        let transferFee = max(MiraFakeGift.defaultNFTTransferStars, source.transferStars ?? MiraFakeGift.defaultNFTTransferStars)
        let recipientValue = recipientPeerId.toInt64()
        if let pendingRecipient = source.pendingTransferRecipientPeerId, pendingRecipient != recipientValue {
            return .fail(.generic)
        }
        let transferPrefix = "\(source.id):transfer:"
        let transferId = "\(transferPrefix)\(recipientValue)"

        // A transfer is staged before the ledger debit. If the process stops
        // at any point in that window, the source remains visible and the
        // staged destination is the durable intent. Refuse a retry aimed at a
        // different recipient so an interrupted local transfer cannot fork
        // into two owners.
        let stagedTransfers = self.list().filter { $0.id.hasPrefix(transferPrefix) }
        guard stagedTransfers.allSatisfy({ $0.id == transferId }) else {
            return .fail(.generic)
        }

        // Bind the source before writing the destination/ledger. This is the
        // durable intent that makes a process interruption retryable without
        // allowing a later tap to select another recipient.
        var stagedSource = source
        stagedSource.pendingTransferRecipientPeerId = recipientValue
        guard self.upsertAndWait(stagedSource) else {
            return .fail(.generic)
        }

        // The ledger is durable independently of the gift JSON. A crash after
        // the debit but before source cleanup must be resumable for the same
        // recipient and must never be redirected to another peer.
        let existingLedgerEntry = account.miraFakeStarsLedger.snapshot().entries.reversed().first {
            $0.kind == .fakeGiftTransfer && $0.relatedId == source.id
        }
        if let existingLedgerEntry {
            guard existingLedgerEntry.peerId == recipientValue else {
                return .fail(.generic)
            }
        }

        var transferred = source
        transferred.giftSnapshot = resolvedSnapshot
        transferred.id = transferId
        transferred.fromPeerId = account.peerId.toInt64()
        transferred.fromPeerIdIsPacked = true
        transferred.ownerPeerId = recipientValue
        transferred.pendingTransferRecipientPeerId = nil
        transferred.fromName = nil
        // A transfer creates a fresh recipient-side gift.  Do not carry the
        // sender's profile presentation state into that copy: a hidden gift
        // on the sender must not arrive in the recipient's Hidden section,
        // and sender-owned collection ids must never leak to another profile.
        transferred.isHidden = false
        transferred.isSaved = false
        transferred.collectionIds = []
        transferred.date = Int32(clamping: Int64(CFAbsoluteTimeGetCurrent() + NSTimeIntervalSince1970))
        transferred.chatMessagePeerId = nil
        transferred.chatMessageId = nil
        transferred.showInChat = true
        // Persist the recipient projection before deleting the source. This
        // ordering makes a crash recoverable: a retry finds the same transfer
        // id, replaces its chat row, and then removes the source.
        return (self.insertChatMessage(account: account, entry: transferred, forcedChatPeerId: recipientPeerId) |> castError(TransferStarGiftError.self))
        |> mapToSignal { [weak self] inserted -> Signal<Never, TransferStarGiftError> in
            guard let self else {
                return .complete()
            }
            // The source must remain until the recipient projection is
            // durably persisted. If the process stops after this point, a
            // retry sees the deterministic transfer id and can safely finish
            // cleanup without charging the fee twice.
            // Keep a transient offline placeholder out of durable storage so
            // the recipient gift can refresh from Telegram after reconnect.
            var durableInserted = inserted
            if source.giftSnapshot == nil {
                durableInserted.giftSnapshot = nil
            }
            guard self.upsertAndWait(durableInserted) else {
                return .fail(.generic)
            }
            // Charge only after the recipient snapshot is durable. Ledger
            // writes are idempotent by source id, so a retry after an
            // interruption cannot charge twice.
            guard account.miraFakeStarsLedger.recordGiftTransfer(
                id: source.id,
                peerId: recipientValue,
                fee: transferFee,
                date: Int32(clamping: Int64(CFAbsoluteTimeGetCurrent() + NSTimeIntervalSince1970))
            ) else {
                // Insufficient local Stars must leave the source untouched
                // and remove the staged recipient projection.
                let rollbackMessage = self.deleteChatMessageSignal(account: account, entry: inserted)
                return ((rollbackMessage |> castError(TransferStarGiftError.self)) |> mapToSignal { _ -> Signal<Never, TransferStarGiftError> in
                    guard self.removeAndWait(id: inserted.id) else {
                        return .fail(.generic)
                    }
                    // The pending recipient is only a durable intent while a
                    // transfer is being committed. If the Stars debit fails,
                    // clear it so the owner can retry with another recipient
                    // after topping up the local balance.
                    guard self.upsertAndWait(source) else {
                        return .fail(.generic)
                    }
                    return .fail(.generic)
                })
            }
            let remove = self.deleteChatMessageSignal(account: account, entry: source)
            return (remove |> castError(TransferStarGiftError.self))
            |> mapToSignal { _ -> Signal<Never, TransferStarGiftError> in
                guard self.removeAndWait(id: source.id) else {
                    return .fail(.generic)
                }
                return .complete()
            }
        }
    }
}
