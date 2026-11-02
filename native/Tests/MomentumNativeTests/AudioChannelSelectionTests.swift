import Foundation
import Testing
@testable import MomentumNative

@Suite("AudioChannelSelection")
struct AudioChannelSelectionTests {
    private static let defaultsKey = "selectedAudioChannels"

    @Test func defaultsToInput() {
        withIsolatedDefaults { defaults in
            #expect(AudioChannelSelection.load(from: defaults) == [.input])
        }
    }

    @Test(arguments: [
        Set<AudioChannel>([.input]),
        [.output],
        [.input, .output],
    ])
    func persistAndLoadRoundTrip(channels: Set<AudioChannel>) {
        withIsolatedDefaults { defaults in
            AudioChannelSelection.persist(channels, to: defaults)
            #expect(AudioChannelSelection.load(from: defaults) == channels)
        }
    }

    @Test func persistsSortedRawValues() {
        withIsolatedDefaults { defaults in
            AudioChannelSelection.persist([.output, .input], to: defaults)
            #expect(defaults.array(forKey: Self.defaultsKey) as? [String] == ["input", "output"])
        }
    }

    @Test func emptySelectionFallsBackToInput() {
        withIsolatedDefaults { defaults in
            AudioChannelSelection.persist([], to: defaults)
            #expect(AudioChannelSelection.load(from: defaults) == [.input])
        }
    }

    @Test func unknownValueFallsBackToInput() {
        withIsolatedDefaults { defaults in
            defaults.set(["output", "bogus"], forKey: Self.defaultsKey)
            #expect(AudioChannelSelection.load(from: defaults) == [.input])
        }
    }

    @Test func wrongTypeFallsBackToInput() {
        withIsolatedDefaults { defaults in
            defaults.set("output", forKey: Self.defaultsKey)
            #expect(AudioChannelSelection.load(from: defaults) == [.input])
        }
    }

    @Test func titleIsCapitalized() {
        #expect(AudioChannel.input.title == "Input")
        #expect(AudioChannel.output.title == "Output")
    }
}
