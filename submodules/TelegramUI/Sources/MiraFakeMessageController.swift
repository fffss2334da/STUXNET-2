import Foundation
import UIKit
import AVFoundation
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import AccountContext
import ItemListUI
import ItemListDatePickerItem
import PresentationDataUtils
import MediaPickerUI
import LegacyMediaPickerUI

private func miraFakeMediaUseTelegramGallery(_ kind: FakeMessageKind) -> Bool {
    return kind == .photo || kind == .video || kind == .sticker
}

private func miraFakeMediaFileURL(_ media: Media) -> URL? {
    let resources: [TelegramMediaResource]
    if let image = media as? TelegramMediaImage, let representation = largestImageRepresentation(image.representations) {
        resources = [representation.resource]
    } else if let file = media as? TelegramMediaFile {
        resources = [file.resource]
    } else {
        return nil
    }
    for resource in resources {
        if let localResource = resource as? LocalFileReferenceMediaResource,
           FileManager.default.fileExists(atPath: localResource.localFilePath) {
            return URL(fileURLWithPath: localResource.localFilePath)
        }
    }
    return nil
}

private func miraFakeMediaDocumentTypes(_ kind: FakeMessageKind) -> [String] {
    switch kind {
    case .photo:
        return ["public.image"]
    case .video:
        return ["public.movie", "public.video"]
    case .audio, .voice:
        return ["public.audio"]
    case .sticker:
        return ["com.compuserve.gif", "public.image"]
    case .file:
        return ["public.item"]
    default:
        return ["public.item"]
    }
}

private func miraFakeMediaMimeType(_ pathExtension: String, kind: FakeMessageKind) -> String {
    switch pathExtension.lowercased() {
    case "jpg", "jpeg": return "image/jpeg"
    case "png": return "image/png"
    case "gif": return "image/gif"
    case "webp": return "image/webp"
    case "heic": return "image/heic"
    case "mp4", "mov", "m4v": return "video/mp4"
    case "mp3", "m4a", "aac": return "audio/mpeg"
    case "ogg", "oga", "opus": return "audio/ogg"
    default:
        switch kind {
        case .photo: return "image/jpeg"
        case .video: return "video/mp4"
        case .audio: return "audio/mpeg"
        case .voice: return "audio/ogg"
        case .sticker: return "image/webp"
        default: return "application/octet-stream"
        }
    }
}

private func miraFakeMediaMetadata(at url: URL, kind: FakeMessageKind) -> (duration: Int32?, width: Int32?, height: Int32?, size: Int64?) {
    let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
    if kind == .photo || kind == .sticker, let image = UIImage(contentsOfFile: url.path) {
        let width = image.cgImage?.width ?? Int(image.size.width * image.scale)
        let height = image.cgImage?.height ?? Int(image.size.height * image.scale)
        return (nil, Int32(clamping: width), Int32(clamping: height), size)
    }
    if kind == .video {
        let asset = AVURLAsset(url: url)
        let track = asset.tracks(withMediaType: .video).first
        let dimensions = track?.naturalSize.applying(track?.preferredTransform ?? .identity)
        let width = dimensions.map { Int32(clamping: Int(abs($0.width))) }
        let height = dimensions.map { Int32(clamping: Int(abs($0.height))) }
        let seconds = asset.duration.seconds
        let duration = seconds.isFinite && seconds > 0 ? Int32(clamping: Int(seconds.rounded())) : nil
        return (duration, width, height, size)
    }
    if kind == .audio || kind == .voice {
        let seconds = AVURLAsset(url: url).duration.seconds
        let duration = seconds.isFinite && seconds > 0 ? Int32(clamping: Int(seconds.rounded())) : nil
        return (duration, nil, nil, size)
    }
    return (nil, nil, nil, size)
}

private func miraCopyFakeMediaToCache(_ source: URL) -> URL? {
    let fileManager = FileManager.default
    guard let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
        return nil
    }
    let directory = applicationSupport.appendingPathComponent("MiraFakeMedia", isDirectory: true)
    do {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let extensionValue = source.pathExtension.isEmpty ? "bin" : source.pathExtension
        let destination = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension(extensionValue)
        let scoped = source.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                source.stopAccessingSecurityScopedResource()
            }
        }
        var coordinatorError: NSError?
        var copied = false
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: source, options: .withoutChanges, error: &coordinatorError) { coordinatedURL in
            do {
                try fileManager.copyItem(at: coordinatedURL, to: destination)
                copied = true
            } catch {
                copied = false
            }
        }
        return copied ? destination : nil
    } catch {
        return nil
    }
}

private final class MiraFakeMessageState {
    var text: String = ""
    var kind: FakeMessageKind = .text
    var mediaResource: String = ""
    var mediaFileName: String = ""
    var mediaMimeType: String = ""
    var mediaDuration: String = ""
    var mediaStars: String = ""
    var mediaStarCount: String = ""
    var oneMessagePerLine: Bool = false
    var conversationMode: Bool = false
    var outgoing: Bool = false
    var sender: String = ""
    var datePreset: Int = 0
    var customDaysBack: String = ""
    var exactDate: Int32 = Int32(Date().timeIntervalSince1970)
    var exactDateSelection: Bool = false
    var exactSeconds: String = String(format: "%02d", Calendar.current.component(.second, from: Date()))
    var editingRecordId: String?
    var version: Int = 0
    var isSubmitting = false

    init(editing record: FakeMessageRecord? = nil) {
        guard let record else {
            return
        }
        self.text = record.text
        self.kind = record.kind
        self.mediaResource = record.media?.resource ?? ""
        self.mediaFileName = record.media?.fileName ?? ""
        self.mediaMimeType = record.media?.mimeType ?? ""
        self.mediaDuration = record.media?.duration.map { String($0) } ?? ""
        self.mediaStars = record.media?.stars.map { String($0) } ?? ""
        self.mediaStarCount = record.media?.starCount.map { String($0) } ?? ""
        self.outgoing = record.outgoing
        self.sender = record.authorPeerId.map { String($0) } ?? record.authorName ?? ""
        self.datePreset = miraFakeMessageDatePresetCount - 2
        self.exactDate = record.date
        self.exactDateSelection = true
        self.exactSeconds = String(format: "%02d", Int(record.date % 60 + 60) % 60)
        self.editingRecordId = record.id
    }
}

private final class MiraFakeMessageControllerArguments {
    let context: AccountContext
    let state: MiraFakeMessageState
    let updated: () -> Void
    let present: (ViewController) -> Void

    init(context: AccountContext, state: MiraFakeMessageState, updated: @escaping () -> Void, present: @escaping (ViewController) -> Void) {
        self.context = context
        self.state = state
        self.updated = updated
        self.present = present
    }
}

private func miraLocalizedFakeText(_ isRussian: Bool, _ russian: String, _ english: String) -> String {
    return isRussian ? russian : english
}

private func miraFakeMessageKindTitle(_ kind: FakeMessageKind, isRussian: Bool = false) -> String {
    switch kind {
    case .text: return miraLocalizedFakeText(isRussian, "Текст", "Text")
    case .photo: return miraLocalizedFakeText(isRussian, "Фото", "Photo")
    case .video: return miraLocalizedFakeText(isRussian, "Видео", "Video")
    case .file: return miraLocalizedFakeText(isRussian, "Файл", "File")
    case .audio: return miraLocalizedFakeText(isRussian, "Аудио", "Audio")
    case .voice: return miraLocalizedFakeText(isRussian, "Голосовое сообщение", "Voice message")
    case .sticker: return miraLocalizedFakeText(isRussian, "Стикер", "Sticker")
    case .service: return miraLocalizedFakeText(isRussian, "Служебное сообщение", "Service message")
    case .stars: return miraLocalizedFakeText(isRussian, "Платёж звёздами", "Stars payment")
    }
}

private let miraFakeMessageDatePresetCount = 6

// Keep the canonical offsets separate from the localized labels used by the
// editor. The date math must never depend on the current interface language.
private let miraFakeMessageDatePresets: [(String, Int32?)] = [
    ("Now", nil),
    ("1 hour ago", 3600),
    ("Yesterday", 86400),
    ("7 days ago", 7 * 86400),
    ("Exact date & time", -2),
    ("Custom (days back)", -1)
]

private func miraLocalizedFakeMessageDatePresets(isRussian: Bool) -> [(String, Int32?)] {
    return [
        (miraLocalizedFakeText(isRussian, "Сейчас", "Now"), nil),
        (miraLocalizedFakeText(isRussian, "Час назад", "1 hour ago"), 3600),
        (miraLocalizedFakeText(isRussian, "Вчера", "Yesterday"), 86400),
        (miraLocalizedFakeText(isRussian, "7 дней назад", "7 days ago"), 7 * 86400),
        (miraLocalizedFakeText(isRussian, "Точная дата и время", "Exact date & time"), -2),
        (miraLocalizedFakeText(isRussian, "Дней назад…", "Custom (days back)"), -1)
    ]
}

private enum MiraFakeMessageEntry: ItemListNodeEntry {
    case input(String)
    case kind(FakeMessageKind)
    case mediaResource(String)
    case mediaFileName(String)
    case mediaMimeType(String)
    case mediaDuration(String)
    case mediaStars(String)
    case mediaStarCount(String)
    case batchMode(Bool)
    case conversationMode(Bool)
    case directionHeader
    case fromThem(Bool)
    case fromMe(Bool)
    case senderHeader
    case senderInput(String)
    case dateHeader
    case preset(Int, String, Bool)
    case exactDatePicker(Int32, Bool)
    case exactSeconds(String)
    case customDays(String)
    case hint(String)

    var section: ItemListSectionId {
        switch self {
        case .input, .kind, .mediaResource, .mediaFileName, .mediaMimeType, .mediaDuration, .mediaStars, .mediaStarCount, .batchMode, .conversationMode:
            return 0
        case .directionHeader, .fromThem, .fromMe, .senderHeader, .senderInput:
            return 1
        case .dateHeader, .preset, .exactDatePicker, .exactSeconds, .customDays:
            return 2
        case .hint:
            return 3
        }
    }

    var stableId: Int {
        switch self {
        case .input:
            return 0
        case .kind:
            return 1
        case .mediaResource:
            return 2
        case .mediaFileName:
            return 3
        case .mediaMimeType:
            return 4
        case .mediaDuration:
            return 5
        case .mediaStars:
            return 6
        case .mediaStarCount:
            return 7
        case .batchMode:
            return 8
        case .conversationMode:
            return 9
        case .directionHeader:
            return 10
        case .fromThem:
            return 11
        case .fromMe:
            return 12
        case .senderHeader:
            return 13
        case .senderInput:
            return 14
        case .dateHeader:
            return 15
        case let .preset(index, _, _):
            return 16 + index
        case .exactDatePicker:
            return 16 + miraFakeMessageDatePresetCount
        case .exactSeconds:
            return 17 + miraFakeMessageDatePresetCount
        case .customDays:
            return 18 + miraFakeMessageDatePresetCount
        case .hint:
            return 19 + miraFakeMessageDatePresetCount
        }
    }

    static func <(lhs: MiraFakeMessageEntry, rhs: MiraFakeMessageEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        guard let arguments = arguments as? MiraFakeMessageControllerArguments else {
            return ItemListTextItem(presentationData: presentationData, text: .plain(""), sectionId: self.section)
        }
        let isRussian = presentationData.strings.baseLanguageCode.lowercased().hasPrefix("ru")
        switch self {
        case let .input(text):
            return ItemListMultilineInputItem(presentationData: presentationData, text: text, placeholder: miraLocalizedFakeText(isRussian, "Текст сообщения", "Message text"), maxLength: nil, sectionId: self.section, style: .blocks, textUpdated: { value in
                arguments.state.text = value
                arguments.updated()
            })
        case let .kind(kind):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: miraLocalizedFakeText(isRussian, "Тип сообщения", "Content type"), label: miraFakeMessageKindTitle(kind, isRussian: isRussian), sectionId: self.section, style: .blocks, action: {
                let presentationData = arguments.context.sharedContext.currentPresentationData.with { $0 }
                let sheet = ActionSheetController(presentationData: presentationData)
                let kinds: [FakeMessageKind] = [.text, .photo, .video, .file, .audio, .voice, .sticker, .service, .stars]
                let buttons = kinds.map { kind in
                    ActionSheetButtonItem(title: miraFakeMessageKindTitle(kind, isRussian: isRussian), color: .accent, action: { [weak sheet] in
                        arguments.state.kind = kind
                        arguments.updated()
                        sheet?.dismissAnimated()
                    })
                }
                sheet.setItemGroups([
                    ActionSheetItemGroup(items: buttons),
                    ActionSheetItemGroup(items: [ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak sheet] in
                        sheet?.dismissAnimated()
                    })])
                ])
                arguments.present(sheet)
            })
        case let .mediaResource(value):
            let fileName = value.isEmpty ? "" : URL(fileURLWithPath: value).lastPathComponent
            let title = isRussian ? "Медиафайл" : "Media file"
            let pickerTitle = arguments.state.kind == .photo || arguments.state.kind == .video || arguments.state.kind == .sticker
                ? (isRussian ? "Выбрать в Telegram" : "Choose in Telegram")
                : (isRussian ? "Выбрать файл" : "Choose file")
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: fileName.isEmpty ? pickerTitle : fileName, sectionId: self.section, style: .blocks, action: {
                if miraFakeMediaUseTelegramGallery(arguments.state.kind) {
                    let picker = MediaPickerScreenImpl(
                        context: arguments.context,
                        updatedPresentationData: nil,
                        style: .glass,
                        peer: nil,
                        threadTitle: nil,
                        chatLocation: .peer(id: arguments.context.account.peerId),
                        enableMultiselection: false,
                        subject: .assets(nil, .default)
                    )
                    picker.getCaptionPanelView = { nil }
                    picker.legacyCompletion = { _, signals, _, _, _, _, sendCompletion in
                        let _ = (legacyAssetPickerEnqueueMessages(context: arguments.context, account: arguments.context.account, signals: signals)
                        |> deliverOnMainQueue).start(next: { items in
                            guard let item = items.first,
                                  case let .message(_, _, _, mediaReference, _, _, _, _, _, _) = item.message,
                                  let mediaReference,
                                  let source = miraFakeMediaFileURL(mediaReference.media),
                                  let cachedURL = miraCopyFakeMediaToCache(source) else {
                                return
                            }
                            arguments.state.mediaResource = cachedURL.path
                            arguments.state.mediaFileName = source.lastPathComponent
                            arguments.state.mediaMimeType = miraFakeMediaMimeType(source.pathExtension, kind: arguments.state.kind)
                            arguments.updated()
                            sendCompletion()
                        })
                    }
                    picker.navigationPresentation = .modal
                    arguments.present(picker)
                    return
                }
                let picker = legacyICloudFilePicker(theme: arguments.context.sharedContext.currentPresentationData.with { $0 }.theme, mode: .import, documentTypes: miraFakeMediaDocumentTypes(arguments.state.kind), completion: { urls in
                    guard let source = urls.first, let cachedURL = miraCopyFakeMediaToCache(source) else {
                        return
                    }
                    arguments.state.mediaResource = cachedURL.path
                    arguments.state.mediaFileName = source.lastPathComponent
                    arguments.state.mediaMimeType = miraFakeMediaMimeType(source.pathExtension, kind: arguments.state.kind)
                    arguments.updated()
                })
                arguments.present(picker)
            })
        case let .mediaFileName(value):
            return ItemListSingleLineInputItem(presentationData: presentationData, title: NSAttributedString(), text: value, placeholder: miraLocalizedFakeText(isRussian, "Имя файла (необязательно)", "File name (optional)"), type: .regular(capitalization: false, autocorrection: false), sectionId: self.section, textUpdated: { value in
                arguments.state.mediaFileName = value
                arguments.updated()
            }, action: {})
        case let .mediaMimeType(value):
            return ItemListSingleLineInputItem(presentationData: presentationData, title: NSAttributedString(), text: value, placeholder: miraLocalizedFakeText(isRussian, "Тип MIME (необязательно)", "MIME type (optional)"), type: .regular(capitalization: false, autocorrection: false), sectionId: self.section, textUpdated: { value in
                arguments.state.mediaMimeType = value
                arguments.updated()
            }, action: {})
        case let .mediaDuration(value):
            return ItemListSingleLineInputItem(presentationData: presentationData, title: NSAttributedString(), text: value, placeholder: miraLocalizedFakeText(isRussian, "Длительность (секунды)", "Duration (seconds)"), type: .number, sectionId: self.section, textUpdated: { value in
                arguments.state.mediaDuration = value.filter { $0.isNumber }
                arguments.updated()
            }, action: {})
        case let .mediaStars(value):
            return ItemListSingleLineInputItem(presentationData: presentationData, title: NSAttributedString(), text: value, placeholder: miraLocalizedFakeText(isRussian, "Количество звёзд", "Stars amount"), type: .number, sectionId: self.section, textUpdated: { value in
                arguments.state.mediaStars = value.filter { $0.isNumber }
                arguments.updated()
            }, action: {})
        case let .mediaStarCount(value):
            return ItemListSingleLineInputItem(presentationData: presentationData, title: NSAttributedString(), text: value, placeholder: miraLocalizedFakeText(isRussian, "Количество элементов", "Star item count"), type: .number, sectionId: self.section, textUpdated: { value in
                arguments.state.mediaStarCount = value.filter { $0.isNumber }
                arguments.updated()
            }, action: {})
        case let .batchMode(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: miraLocalizedFakeText(isRussian, "Отдельное сообщение для каждой строки", "One message per line"), value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.state.oneMessagePerLine = value
                arguments.updated()
            })
        case let .conversationMode(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: miraLocalizedFakeText(isRussian, "Сценарий переписки", "Conversation script"), value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.state.conversationMode = value
                if value {
                    arguments.state.oneMessagePerLine = true
                }
                arguments.updated()
            })
        case .directionHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: miraLocalizedFakeText(isRussian, "Направление", "Direction"), sectionId: self.section)
        case let .fromThem(checked):
            return ItemListCheckboxItem(presentationData: presentationData, title: miraLocalizedFakeText(isRussian, "От собеседника", "From them"), style: .left, checked: checked, zeroSeparatorInsets: true, sectionId: self.section, action: {
                arguments.state.outgoing = false
                arguments.updated()
            })
        case let .fromMe(checked):
            return ItemListCheckboxItem(presentationData: presentationData, title: miraLocalizedFakeText(isRussian, "От меня", "From me"), style: .left, checked: checked, zeroSeparatorInsets: true, sectionId: self.section, action: {
                arguments.state.outgoing = true
                arguments.updated()
            })
        case .senderHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: miraLocalizedFakeText(isRussian, "Отправитель", "Sender"), sectionId: self.section)
        case let .senderInput(text):
            return ItemListSingleLineInputItem(presentationData: presentationData, title: NSAttributedString(), text: text, placeholder: miraLocalizedFakeText(isRussian, "@username или ID пользователя", "@username or user ID"), type: .regular(capitalization: false, autocorrection: false), sectionId: self.section, textUpdated: { value in
                arguments.state.sender = value
                arguments.updated()
            }, action: {})
        case .dateHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: miraLocalizedFakeText(isRussian, "Дата", "Date"), sectionId: self.section)
        case let .preset(index, title, checked):
            return ItemListCheckboxItem(presentationData: presentationData, title: title, style: .left, checked: checked, zeroSeparatorInsets: true, sectionId: self.section, action: {
                arguments.state.datePreset = index
                arguments.updated()
            })
        case let .exactDatePicker(timestamp, selectingDate):
            return ItemListDatePickerItem(presentationData: presentationData, systemStyle: .glass, dateTimeFormat: presentationData.dateTimeFormat, date: timestamp, minDate: 0, title: miraLocalizedFakeText(isRussian, "Точная дата и время", "Exact date & time"), displayingDateSelection: selectingDate, displayingTimeSelection: !selectingDate, sectionId: self.section, style: .blocks, toggleDateSelection: {
                arguments.state.exactDateSelection = true
                arguments.updated()
            }, toggleTimeSelection: {
                arguments.state.exactDateSelection = false
                arguments.updated()
            }, updated: { date in
                let calendar = Calendar.current
                let previousSeconds = calendar.component(.second, from: Date(timeIntervalSince1970: TimeInterval(arguments.state.exactDate)))
                var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: Date(timeIntervalSince1970: TimeInterval(date)))
                components.second = previousSeconds
                if let updatedDate = calendar.date(from: components) {
                    arguments.state.exactDate = miraClampedMessageTimestamp(Int64(updatedDate.timeIntervalSince1970))
                    arguments.state.exactSeconds = String(format: "%02d", previousSeconds)
                    arguments.updated()
                }
            })
        case let .exactSeconds(text):
            return ItemListSingleLineInputItem(presentationData: presentationData, title: NSAttributedString(), text: text, placeholder: miraLocalizedFakeText(isRussian, "Секунды (0–59)", "Seconds (0-59)"), type: .number, sectionId: self.section, textUpdated: { value in
                let filtered = String(value.filter { $0.isNumber }.prefix(2))
                let seconds = min(59, Int(filtered) ?? 0)
                arguments.state.exactSeconds = String(format: "%02d", seconds)
                let calendar = Calendar.current
                var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: Date(timeIntervalSince1970: TimeInterval(arguments.state.exactDate)))
                components.second = seconds
                if let updatedDate = calendar.date(from: components) {
                    arguments.state.exactDate = miraClampedMessageTimestamp(Int64(updatedDate.timeIntervalSince1970))
                }
                arguments.updated()
            }, action: {})
        case let .customDays(text):
            return ItemListSingleLineInputItem(presentationData: presentationData, title: NSAttributedString(), text: text, placeholder: miraLocalizedFakeText(isRussian, "Дней назад", "Days back"), type: .number, sectionId: self.section, textUpdated: { value in
                arguments.state.customDaysBack = value
                arguments.updated()
            }, action: {
            })
        case let .hint(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

// Transaction size controls work per queue turn, never the number of requested messages.
private let miraFakeMessageTransactionBatchSize = 256

private func miraClampedMessageTimestamp(_ value: Int64) -> Int32 {
    return Int32(max(Int64(Int32.min), min(Int64(Int32.max), value)))
}

public func miraFakeMessageController(context: AccountContext, peerId: PeerId, editing record: FakeMessageRecord? = nil, onSaved: (() -> Void)? = nil) -> ViewController {
    let state = MiraFakeMessageState(editing: record)
    let versionPromise = ValuePromise<Int>(0, ignoreRepeated: true)
    var dismissImpl: (() -> Void)?

    var presentControllerImpl: ((ViewController) -> Void)?
    let arguments = MiraFakeMessageControllerArguments(context: context, state: state, updated: {
        state.version += 1
        versionPromise.set(state.version)
    }, present: { controller in
        presentControllerImpl?(controller)
    })
    let finishSave: () -> Void = {
        if let onSaved {
            onSaved()
        } else {
            dismissImpl?()
        }
    }

    let resolveSenderAndAdd: () -> Void = {
        guard !state.isSubmitting else {
            return
        }
        let texts: [String]
        if state.oneMessagePerLine {
            texts = state.text
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        } else {
            let text = state.text.trimmingCharacters(in: .whitespacesAndNewlines)
            texts = text.isEmpty ? [] : [text]
        }
        guard !texts.isEmpty else {
            return
        }
        let now = miraClampedMessageTimestamp(Int64(CFAbsoluteTimeGetCurrent() + NSTimeIntervalSince1970))
        let baseDate: Int32
        if state.datePreset == miraFakeMessageDatePresetCount - 2 {
            baseDate = miraClampedMessageTimestamp(Int64(state.exactDate))
        } else if miraFakeMessageDatePresets.indices.contains(state.datePreset), let offset = miraFakeMessageDatePresets[state.datePreset].1 {
            if offset < 0 {
                let requestedDays = Int64(state.customDaysBack) ?? 0
                let days = max(0, min(requestedDays, Int64(Int32.max) / 86400))
                baseDate = miraClampedMessageTimestamp(Int64(now) - days * 86400)
            } else {
                baseDate = miraClampedMessageTimestamp(Int64(now) - Int64(offset))
            }
        } else {
            baseDate = now
        }
        let outgoing = state.outgoing
        let mediaDescriptor: FakeMessageMedia? = {
            guard state.kind != .text else {
                return nil
            }
            let resource = state.mediaResource.trimmingCharacters(in: .whitespacesAndNewlines)
            let fileName = state.mediaFileName.trimmingCharacters(in: .whitespacesAndNewlines)
            let mimeType = state.mediaMimeType.trimmingCharacters(in: .whitespacesAndNewlines)
            let metadata = resource.isEmpty ? (duration: nil, width: nil, height: nil, size: nil) : miraFakeMediaMetadata(at: URL(fileURLWithPath: resource), kind: state.kind)
            return FakeMessageMedia(
                kind: state.kind,
                resource: resource.isEmpty ? nil : resource,
                fileName: fileName.isEmpty ? nil : fileName,
                mimeType: mimeType.isEmpty ? nil : mimeType,
                duration: Int32(state.mediaDuration).flatMap { max(0, $0) } ?? metadata.duration,
                width: metadata.width,
                height: metadata.height,
                fileSize: metadata.size,
                stars: Int64(state.mediaStars).flatMap { max(0, $0) },
                starCount: Int32(state.mediaStarCount).flatMap { max(0, $0) }
            )
        }()
        state.isSubmitting = true
        arguments.updated()

        // Editing keeps the existing local Postbox id and author metadata.
        // Do this before sender resolution so an edit never performs a network
        // lookup for the label shown in the original fake message.
        if let editingRecordId = state.editingRecordId {
            let editAuthorPeerId = (!state.outgoing ? Int64(state.sender.trimmingCharacters(in: .whitespacesAndNewlines)) : nil).map { PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value($0)) }
            let _ = (context.engine.messages.miraUpdateFakeMessage(id: editingRecordId, text: texts[0], date: baseDate, kind: state.kind, media: mediaDescriptor, outgoing: state.outgoing, authorPeerId: editAuthorPeerId, authorName: state.sender.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : state.sender.trimmingCharacters(in: .whitespacesAndNewlines))
            |> deliverOnMainQueue).start(next: { success in
                state.isSubmitting = false
                arguments.updated()
                if success {
                    finishSave()
                }
            })
            return
        }

        let addMessages: (EnginePeer?, String?) -> Void = { author, fallbackName in
            if state.conversationMode {
                let scriptedMessages: [(text: String, date: Int32, outgoing: Bool)] = texts.enumerated().compactMap { index, rawText in
                    var text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
                    var messageOutgoing = outgoing
                    let prefixes: [(String, Bool)] = [("me:", true), ("you:", true), ("out:", true), ("[me]", true), ("them:", false), ("in:", false), ("from them:", false), ("[them]", false)]
                    for (prefix, value) in prefixes where text.lowercased().hasPrefix(prefix) {
                        text = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                        messageOutgoing = value
                        break
                    }
                    guard !text.isEmpty else { return nil }
                    let date = miraClampedMessageTimestamp(Int64(baseDate) - Int64(texts.count - 1 - index))
                    return (text, date, messageOutgoing)
                }
                func insertScriptedMessage(at index: Int) {
                    guard index < scriptedMessages.count else {
                        state.isSubmitting = false
                        arguments.updated()
                        finishSave()
                        return
                    }
                    let entry = scriptedMessages[index]
                    let signal: Signal<Void, NoError>
                    if state.kind == .text {
                        signal = context.engine.messages.miraAddFakeMessage(
                            peerId: peerId,
                            text: entry.text,
                            outgoing: entry.outgoing,
                            date: entry.date,
                            authorPeerId: author?.id,
                            authorName: author?.compactDisplayTitle ?? fallbackName
                        )
                    } else {
                        signal = context.engine.messages.miraAddFakeMediaMessage(
                            peerId: peerId,
                            text: entry.text,
                            kind: state.kind,
                            media: mediaDescriptor,
                            outgoing: entry.outgoing,
                            date: entry.date,
                            authorPeerId: author?.id,
                            authorName: author?.compactDisplayTitle ?? fallbackName
                        )
                    }
                    let _ = (signal |> deliverOnMainQueue).start(completed: {
                        insertScriptedMessage(at: index + 1)
                    })
                }
                insertScriptedMessage(at: 0)
                return
            }
            func insertBatch(startIndex: Int) {
                let endIndex = min(startIndex + miraFakeMessageTransactionBatchSize, texts.count)
                let messageDates: [(text: String, date: Int32)] = (startIndex ..< endIndex).map { index in
                    // Keep scripted lines in their entered order when the chat sorts by date.
                    let date = miraClampedMessageTimestamp(Int64(baseDate) - Int64(texts.count - 1 - index))
                    return (texts[index], date)
                }
                let completeBatch: () -> Void = {
                    if endIndex < texts.count {
                        insertBatch(startIndex: endIndex)
                    } else {
                        state.isSubmitting = false
                        arguments.updated()
                        finishSave()
                    }
                }
                if state.kind == .text {
                    let _ = (context.engine.messages.miraAddFakeMessages(peerId: peerId, messages: messageDates, outgoing: outgoing, authorPeerId: author?.id, authorName: author?.compactDisplayTitle ?? fallbackName)
                    |> deliverOnMainQueue).start(completed: completeBatch)
                } else {
                    let mediaMessages: [(text: String, date: Int32, kind: FakeMessageKind, media: FakeMessageMedia?)] = messageDates.map { entry in
                        return (text: entry.text, date: entry.date, kind: state.kind, media: mediaDescriptor)
                    }
                    let _ = (context.engine.messages.miraAddFakeMediaMessages(peerId: peerId, messages: mediaMessages, outgoing: outgoing, authorPeerId: author?.id, authorName: author?.compactDisplayTitle ?? fallbackName)
                    |> deliverOnMainQueue).start(completed: completeBatch)
                }
            }
            // Once accepted, all batches finish even if the user leaves this screen.
            // Only sender lookup is canceled by navigation; it has no local side effects.
            insertBatch(startIndex: 0)
        }
        guard !outgoing else {
            addMessages(nil, nil)
            return
        }
        let sender = state.sender.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sender.isEmpty else {
            addMessages(nil, nil)
            return
        }
        // Fake messages are local by definition. Do not wait for a Telegram
        // username lookup: an offline account, a stale username, or a slow
        // network must never block insertion or leave the editor in a spinner
        // state. The entered sender is retained as local display metadata.
        addMessages(nil, sender)
    }

    let signal: Signal<(ItemListControllerState, (ItemListNodeState, Any)), NoError> = combineLatest(context.sharedContext.presentationData, versionPromise.get())
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, MiraFakeMessageControllerArguments)) in
        let isRussian = presentationData.strings.baseLanguageCode.lowercased().hasPrefix("ru")
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(miraLocalizedFakeText(isRussian, state.editingRecordId == nil ? "Добавить сообщение" : "Изменить сообщение", state.editingRecordId == nil ? "Add Message" : "Edit Message")), leftNavigationButton: nil, rightNavigationButton: ItemListNavigationButton(content: .text(presentationData.strings.Common_Done), style: state.isSubmitting ? .activity : .regular, enabled: !state.isSubmitting && !state.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, action: {
            resolveSenderAndAdd()
        }), backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back), animateChanges: true)

        var entries: [MiraFakeMessageEntry] = []
        entries.append(.input(state.text))
        entries.append(.kind(state.kind))
        if state.kind != .text {
            entries.append(.mediaResource(state.mediaResource))
            entries.append(.mediaFileName(state.mediaFileName))
            entries.append(.mediaMimeType(state.mediaMimeType))
            if state.kind == .audio || state.kind == .voice || state.kind == .video {
                entries.append(.mediaDuration(state.mediaDuration))
            }
            if state.kind == .stars {
                entries.append(.mediaStars(state.mediaStars))
                entries.append(.mediaStarCount(state.mediaStarCount))
            }
        }
        entries.append(.batchMode(state.oneMessagePerLine))
        entries.append(.conversationMode(state.conversationMode))
        entries.append(.directionHeader)
        entries.append(.fromThem(!state.outgoing))
        entries.append(.fromMe(state.outgoing))
        if !state.outgoing {
            entries.append(.senderHeader)
            entries.append(.senderInput(state.sender))
        }
        entries.append(.dateHeader)
        let localizedDatePresets = miraLocalizedFakeMessageDatePresets(isRussian: isRussian)
        for (index, preset) in localizedDatePresets.enumerated() {
            entries.append(.preset(index, preset.0, state.datePreset == index))
        }
        if state.datePreset == miraFakeMessageDatePresetCount - 2 {
            entries.append(.exactDatePicker(state.exactDate, state.exactDateSelection))
            entries.append(.exactSeconds(state.exactSeconds))
        }
        if state.datePreset == miraFakeMessageDatePresetCount - 1 {
            entries.append(.customDays(state.customDaysBack))
        }
        let pendingCount: Int
        if state.oneMessagePerLine {
            pendingCount = state.text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.count
        } else {
            pendingCount = state.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : 1
        }
        let countHint: String
        if pendingCount > 0 {
            let noun = miraLocalizedFakeText(isRussian, pendingCount == 1 ? "сообщение" : "сообщений", pendingCount == 1 ? "message" : "messages")
            countHint = miraLocalizedFakeText(isRussian, "Готово к добавлению: \(pendingCount) \(noun).", "Ready to add \(pendingCount) \(noun).")
        } else {
            countHint = ""
        }
        let lineHint = state.oneMessagePerLine
            ? miraLocalizedFakeText(isRussian, "Каждая непустая строка станет отдельным сообщением.", "Each non-empty line becomes a separate message.")
            : ""
        let scriptHint = state.conversationMode
            ? miraLocalizedFakeText(isRussian, "Режим переписки поддерживает префиксы me:/you:/them:/in:.", "Conversation mode accepts me:/you:/them:/in: prefixes per line.")
            : ""
        entries.append(.hint([lineHint, scriptHint, countHint].filter { !$0.isEmpty }.joined(separator: " ")))

        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks)

        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    presentControllerImpl = { [weak controller] alertController in
        controller?.present(alertController, in: .window(.root))
    }
    dismissImpl = { [weak controller] in
        guard let controller else {
            return
        }
        guard let navigationController = controller.navigationController as? NavigationController else {
            controller.dismiss()
            return
        }
        if navigationController.topViewController === controller {
            _ = navigationController.popViewController(animated: true)
        } else if let index = navigationController.viewControllers.firstIndex(where: { $0 === controller }), navigationController.viewControllers.count > 1 {
            // Saving is asynchronous. If a media picker or another local
            // editor was pushed while it completed, remove this editor from
            // the stack instead of silently leaving it behind.
            var viewControllers = navigationController.viewControllers
            viewControllers.remove(at: index)
            navigationController.setViewControllers(viewControllers, animated: false)
        } else {
            controller.dismiss()
        }
    }
    return controller
}

private final class MiraFakeConversationPickerState {
    var text = ""
    var version = 0
}

private enum MiraFakeConversationPickerEntry: ItemListNodeEntry {
    case input(String)
    case hint(String)

    var section: ItemListSectionId {
        switch self {
        case .input:
            return 0
        case .hint:
            return 1
        }
    }

    var stableId: Int {
        switch self {
        case .input:
            return 0
        case .hint:
            return 1
        }
    }

    static func <(lhs: MiraFakeConversationPickerEntry, rhs: MiraFakeConversationPickerEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! MiraFakeConversationPickerArguments
        switch self {
        case let .input(value):
            let isRussian = presentationData.strings.baseLanguageCode.lowercased().hasPrefix("ru")
            return ItemListSingleLineInputItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: NSAttributedString(string: isRussian ? "Username, ссылка или ID" : "Username, link, or ID"),
                text: value,
                placeholder: isRussian ? "@username, t.me/… или 123456789" : "@username, t.me/…, or 123456789",
                type: .regular(capitalization: false, autocorrection: false),
                sectionId: self.section,
                textUpdated: { value in
                    arguments.state.text = value
                    arguments.updated()
                },
                action: {}
            )
        case let .hint(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private final class MiraFakeConversationPickerArguments {
    let state: MiraFakeConversationPickerState
    let updated: () -> Void

    init(state: MiraFakeConversationPickerState, updated: @escaping () -> Void) {
        self.state = state
        self.updated = updated
    }
}

private enum MiraFakeConversationDestination {
    case peerId(PeerId)
    case username(String)
}

private func miraFakeConversationDestination(_ value: String) -> MiraFakeConversationDestination? {
    var input = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !input.isEmpty else {
        return nil
    }
    if let id = Int64(input) {
        guard id > 0 else {
            return nil
        }
        return .peerId(PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(id)))
    }
    if input.hasPrefix("@") {
        input.removeFirst()
        return input.isEmpty ? nil : .username(input)
    }

    guard input.range(of: "^(https?://)?(www\\.)?(t\\.me|telegram\\.me)/", options: .regularExpression) != nil else {
        return nil
    }
    if !input.contains("://") {
        input = "https://\(input)"
    }
    guard let components = URLComponents(string: input),
          let host = components.host?.lowercased(),
          ["t.me", "www.t.me", "telegram.me", "www.telegram.me"].contains(host) else {
        return nil
    }
    var path = components.path.split(separator: "/").map(String.init)
    if path.first == "s" {
        path.removeFirst()
    }
    if path.first == "c", path.count > 1, let channelId = Int64(path[1]), channelId > 0 {
        return .peerId(PeerId(namespace: Namespaces.Peer.CloudChannel, id: PeerId.Id._internalFromInt64Value(channelId)))
    }
    guard let username = path.first, !username.isEmpty, !username.hasPrefix("+") else {
        return nil
    }
    return .username(username)
}

private func miraFakeConversationPickerController(context: AccountContext, push: @escaping (ViewController) -> Void) -> ViewController {
    let state = MiraFakeConversationPickerState()
    let versionPromise = ValuePromise<Int>(0, ignoreRepeated: true)
    let disposable = MetaDisposable()
    weak var pickerController: ViewController?
    var currentPresentationData = context.sharedContext.currentPresentationData.with { $0 }

    let open = {
        let value = state.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return
        }
        let openPeer: (PeerId) -> Void = { peerId in
            guard peerId != context.account.peerId else {
                return
            }
            let _ = (context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId))
            |> deliverOnMainQueue).start(next: { peer in
                guard peer != nil else {
                    let isRussian = currentPresentationData.strings.baseLanguageCode.lowercased().hasPrefix("ru")
                    let alert = textAlertController(context: context, title: isRussian ? "Чат не найден" : "Chat not found", text: isRussian ? "Этот чат не сохранён в аккаунте Telegram. Откройте его в Telegram и повторите попытку." : "This chat is not known by the Telegram account. Open it in Telegram and try again.", actions: [TextAlertAction(type: .defaultAction, title: currentPresentationData.strings.Common_OK, action: {})])
                    context.sharedContext.mainWindow?.present(alert, on: .root)
                    return
                }
                let chatController = context.sharedContext.makeChatController(context: context, chatLocation: .peer(id: peerId), subject: nil, botStart: nil, mode: .standard(.default), params: nil)
                if let pickerController, let navigationController = pickerController.navigationController as? NavigationController,
                   let pickerIndex = navigationController.viewControllers.firstIndex(where: { $0 === pickerController }) {
                    var viewControllers = navigationController.viewControllers
                    viewControllers.remove(at: pickerIndex)
                    navigationController.setViewControllers(viewControllers, animated: false)
                }
                push(chatController)
            })
        }
        guard let destination = miraFakeConversationDestination(value) else {
            return
        }
        if case let .peerId(peerId) = destination {
            disposable.set((context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId))
            |> deliverOnMainQueue).start(next: { peer in
                guard peer != nil else {
                    let isRussian = currentPresentationData.strings.baseLanguageCode.lowercased().hasPrefix("ru")
                    let alert = textAlertController(context: context, title: isRussian ? "Чат не найден" : "Chat not found", text: isRussian ? "Введите username, ссылку на чат или ID, уже известный этому аккаунту Telegram." : "Enter a username, chat link, or ID already known by this Telegram account.", actions: [TextAlertAction(type: .defaultAction, title: currentPresentationData.strings.Common_OK, action: {})])
                    context.sharedContext.mainWindow?.present(alert, on: .root)
                    return
                }
                openPeer(peer.id)
            }))
            return
        }
        guard case let .username(name) = destination else { return }
        disposable.set((context.engine.peers.resolvePeerByName(name: name, referrer: nil)
        |> deliverOnMainQueue).start(next: { result in
            if case let .result(peer) = result, let peer {
                openPeer(peer.id)
            } else if case .result = result {
                let isRussian = currentPresentationData.strings.baseLanguageCode.lowercased().hasPrefix("ru")
                let alert = textAlertController(context: context, title: isRussian ? "Чат не найден" : "Chat not found", text: isRussian ? "Проверьте username или ссылку и попробуйте ещё раз." : "Check the username or link and try again.", actions: [TextAlertAction(type: .defaultAction, title: currentPresentationData.strings.Common_OK, action: {})])
                context.sharedContext.mainWindow?.present(alert, on: .root)
            }
        }))
    }

    let signal = combineLatest(context.sharedContext.presentationData, versionPromise.get())
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        currentPresentationData = presentationData
        let isRussian = presentationData.strings.baseLanguageCode.lowercased().hasPrefix("ru")
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text(isRussian ? "Новая переписка" : "Open conversation"),
            leftNavigationButton: nil,
            rightNavigationButton: ItemListNavigationButton(content: .text(isRussian ? "Продолжить" : "Open"), style: .bold, enabled: !state.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, action: open),
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back),
            animateChanges: true
        )
        let entries: [MiraFakeConversationPickerEntry] = [
            .input(state.text),
            .hint(isRussian
                ? "Введите username, ссылку t.me или ID, уже известный аккаунту. История чата останется на месте."
                : "Use a username, t.me link, or ID already known by this account. Existing chat history stays in place.")
        ]
        let arguments = MiraFakeConversationPickerArguments(state: state, updated: {
            state.version += 1
            versionPromise.set(state.version)
        })
        return (controllerState, (ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks), arguments as Any))
    }
    let controller = ItemListController(context: context, state: signal)
    pickerController = controller
    controller.navigationPresentation = .modal
    return controller
}

private enum MiraFakeMessagesListEntry: ItemListNodeEntry {
    case add(String)
    case choose(String)
    case count(String)
    case message(Int, FakeMessageRecord, String, String)
    case removeAll(String)
    case empty(String)

    var section: ItemListSectionId {
        switch self {
        case .add, .choose, .count:
            return 0
        case .message, .removeAll, .empty:
            return 1
        }
    }

    var stableId: Int {
        switch self {
        case .add:
            return 0
        case .choose:
            return 1
        case .count:
            return 2
        case let .message(_, record, _, _):
            // Row identifiers remain stable when the list is sorted and cannot
            // collide with the fixed Add/Count/Remove rows at large counts.
            let value = Int(truncatingIfNeeded: record.stableUniqueId)
            switch value {
            case 0, 1, 2, 100000, 100001:
                return value ^ 0x40000000
            default:
                return value
            }
        case .removeAll:
            return 100000
        case .empty:
            return 100001
        }
    }

    static func < (lhs: MiraFakeMessagesListEntry, rhs: MiraFakeMessagesListEntry) -> Bool {
        return lhs.order < rhs.order
    }

    private var order: Int {
        switch self {
        case .add:
            return 0
        case .choose:
            return 1
        case .count:
            return 2
        case let .message(index, _, _, _):
            return 3 + index
        case .removeAll:
            return Int.max - 1
        case .empty:
            return Int.max
        }
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        guard let arguments = arguments as? MiraFakeMessagesListArguments else {
            return ItemListTextItem(presentationData: presentationData, text: .plain(""), sectionId: self.section)
        }
        switch self {
        case let .add(title):
            return ItemListDisclosureItem(presentationData: presentationData, title: title, label: "", sectionId: self.section, style: .blocks, action: {
                arguments.add()
            })
        case let .choose(title):
            let isRussian = presentationData.strings.baseLanguageCode.lowercased().hasPrefix("ru")
            return ItemListDisclosureItem(presentationData: presentationData, title: title, label: miraLocalizedFakeText(isRussian, "Username или ID", "Username or ID"), sectionId: self.section, style: .blocks, action: {
                arguments.choose()
            })
        case let .count(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .message(_, record, title, detail):
            return ItemListDisclosureItem(presentationData: presentationData, title: title, label: detail, labelStyle: .detailText, sectionId: self.section, style: .blocks, action: {
                arguments.showActions(record)
            })
        case let .removeAll(title):
            return ItemListActionItem(presentationData: presentationData, title: title, kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.confirmRemoveAll()
            })
        case let .empty(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private final class MiraFakeMessagesListArguments {
    let add: () -> Void
    let choose: () -> Void
    let showActions: (FakeMessageRecord) -> Void
    let confirmRemoveAll: () -> Void
    let confirmRemove: (FakeMessageRecord) -> Void

    init(add: @escaping () -> Void, choose: @escaping () -> Void, showActions: @escaping (FakeMessageRecord) -> Void, confirmRemoveAll: @escaping () -> Void, confirmRemove: @escaping (FakeMessageRecord) -> Void) {
        self.add = add
        self.choose = choose
        self.showActions = showActions
        self.confirmRemoveAll = confirmRemoveAll
        self.confirmRemove = confirmRemove
    }
}

private func miraFakeMessageListDate(_ timestamp: Int32) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .medium
    return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
}

public func miraFakeMessagesController(context: AccountContext, peerId: PeerId) -> ViewController {
    var pushControllerImpl: ((ViewController) -> Void)?
    var presentControllerImpl: ((ViewController) -> Void)?
    let arguments = MiraFakeMessagesListArguments(add: {
        pushControllerImpl?(miraFakeMessageController(context: context, peerId: peerId))
    }, choose: {
        pushControllerImpl?(miraFakeConversationPickerController(context: context, push: { controller in
            pushControllerImpl?(controller)
        }))
    }, showActions: { record in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let actionSheet = ActionSheetController(presentationData: presentationData)
        actionSheet.setItemGroups([
            ActionSheetItemGroup(items: [
                ActionSheetButtonItem(title: miraLocalizedFakeText(presentationData.strings.baseLanguageCode.lowercased().hasPrefix("ru"), "Изменить", "Edit"), color: .accent, action: { [weak actionSheet] in
                    actionSheet?.dismissAnimated()
                    pushControllerImpl?(miraFakeMessageController(context: context, peerId: peerId, editing: record))
                }),
                ActionSheetButtonItem(title: record.isRead ? miraLocalizedFakeText(presentationData.strings.baseLanguageCode.lowercased().hasPrefix("ru"), "Отметить непрочитанным", "Mark as unread") : miraLocalizedFakeText(presentationData.strings.baseLanguageCode.lowercased().hasPrefix("ru"), "Отметить прочитанным", "Mark as read"), color: .accent, action: { [weak actionSheet] in
                    actionSheet?.dismissAnimated()
                    let _ = context.engine.messages.miraSetFakeMessageRead(id: record.id, isRead: !record.isRead).start()
                }),
                ActionSheetButtonItem(title: presentationData.strings.Common_Delete, color: .destructive, action: { [weak actionSheet] in
                    actionSheet?.dismissAnimated()
                    let strings = context.sharedContext.currentPresentationData.with { $0.strings }
                    let isRussian = presentationData.strings.baseLanguageCode.lowercased().hasPrefix("ru")
                    let controller = textAlertController(context: context, title: miraLocalizedFakeText(isRussian, "Удалить сообщение?", "Remove Message?"), text: miraLocalizedFakeText(isRussian, "Это сообщение будет удалено из чата.", "This message will be removed from the chat."), actions: [
                        TextAlertAction(type: .genericAction, title: strings.Common_Cancel, action: {}),
                        TextAlertAction(type: .destructiveAction, title: strings.Common_Delete, action: {
                            let _ = context.engine.messages.miraRemoveFakeMessage(id: record.id).start()
                        })
                    ])
                    presentControllerImpl?(controller)
                })
            ]),
            ActionSheetItemGroup(items: [
                ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                    actionSheet?.dismissAnimated()
                })
            ])
        ])
        presentControllerImpl?(actionSheet)
    }, confirmRemoveAll: {
        let strings = context.sharedContext.currentPresentationData.with { $0.strings }
        let isRussian = strings.baseLanguageCode.lowercased().hasPrefix("ru")
        let controller = textAlertController(context: context, title: miraLocalizedFakeText(isRussian, "Удалить сообщения?", "Remove Messages?"), text: miraLocalizedFakeText(isRussian, "Все добавленные сообщения в этом чате будут удалены.", "All added messages in this chat will be removed."), actions: [
            TextAlertAction(type: .genericAction, title: strings.Common_Cancel, action: {}),
            TextAlertAction(type: .destructiveAction, title: strings.Common_Delete, action: {
                let _ = context.engine.messages.miraRemoveAllFakeMessages(peerId: peerId).start()
            })
        ])
        presentControllerImpl?(controller)
    }, confirmRemove: { record in
        let strings = context.sharedContext.currentPresentationData.with { $0.strings }
        let isRussian = strings.baseLanguageCode.lowercased().hasPrefix("ru")
        let controller = textAlertController(context: context, title: miraLocalizedFakeText(isRussian, "Удалить сообщение?", "Remove Message?"), text: miraLocalizedFakeText(isRussian, "Это сообщение будет удалено из чата.", "This message will be removed from the chat."), actions: [
            TextAlertAction(type: .genericAction, title: strings.Common_Cancel, action: {}),
            TextAlertAction(type: .destructiveAction, title: strings.Common_Delete, action: {
                let _ = context.engine.messages.miraRemoveFakeMessage(id: record.id).start()
            })
        ])
        presentControllerImpl?(controller)
    })

    let signal = combineLatest(context.sharedContext.presentationData, context.account.miraMessageHistoryStore.fakeMessagesChanges)
    |> map { presentationData, records -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let isRussian = presentationData.strings.baseLanguageCode.lowercased().hasPrefix("ru")
        let peerRecords = records.filter { $0.messagePeerId == peerId.toInt64() }.sorted { lhs, rhs in
            if lhs.date == rhs.date {
                return lhs.id < rhs.id
            }
            return lhs.date < rhs.date
        }
        var entries: [MiraFakeMessagesListEntry] = []
        entries.append(.add(miraLocalizedFakeText(isRussian, "Добавить сообщение", "Add Message")))
        entries.append(.choose(miraLocalizedFakeText(isRussian, "Выбрать чат Telegram", "Choose Telegram chat")))
        let countText: String
        if peerRecords.isEmpty {
            countText = miraLocalizedFakeText(isRussian, "Нет сообщений", "No messages")
        } else {
            let noun = miraLocalizedFakeText(isRussian, peerRecords.count == 1 ? "сообщение" : "сообщений", peerRecords.count == 1 ? "message" : "messages")
            countText = "\(peerRecords.count) \(noun)"
        }
        entries.append(.count(countText))
        if peerRecords.isEmpty {
            entries.append(.empty(miraLocalizedFakeText(isRussian, "Сообщений пока нет", "No messages yet.")))
        } else {
            for (index, record) in peerRecords.enumerated() {
                let preview = record.text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                let title: String
                if preview.isEmpty {
                    title = "[\(miraFakeMessageKindTitle(record.kind, isRussian: isRussian))]"
                } else if record.kind == .text {
                    title = String(preview.prefix(80))
                } else {
                    title = "[\(miraFakeMessageKindTitle(record.kind, isRussian: isRussian))] \(String(preview.prefix(64)))"
                }
                let direction: String
                if record.outgoing {
                    direction = miraLocalizedFakeText(isRussian, "От вас", "From you")
                } else if let authorName = record.authorName, !authorName.isEmpty {
                    direction = "\(miraLocalizedFakeText(isRussian, "От", "From")) \(authorName)"
                } else {
                    direction = miraLocalizedFakeText(isRussian, "Из чата", "From chat")
                }
                let readState = record.isRead ? miraLocalizedFakeText(isRussian, "Прочитано", "Read") : miraLocalizedFakeText(isRussian, "Непрочитано", "Unread")
                entries.append(.message(index, record, title, "\(direction) · \(miraFakeMessageKindTitle(record.kind, isRussian: isRussian)) · \(readState) · \(miraFakeMessageListDate(record.date))"))
            }
            entries.append(.removeAll(miraLocalizedFakeText(isRussian, "Удалить все сообщения", "Remove all messages")))
        }

        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text(miraLocalizedFakeText(isRussian, "Сообщения", "Messages")),
            leftNavigationButton: nil,
            rightNavigationButton: ItemListNavigationButton(content: .icon(.add), style: .regular, enabled: true, action: {
                arguments.add()
            }),
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back),
            animateChanges: true
        )
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    pushControllerImpl = { [weak controller] nextController in
        (controller?.navigationController as? NavigationController)?.pushViewController(nextController)
    }
    presentControllerImpl = { [weak controller] alertController in
        controller?.present(alertController, in: .window(.root))
    }
    return controller
}
