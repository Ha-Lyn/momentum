import Foundation

enum AudioChannel: String, CaseIterable, Codable, Hashable {
    case input
    case output

    var title: String {
        rawValue.capitalized
    }
}

struct AudioChannelSelection {
    private static let defaultsKey = "selectedAudioChannels"

    static func load(from defaults: UserDefaults = .standard) -> Set<AudioChannel> {
        guard
            let values = defaults.array(forKey: defaultsKey) as? [String],
            let channels = decode(values),
            !channels.isEmpty
        else {
            return [.input]
        }

        return channels
    }

    static func persist(_ channels: Set<AudioChannel>, to defaults: UserDefaults = .standard) {
        defaults.set(channels.map(\.rawValue).sorted(), forKey: defaultsKey)
    }

    private static func decode(_ values: [String]) -> Set<AudioChannel>? {
        let channels = Set(values.compactMap(AudioChannel.init(rawValue:)))
        return channels.count == values.count ? channels : nil
    }
}
