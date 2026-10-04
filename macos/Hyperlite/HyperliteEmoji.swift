import Foundation

/// GitHub emoji shortcodes (`:sparkles:`) rendered as emoji. Covers the full
/// gitmoji set used in commit-style titles plus common GitHub emoji; unknown
/// shortcodes stay as written.
enum HyperliteEmoji {
    static func render(_ text: String) -> String {
        guard text.contains(":") else { return text }
        var result = ""
        var rest = Substring(text)
        while let start = rest.firstIndex(of: ":") {
            result += rest[..<start]
            let afterColon = rest.index(after: start)
            guard let end = rest[afterColon...].firstIndex(of: ":") else {
                result += rest[start...]
                return result
            }
            let name = rest[afterColon..<end]
            if let emoji = shortcodes[String(name)], name.allSatisfy(isShortcodeCharacter) {
                result += emoji
                rest = rest[rest.index(after: end)...]
            } else {
                result += ":"
                rest = rest[afterColon...]
            }
        }
        return result + rest
    }

    private static func isShortcodeCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_" || character == "+" || character == "-"
    }

    static let shortcodes: [String: String] = [
        // gitmoji
        "art": "🎨", "zap": "⚡️", "fire": "🔥", "bug": "🐛", "ambulance": "🚑️", "sparkles": "✨",
        "memo": "📝", "rocket": "🚀", "lipstick": "💄", "tada": "🎉", "white_check_mark": "✅",
        "lock": "🔒️", "closed_lock_with_key": "🔐", "bookmark": "🔖", "rotating_light": "🚨",
        "construction": "🚧", "green_heart": "💚", "arrow_down": "⬇️", "arrow_up": "⬆️", "pushpin": "📌",
        "construction_worker": "👷", "chart_with_upwards_trend": "📈", "recycle": "♻️", "heavy_plus_sign": "➕",
        "heavy_minus_sign": "➖", "wrench": "🔧", "hammer": "🔨", "globe_with_meridians": "🌐", "pencil2": "✏️",
        "poop": "💩", "rewind": "⏪️", "twisted_rightwards_arrows": "🔀", "package": "📦️", "alien": "👽️",
        "truck": "🚚", "page_facing_up": "📄", "boom": "💥", "bento": "🍱", "wheelchair": "♿️", "bulb": "💡",
        "beers": "🍻", "speech_balloon": "💬", "card_file_box": "🗃️", "loud_sound": "🔊", "mute": "🔇",
        "busts_in_silhouette": "👥", "children_crossing": "🚸", "building_construction": "🏗️", "iphone": "📱",
        "clown_face": "🤡", "egg": "🥚", "see_no_evil": "🙈", "camera_flash": "📸", "alembic": "⚗️", "mag": "🔍️",
        "label": "🏷️", "seedling": "🌱", "triangular_flag_on_post": "🚩", "goal_net": "🥅", "dizzy": "💫",
        "wastebasket": "🗑️", "passport_control": "🛂", "adhesive_bandage": "🩹", "monocle_face": "🧐",
        "coffin": "⚰️", "test_tube": "🧪", "necktie": "👔", "stethoscope": "🩺", "bricks": "🧱",
        "technologist": "🧑‍💻", "money_with_wings": "💸", "thread": "🧵", "safety_vest": "🦺", "airplane": "✈️",
        "lock_with_ink_pen": "🔏", "pencil": "📝",
        // common GitHub emoji
        "+1": "👍", "thumbsup": "👍", "-1": "👎", "thumbsdown": "👎", "heart": "❤️", "warning": "⚠️",
        "x": "❌", "heavy_check_mark": "✔️", "white_check_mark_button": "✅", "question": "❓",
        "exclamation": "❗", "eyes": "👀", "point_right": "👉", "star": "⭐️", "smile": "😄", "laughing": "😆",
        "thinking": "🤔", "pray": "🙏", "clap": "👏", "100": "💯", "no_entry": "⛔️", "stop_sign": "🛑",
        "hourglass": "⌛️", "hourglass_flowing_sand": "⏳", "lock_open": "🔓", "key": "🔑", "link": "🔗",
        "gear": "⚙️", "books": "📚", "book": "📖", "clipboard": "📋", "calendar": "📅", "chart": "💹",
        "bar_chart": "📊", "fast_forward": "⏩", "arrows_counterclockwise": "🔄", "information_source": "ℹ️",
        "rotating_light_siren": "🚨", "robot": "🤖", "shield": "🛡️", "dart": "🎯", "trophy": "🏆",
        "partying_face": "🥳", "zzz": "💤", "skull": "💀", "ghost": "👻", "crystal_ball": "🔮",
        "electric_plug": "🔌", "satellite": "📡", "floppy_disk": "💾", "inbox_tray": "📥", "outbox_tray": "📤",
        "mailbox": "📫", "bell": "🔔", "no_bell": "🔕", "hammer_and_wrench": "🛠️", "microscope": "🔬",
        "dna": "🧬", "scroll": "📜", "new": "🆕", "up": "🆙", "cool": "🆒", "free": "🆓", "ok": "🆗",
        "heavy_exclamation_mark": "❗", "grey_question": "❔", "arrow_right": "➡️", "arrow_left": "⬅️",
    ]
}
