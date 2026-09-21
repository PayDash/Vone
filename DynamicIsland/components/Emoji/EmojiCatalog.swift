/*
 * Vone (DynamicIsland)
 * Copyright (C) 2024-2026 Vone Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

#if os(macOS)
import Foundation

enum EmojiCategory: String, CaseIterable, Identifiable {
    case smileys
    case people
    case animals
    case food
    case activity
    case travel
    case objects
    case symbols

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smileys: return String(localized: "Smileys")
        case .people: return String(localized: "People")
        case .animals: return String(localized: "Nature")
        case .food: return String(localized: "Food")
        case .activity: return String(localized: "Activity")
        case .travel: return String(localized: "Travel")
        case .objects: return String(localized: "Objects")
        case .symbols: return String(localized: "Symbols")
        }
    }

    var systemImage: String {
        switch self {
        case .smileys: return "face.smiling"
        case .people: return "person"
        case .animals: return "pawprint"
        case .food: return "fork.knife"
        case .activity: return "figure.run"
        case .travel: return "airplane"
        case .objects: return "lightbulb"
        case .symbols: return "heart"
        }
    }
}

struct EmojiEntry: Identifiable, Hashable {
    var id: String { value }
    let value: String
    let name: String
    var keywords: [String] = []
    let category: EmojiCategory

    func matches(_ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        let needle = query.lowercased()
        if name.lowercased().contains(needle) { return true }
        return keywords.contains { $0.lowercased().contains(needle) }
    }
}

/// Curated set of common emoji with searchable keywords. Deliberately hand-kept
/// rather than generated so every entry has useful search terms.
enum EmojiCatalog {
    static let all: [EmojiEntry] = smileys + people + animals + food + activity + travel + objects + symbols

    static func entries(in category: EmojiCategory) -> [EmojiEntry] {
        all.filter { $0.category == category }
    }

    static func search(_ query: String) -> [EmojiEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        return all.filter { $0.matches(trimmed) }
    }

    // MARK: Categories

    private static let smileys: [EmojiEntry] = [
        .init(value: "😀", name: "grinning", keywords: ["smile", "happy"], category: .smileys),
        .init(value: "😃", name: "smiley", keywords: ["smile", "happy"], category: .smileys),
        .init(value: "😄", name: "smile", keywords: ["happy", "grin"], category: .smileys),
        .init(value: "😁", name: "beaming", keywords: ["grin", "happy"], category: .smileys),
        .init(value: "😆", name: "laughing", keywords: ["lol", "haha"], category: .smileys),
        .init(value: "😅", name: "sweat smile", keywords: ["phew", "relief"], category: .smileys),
        .init(value: "🤣", name: "rofl", keywords: ["laugh", "lol"], category: .smileys),
        .init(value: "😂", name: "joy", keywords: ["laugh", "tears"], category: .smileys),
        .init(value: "🙂", name: "slight smile", keywords: ["ok", "fine"], category: .smileys),
        .init(value: "😉", name: "wink", keywords: ["flirt", "joke"], category: .smileys),
        .init(value: "😊", name: "blush", keywords: ["happy", "shy"], category: .smileys),
        .init(value: "😇", name: "innocent", keywords: ["angel", "halo"], category: .smileys),
        .init(value: "🥰", name: "love", keywords: ["hearts", "adore"], category: .smileys),
        .init(value: "😍", name: "heart eyes", keywords: ["love", "crush"], category: .smileys),
        .init(value: "🤩", name: "star struck", keywords: ["wow", "amazed"], category: .smileys),
        .init(value: "😘", name: "kiss", keywords: ["love"], category: .smileys),
        .init(value: "😗", name: "kissing", keywords: ["whistle"], category: .smileys),
        .init(value: "🤔", name: "thinking", keywords: ["hmm", "consider"], category: .smileys),
        .init(value: "🤨", name: "raised eyebrow", keywords: ["skeptical", "doubt"], category: .smileys),
        .init(value: "😐", name: "neutral", keywords: ["meh", "blank"], category: .smileys),
        .init(value: "😑", name: "expressionless", keywords: ["blank"], category: .smileys),
        .init(value: "🙄", name: "eye roll", keywords: ["whatever", "annoyed"], category: .smileys),
        .init(value: "😏", name: "smirk", keywords: ["smug"], category: .smileys),
        .init(value: "😴", name: "sleeping", keywords: ["zzz", "tired"], category: .smileys),
        .init(value: "😢", name: "cry", keywords: ["sad", "tear"], category: .smileys),
        .init(value: "😭", name: "sob", keywords: ["sad", "crying"], category: .smileys),
        .init(value: "😤", name: "triumph", keywords: ["frustrated", "huff"], category: .smileys),
        .init(value: "😠", name: "angry", keywords: ["mad"], category: .smileys),
        .init(value: "🤯", name: "exploding head", keywords: ["mind blown", "shock"], category: .smileys),
        .init(value: "😱", name: "scream", keywords: ["shock", "fear"], category: .smileys),
        .init(value: "😳", name: "flushed", keywords: ["embarrassed", "shy"], category: .smileys),
        .init(value: "🥺", name: "pleading", keywords: ["please", "puppy"], category: .smileys),
        .init(value: "😎", name: "cool", keywords: ["sunglasses", "awesome"], category: .smileys),
        .init(value: "🤓", name: "nerd", keywords: ["geek", "glasses"], category: .smileys),
        .init(value: "🥳", name: "party face", keywords: ["celebrate", "birthday"], category: .smileys),
        .init(value: "😬", name: "grimace", keywords: ["awkward", "yikes"], category: .smileys),
        .init(value: "🙃", name: "upside down", keywords: ["silly", "irony"], category: .smileys),
        .init(value: "🫠", name: "melting", keywords: ["hot", "embarrassed"], category: .smileys),
        .init(value: "🤝", name: "handshake", keywords: ["deal", "agreement"], category: .smileys),
    ]

    private static let people: [EmojiEntry] = [
        .init(value: "👋", name: "wave", keywords: ["hello", "hi", "bye"], category: .people),
        .init(value: "👍", name: "thumbs up", keywords: ["yes", "ok", "like"], category: .people),
        .init(value: "👎", name: "thumbs down", keywords: ["no", "dislike"], category: .people),
        .init(value: "👌", name: "ok hand", keywords: ["perfect", "nice"], category: .people),
        .init(value: "🙏", name: "pray", keywords: ["thanks", "please"], category: .people),
        .init(value: "👏", name: "clap", keywords: ["applause", "bravo"], category: .people),
        .init(value: "🙌", name: "raised hands", keywords: ["celebrate", "hooray"], category: .people),
        .init(value: "💪", name: "flexed biceps", keywords: ["strong", "gym"], category: .people),
        .init(value: "🤞", name: "crossed fingers", keywords: ["luck", "hope"], category: .people),
        .init(value: "✌️", name: "victory", keywords: ["peace", "two"], category: .people),
        .init(value: "🤟", name: "love you gesture", keywords: ["sign"], category: .people),
        .init(value: "👀", name: "eyes", keywords: ["look", "watching"], category: .people),
        .init(value: "🧠", name: "brain", keywords: ["think", "smart"], category: .people),
        .init(value: "👶", name: "baby", keywords: ["child"], category: .people),
        .init(value: "🧑", name: "person", keywords: ["user"], category: .people),
        .init(value: "👩", name: "woman", keywords: ["female"], category: .people),
        .init(value: "👨", name: "man", keywords: ["male"], category: .people),
        .init(value: "🧑‍💻", name: "technologist", keywords: ["developer", "coder"], category: .people),
        .init(value: "🧑‍🎓", name: "student", keywords: ["graduate"], category: .people),
        .init(value: "🕺", name: "dancer", keywords: ["dance", "party"], category: .people),
    ]

    private static let animals: [EmojiEntry] = [
        .init(value: "🐶", name: "dog", keywords: ["puppy", "pet"], category: .animals),
        .init(value: "🐱", name: "cat", keywords: ["kitten", "pet"], category: .animals),
        .init(value: "🐭", name: "mouse", keywords: ["rodent"], category: .animals),
        .init(value: "🐹", name: "hamster", keywords: ["pet"], category: .animals),
        .init(value: "🐰", name: "rabbit", keywords: ["bunny"], category: .animals),
        .init(value: "🦊", name: "fox", keywords: ["animal"], category: .animals),
        .init(value: "🐻", name: "bear", keywords: ["animal"], category: .animals),
        .init(value: "🐼", name: "panda", keywords: ["animal"], category: .animals),
        .init(value: "🐨", name: "koala", keywords: ["animal"], category: .animals),
        .init(value: "🦁", name: "lion", keywords: ["animal"], category: .animals),
        .init(value: "🐮", name: "cow", keywords: ["animal"], category: .animals),
        .init(value: "🐷", name: "pig", keywords: ["animal"], category: .animals),
        .init(value: "🐸", name: "frog", keywords: ["animal"], category: .animals),
        .init(value: "🐵", name: "monkey", keywords: ["animal"], category: .animals),
        .init(value: "🐔", name: "chicken", keywords: ["bird"], category: .animals),
        .init(value: "🐧", name: "penguin", keywords: ["bird"], category: .animals),
        .init(value: "🦄", name: "unicorn", keywords: ["magic"], category: .animals),
        .init(value: "🐝", name: "bee", keywords: ["insect", "honey"], category: .animals),
        .init(value: "🦋", name: "butterfly", keywords: ["insect"], category: .animals),
        .init(value: "🌱", name: "seedling", keywords: ["plant", "grow"], category: .animals),
        .init(value: "🌲", name: "tree", keywords: ["forest"], category: .animals),
        .init(value: "🌵", name: "cactus", keywords: ["desert"], category: .animals),
        .init(value: "🌊", name: "wave water", keywords: ["ocean", "sea"], category: .animals),
        .init(value: "🔥", name: "fire", keywords: ["hot", "lit"], category: .animals),
        .init(value: "⭐", name: "star", keywords: ["favourite", "favorite"], category: .animals),
        .init(value: "🌈", name: "rainbow", keywords: ["pride", "weather"], category: .animals),
        .init(value: "☀️", name: "sun", keywords: ["sunny", "weather"], category: .animals),
        .init(value: "🌙", name: "moon", keywords: ["night"], category: .animals),
        .init(value: "❄️", name: "snowflake", keywords: ["cold", "winter"], category: .animals),
    ]

    private static let food: [EmojiEntry] = [
        .init(value: "🍎", name: "apple", keywords: ["fruit"], category: .food),
        .init(value: "🍌", name: "banana", keywords: ["fruit"], category: .food),
        .init(value: "🍇", name: "grapes", keywords: ["fruit"], category: .food),
        .init(value: "🍓", name: "strawberry", keywords: ["fruit"], category: .food),
        .init(value: "🍕", name: "pizza", keywords: ["food"], category: .food),
        .init(value: "🍔", name: "burger", keywords: ["food"], category: .food),
        .init(value: "🍟", name: "fries", keywords: ["food"], category: .food),
        .init(value: "🌮", name: "taco", keywords: ["food"], category: .food),
        .init(value: "🍣", name: "sushi", keywords: ["food"], category: .food),
        .init(value: "🍜", name: "ramen", keywords: ["noodles", "food"], category: .food),
        .init(value: "🍰", name: "cake", keywords: ["dessert", "birthday"], category: .food),
        .init(value: "🍪", name: "cookie", keywords: ["biscuit", "snack"], category: .food),
        .init(value: "🍫", name: "chocolate", keywords: ["sweet"], category: .food),
        .init(value: "☕", name: "coffee", keywords: ["drink", "caffeine"], category: .food),
        .init(value: "🍵", name: "tea", keywords: ["drink"], category: .food),
        .init(value: "🍺", name: "beer", keywords: ["drink", "pub"], category: .food),
        .init(value: "🍷", name: "wine", keywords: ["drink"], category: .food),
        .init(value: "🥂", name: "cheers", keywords: ["celebrate", "toast"], category: .food),
    ]

    private static let activity: [EmojiEntry] = [
        .init(value: "⚽", name: "football", keywords: ["soccer", "sport"], category: .activity),
        .init(value: "🏀", name: "basketball", keywords: ["sport"], category: .activity),
        .init(value: "🏈", name: "american football", keywords: ["sport"], category: .activity),
        .init(value: "🎾", name: "tennis", keywords: ["sport"], category: .activity),
        .init(value: "🏃", name: "running", keywords: ["run", "exercise"], category: .activity),
        .init(value: "🚴", name: "cycling", keywords: ["bike"], category: .activity),
        .init(value: "🏆", name: "trophy", keywords: ["win", "award"], category: .activity),
        .init(value: "🎯", name: "target", keywords: ["goal", "dart"], category: .activity),
        .init(value: "🎮", name: "game", keywords: ["gaming", "controller"], category: .activity),
        .init(value: "🎲", name: "dice", keywords: ["game", "random"], category: .activity),
        .init(value: "🎵", name: "music note", keywords: ["song", "audio"], category: .activity),
        .init(value: "🎉", name: "party popper", keywords: ["celebrate", "congrats"], category: .activity),
        .init(value: "🎈", name: "balloon", keywords: ["party", "birthday"], category: .activity),
        .init(value: "🎁", name: "gift", keywords: ["present"], category: .activity),
    ]

    private static let travel: [EmojiEntry] = [
        .init(value: "🚗", name: "car", keywords: ["drive", "vehicle"], category: .travel),
        .init(value: "🚕", name: "taxi", keywords: ["cab"], category: .travel),
        .init(value: "🚌", name: "bus", keywords: ["transport"], category: .travel),
        .init(value: "🚀", name: "rocket", keywords: ["launch", "ship"], category: .travel),
        .init(value: "✈️", name: "airplane", keywords: ["flight", "travel"], category: .travel),
        .init(value: "🚂", name: "train", keywords: ["rail"], category: .travel),
        .init(value: "🚲", name: "bicycle", keywords: ["bike"], category: .travel),
        .init(value: "🏠", name: "house", keywords: ["home"], category: .travel),
        .init(value: "🏢", name: "office", keywords: ["building", "work"], category: .travel),
        .init(value: "🗺️", name: "map", keywords: ["travel", "directions"], category: .travel),
        .init(value: "📍", name: "pin", keywords: ["location", "place"], category: .travel),
        .init(value: "🌍", name: "earth", keywords: ["world", "globe"], category: .travel),
    ]

    private static let objects: [EmojiEntry] = [
        .init(value: "💻", name: "laptop", keywords: ["computer", "mac"], category: .objects),
        .init(value: "🖥️", name: "desktop computer", keywords: ["monitor", "display"], category: .objects),
        .init(value: "⌨️", name: "keyboard", keywords: ["typing"], category: .objects),
        .init(value: "🖱️", name: "mouse", keywords: ["pointer", "click"], category: .objects),
        .init(value: "📱", name: "phone", keywords: ["mobile", "iphone"], category: .objects),
        .init(value: "⌚", name: "watch", keywords: ["time", "wearable"], category: .objects),
        .init(value: "💡", name: "bulb", keywords: ["idea", "light"], category: .objects),
        .init(value: "🔑", name: "key", keywords: ["password", "lock"], category: .objects),
        .init(value: "🔒", name: "lock", keywords: ["secure", "private"], category: .objects),
        .init(value: "🔧", name: "wrench", keywords: ["tool", "fix"], category: .objects),
        .init(value: "🔨", name: "hammer", keywords: ["tool", "build"], category: .objects),
        .init(value: "⚙️", name: "gear", keywords: ["settings", "config"], category: .objects),
        .init(value: "📦", name: "package", keywords: ["box", "shipping"], category: .objects),
        .init(value: "📁", name: "folder", keywords: ["directory", "files"], category: .objects),
        .init(value: "📄", name: "document", keywords: ["file", "page"], category: .objects),
        .init(value: "📝", name: "memo", keywords: ["note", "write"], category: .objects),
        .init(value: "📌", name: "pushpin", keywords: ["pin", "important"], category: .objects),
        .init(value: "✏️", name: "pencil", keywords: ["edit", "write"], category: .objects),
        .init(value: "🔍", name: "magnifier", keywords: ["search", "find"], category: .objects),
        .init(value: "⏰", name: "alarm", keywords: ["clock", "timer"], category: .objects),
        .init(value: "⏳", name: "hourglass", keywords: ["wait", "time"], category: .objects),
        .init(value: "📷", name: "camera", keywords: ["photo", "picture"], category: .objects),
        .init(value: "🎤", name: "microphone", keywords: ["record", "audio"], category: .objects),
        .init(value: "🎧", name: "headphones", keywords: ["music", "audio"], category: .objects),
        .init(value: "💰", name: "money bag", keywords: ["cash", "cost"], category: .objects),
        .init(value: "📊", name: "bar chart", keywords: ["stats", "analytics"], category: .objects),
        .init(value: "📈", name: "chart up", keywords: ["growth", "increase"], category: .objects),
        .init(value: "🗑️", name: "wastebasket", keywords: ["trash", "delete"], category: .objects),
    ]

    private static let symbols: [EmojiEntry] = [
        .init(value: "❤️", name: "red heart", keywords: ["love", "like"], category: .symbols),
        .init(value: "🧡", name: "orange heart", keywords: ["love"], category: .symbols),
        .init(value: "💛", name: "yellow heart", keywords: ["love"], category: .symbols),
        .init(value: "💚", name: "green heart", keywords: ["love"], category: .symbols),
        .init(value: "💙", name: "blue heart", keywords: ["love"], category: .symbols),
        .init(value: "💜", name: "purple heart", keywords: ["love"], category: .symbols),
        .init(value: "🖤", name: "black heart", keywords: ["love"], category: .symbols),
        .init(value: "🤍", name: "white heart", keywords: ["love"], category: .symbols),
        .init(value: "💔", name: "broken heart", keywords: ["sad", "breakup"], category: .symbols),
        .init(value: "✅", name: "check", keywords: ["done", "tick", "yes"], category: .symbols),
        .init(value: "❌", name: "cross", keywords: ["no", "wrong", "close"], category: .symbols),
        .init(value: "⚠️", name: "warning", keywords: ["caution", "alert"], category: .symbols),
        .init(value: "❗", name: "exclamation", keywords: ["important"], category: .symbols),
        .init(value: "❓", name: "question", keywords: ["help", "unknown"], category: .symbols),
        .init(value: "💯", name: "hundred", keywords: ["perfect", "score"], category: .symbols),
        .init(value: "🔥", name: "flame", keywords: ["hot", "trending"], category: .symbols),
        .init(value: "✨", name: "sparkles", keywords: ["new", "shine"], category: .symbols),
        .init(value: "⚡", name: "zap", keywords: ["fast", "power", "energy"], category: .symbols),
        .init(value: "🐛", name: "bug", keywords: ["issue", "debug"], category: .symbols),
        .init(value: "🚧", name: "construction", keywords: ["wip", "work in progress"], category: .symbols),
        .init(value: "🔴", name: "red circle", keywords: ["dot", "record"], category: .symbols),
        .init(value: "🟢", name: "green circle", keywords: ["dot", "online"], category: .symbols),
        .init(value: "⏸️", name: "pause", keywords: ["stop", "break"], category: .symbols),
        .init(value: "▶️", name: "play", keywords: ["start", "go"], category: .symbols),
        .init(value: "⏹️", name: "stop", keywords: ["end", "halt"], category: .symbols),
        .init(value: "🔄", name: "refresh", keywords: ["reload", "sync"], category: .symbols),
        .init(value: "🔗", name: "link", keywords: ["url", "chain"], category: .symbols),
        .init(value: "1️⃣", name: "one", keywords: ["number", "first"], category: .symbols),
        .init(value: "2️⃣", name: "two", keywords: ["number", "second"], category: .symbols),
        .init(value: "3️⃣", name: "three", keywords: ["number", "third"], category: .symbols),
    ]
}
#endif
