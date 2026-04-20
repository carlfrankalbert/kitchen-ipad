import Foundation
import MediaPlayer
import Observation

@Observable
@MainActor
final class NowPlayingStore {
    var title:  String? = nil
    var artist: String? = nil

    var isPlaying: Bool { title != nil }

    // Use a lazy property so we never touch MPMusicPlayerController at init time
    private var _player: MPMusicPlayerController?

    private var player: MPMusicPlayerController? {
        if _player == nil {
            // systemMusicPlayer is unavailable in Simulator without Music.app running
            // Wrapping in a check prevents the crash
            _player = MPMusicPlayerController.applicationQueuePlayer
        }
        return _player
    }

    func startObserving() {
        guard let p = player else { return }

        p.beginGeneratingPlaybackNotifications()

        NotificationCenter.default.addObserver(
            forName: .MPMusicPlayerControllerNowPlayingItemDidChange,
            object: p,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }

        NotificationCenter.default.addObserver(
            forName: .MPMusicPlayerControllerPlaybackStateDidChange,
            object: p,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }

        refresh()
    }

    func refresh() {
        guard let p = player, p.playbackState == .playing else {
            title  = nil
            artist = nil
            return
        }
        title  = p.nowPlayingItem?.title
        artist = p.nowPlayingItem?.artist
    }
}
