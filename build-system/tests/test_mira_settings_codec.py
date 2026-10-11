#!/usr/bin/env python3
"""Exercise real MiraSettings -> PreferencesEntry -> Postbox decoder on macOS."""
import importlib.util
import platform
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

def read(path):
    return (ROOT / path).read_text(encoding="utf-8")

def source():
    spec = importlib.util.spec_from_file_location("store_tests", Path(__file__).with_name("test_mira_stores.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    extract = module.declaration
    settings = read("submodules/TelegramUIPreferences/Sources/MiraSettings.swift")
    cached_user_data = read("submodules/TelegramCore/Sources/SyncCore/SyncCore_CachedUserData.swift")
    postbox = "submodules/Postbox/Sources/"
    # Hashes identify object types in the binary headers. These tests decode
    # through Codable, so the global PostboxCoding type registry is not used.
    fixtures = '''
import Foundation
func murMurHashString32(_ text: String) -> Int32 {
    var hash: UInt32 = 2166136261
    for byte in text.utf8 { hash = (hash ^ UInt32(byte)) &* 16777619 }
    return Int32(bitPattern: hash)
}
func postboxLog(_ text: String) {}
func mdb_cmp_memn(_ lhs: UnsafeRawPointer, _ lhsLength: Int, _ rhs: UnsafeRawPointer, _ rhsLength: Int) -> Int32 {
    let compared = memcmp(lhs, rhs, min(lhsLength, rhsLength))
    return compared == 0 ? (lhsLength == rhsLength ? 0 : (lhsLength < rhsLength ? -1 : 1)) : compared
}
public enum EnginePeer { public typealias Id = PeerId }
'''
    parts = [fixtures, read(postbox + "Coding.swift")]
    for folder in ("Encoder", "Decoder"):
        for path in sorted((ROOT / postbox / "Utils" / folder).glob("AdaptedPostbox*.swift")):
            parts.append(path.read_text(encoding="utf-8"))
    parts.extend([
        extract(read(postbox + "Peer.swift"), "public struct PeerId"),
        extract(read(postbox + "PreferencesEntry.swift"), "public final class PreferencesEntry"),
        read("submodules/TelegramCore/Sources/TelegramEngine/Utils/StringCodingKey.swift"),
        extract(settings, "public struct MiraGhostSettings"),
        extract(settings, "public enum MiraSocialVideoPlatform"),
        extract(settings, "public enum MiraSocialVideoQuality"),
        extract(settings, "public enum MiraSocialVideoDestination"),
        extract(settings, "public struct MiraSocialVideoSettings"),
        extract(settings, "public struct MiraSocialVideoLink"),
        extract(settings, "public enum MiraSocialVideoLinkParser"),
        extract(settings, "public enum MiraLocalPeerRole"),
        extract(settings, "public struct MiraLocalPeerOverride"),
        extract(settings, "public struct MiraSettings"),
        extract(cached_user_data, "public final class TelegramStarRating"),
    ])
    parts = [re.sub(r"^import [^\n]+$", "", part, flags=re.MULTILINE) for part in parts]
    result = "import Foundation\n" + "\n".join(parts)
    tests = '''
func check(_ condition: @autoclosure () -> Bool, _ name: String) {
    if !condition() { fatalError(name) }
}
func roundTrip(_ value: MiraSettings) {
    let entry = PreferencesEntry(value)!
    let decoded = PreferencesEntry(data: entry.data).get(MiraSettings.self)
    check(decoded == value, "settings round trip")
}
roundTrip(.defaultSettings)
let serverRating = TelegramStarRating(level: 2, currentLevelStars: 1000, stars: 2000, nextLevelStars: 3000)
let inLevelRating = serverRating.withUpdatedTotalStars(2500)
check(inLevelRating.level == 2 && inLevelRating.currentLevelStars == 1000 && inLevelRating.nextLevelStars == 3000, "rating remains in its server-supplied range")
let nextLevelRating = serverRating.withUpdatedTotalStars(3000)
check(nextLevelRating.level == 3 && nextLevelRating.currentLevelStars == 3000 && nextLevelRating.nextLevelStars == 5000, "rating advances at the next threshold")
let higherRating = serverRating.withUpdatedTotalStars(3500)
check(higherRating.level == 3 && higherRating.currentLevelStars == 3000 && higherRating.nextLevelStars == 5000, "rating total beyond the cached range is rebased")
let lowerRating = serverRating.withUpdatedTotalStars(500)
check(lowerRating.level == 1 && lowerRating.currentLevelStars == 0 && lowerRating.nextLevelStars == 1000, "rating below the cached range is rebased")
let localBaselineRating = TelegramStarRating(level: 0, currentLevelStars: 0, stars: 0, nextLevelStars: 1000).withUpdatedTotalStars(3500)
check(localBaselineRating.level == 3 && localBaselineRating.currentLevelStars == 3000 && localBaselineRating.nextLevelStars == 4000, "local rating works without server rating data")
var configured = MiraSettings.defaultSettings
var ghost = MiraGhostSettings.defaultSettings
ghost.setGhostModeEnabled(true)
var lockedGhost = MiraGhostSettings.defaultSettings
lockedGhost.sendReadMessagesLocked = true
check(!lockedGhost.isGhostActive, "locked allowed packet does not activate Ghost Mode")
lockedGhost.sendReadMessages = false
check(lockedGhost.isGhostActive, "blocked packet activates Ghost Mode")
configured.ghost = ["0": ghost, "12345": .defaultSettings]
configured.ghostByAccount = ["account:456": ghost, "account:789": .defaultSettings]
roundTrip(configured)
struct OldSettings: Encodable { let localPremium: Bool; let ghost: [String: MiraGhostSettings] }
let migrated = PreferencesEntry(OldSettings(localPremium: true, ghost: ["0": ghost]))!.get(MiraSettings.self)!
check(migrated.localPremium && migrated.ghost["0"] == ghost && migrated.ghostByAccount.isEmpty, "legacy settings migrate")
struct OldVoiceSettings: Encodable { let voiceChangerEnabled: Bool }
let migratedVoice = PreferencesEntry(OldVoiceSettings(voiceChangerEnabled: true))!.get(MiraSettings.self)!
check(migratedVoice.voiceChangerEnabled && migratedVoice.voiceChangerPreset == MiraSettings.defaultVoiceChangerPreset, "enabled legacy voice changer gets a usable preset")
'''
    # Toggle every persisted boolean independently with both empty and populated
    # dictionaries, exactly like each settings action followed by sharedData.
    model = extract(settings, "public struct MiraSettings")
    for name in re.findall(r"public var (\w+): Bool\s*\n", model):
        tests += f"configured.{name}.toggle(); roundTrip(configured)\n"
        tests += f"var empty_{name} = MiraSettings.defaultSettings; empty_{name}.{name}.toggle(); roundTrip(empty_{name})\n"
    tests += '''
configured.fakeStarsBalance = 9000000000
configured.fakeGiftCount = 12345
configured.fakeRatingLevel = 1234
configured.voiceChangerPreset = 13
configured.interfaceFont = 3
configured.avatarCornerStyle = 2
configured.socialVideoSettings.enabled = true
configured.socialVideoSettings.platforms = MiraSocialVideoSettings.allPlatforms
configured.socialVideoSettings.wifiOnly = false
configured.socialVideoSettings.quality = .p1080
configured.socialVideoSettings.confirmBeforeDownload = false
configured.socialVideoSettings.destination = .photos
configured.deletedMark = "🧹 удалено"
configured.editedMark = "изменено"
configured.localPeerOverrides = [
    "123": MiraLocalPeerOverride(username: "@alice", tag: "@editor", phone: "+100", firstName: "Alice", lastName: "Editor", role: .administrator)
]
roundTrip(configured)
check(MiraSettings.defaultSettings.showRealLastSeen == false, "legacy self Last Seen codec remains disabled")
check(configured.localPeerOverride(forPeerId: 123)?.username == "alice", "local peer override username")
check(configured.localPeerOverride(forPeerId: 123)?.tag == "editor", "local peer override tag")
check(configured.localPeerOverride(forPeerId: 123)?.displayName == "Alice Editor", "local peer override display name")
check(configured.localPeerOverride(forPeerId: 123)?.role == .administrator, "local peer override role")
configured.setLocalPeerOverride(MiraLocalPeerOverride(), forPeerId: 123)
check(configured.localPeerOverride(forPeerId: 123) == nil, "empty local peer override removed")
roundTrip(configured)
check(MiraSocialVideoLinkParser.parse("https://youtube.com/shorts/abc")?.platform == .youtube, "YouTube Shorts parser")
check(MiraSocialVideoLinkParser.parse("https://www.instagram.com/share/reel/abc")?.platform == .instagram, "Instagram share parser")
check(MiraSocialVideoLinkParser.parse("https://vm.tiktok.com/abc")?.platform == .tiktok, "TikTok share parser")
check(MiraSocialVideoLinkParser.parse("https://example.com/video/abc") == nil, "unsupported host rejected")
let encoder = PostboxEncoder()
encoder.encodeString("text", forKey: "first")
encoder.encodeInt64(42, forKey: "second")
encoder.encodeNil(forKey: "third")
let decoder = PostboxDecoder(buffer: MemoryBuffer(data: encoder.makeData()))
check(decoder.decodeInt64ForKey("second", orElse: 0) == 42, "cursor before enumeration")
check(decoder.allKeys == ["first", "second", "third"], "all keys enumerate")
check(decoder.decodeStringForKey("first", orElse: "") == "text", "enumeration preserves cursor")
print("Mira settings codec: every toggle and legacy dictionaries passed")
'''
    return result + tests

def main():
    if platform.system() != "Darwin" or shutil.which("swiftc") is None:
        print("SKIP: settings codec executable requires macOS Swift")
        return 0
    with tempfile.TemporaryDirectory(prefix="mira-settings-test-") as temp:
        directory = Path(temp)
        path = directory / "main.swift"
        path.write_text(source(), encoding="utf-8")
        binary = directory / "codec-test"
        subprocess.run(["swiftc", str(path), "-Onone", "-o", str(binary)], check=True)
        subprocess.run([str(binary)], check=True, timeout=30)
        # Reinstall the old allKeys trap in the otherwise identical production
        # code. The same default-settings round trip must reproduce the crash.
        baseline = source().replace("return self.decoder.allKeys.compactMap { Key(stringValue: $0) }", "preconditionFailure()")
        path.write_text(baseline, encoding="utf-8")
        subprocess.run(["swiftc", str(path), "-Onone", "-o", str(binary)], check=True)
        old = subprocess.run([str(binary)], capture_output=True, timeout=30)
        if old.returncode >= 0:
            raise RuntimeError("Original allKeys implementation did not reproduce the expected crash")
        print("Original decoder reproduced crash; repaired decoder passed every toggle")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
