import AVFoundation
import SwiftUI

/// Звуки и музыка. Файлы синтезирует tools/make_sounds.py. Музыка тихая и не глушит музыку
/// других приложений (категория ambient), звуки можно выключить в настройках.
@MainActor
final class Audio: ObservableObject {
    static let shared = Audio()

    enum Sound: String, CaseIterable {
        case spawn, merge, drop, coins, build, levelup, nope, sparkle
    }

    @AppStorage("soundOn") var soundOn = true { didSet { objectWillChange.send() } }
    @AppStorage("musicOn") var musicOn = true { didSet { objectWillChange.send(); updateMusic() } }
    @AppStorage("hapticsOn") var hapticsOn = true { didSet { objectWillChange.send() } }

    private var players: [Sound: [AVAudioPlayer]] = [:]
    private var music: AVAudioPlayer?

    private init() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        for sound in Sound.allCases {
            guard let url = Bundle.main.url(forResource: sound.rawValue, withExtension: "m4a") else { continue }
            // несколько копий, чтобы быстрые слияния не обрывали друг друга
            players[sound] = (0..<3).compactMap { _ in
                let p = try? AVAudioPlayer(contentsOf: url)
                p?.prepareToPlay()
                p?.volume = 0.7
                return p
            }
        }
        if let url = Bundle.main.url(forResource: "music", withExtension: "m4a") {
            music = try? AVAudioPlayer(contentsOf: url)
            music?.numberOfLoops = -1
            music?.volume = 0.35
        }
    }

    func play(_ sound: Sound) {
        guard soundOn, let pool = players[sound] else { return }
        let player = pool.first { !$0.isPlaying } ?? pool.first
        player?.currentTime = 0
        player?.play()
    }

    func startMusic() { updateMusic() }

    private func updateMusic() {
        guard let music else { return }
        if musicOn, !music.isPlaying {
            music.volume = 0
            music.play()
            music.setVolume(0.35, fadeDuration: 2)
        } else if !musicOn, music.isPlaying {
            music.pause()
        }
    }
}
