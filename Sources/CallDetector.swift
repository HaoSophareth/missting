import AVFoundation
import AppKit

/// Detects whether the user is in an active call by checking if any app
/// is using the microphone or camera. Requires no extra permissions.
final class CallDetector: ObservableObject {
    static let shared = CallDetector()

    @Published private(set) var isInCall: Bool = false

    private var timer: Timer?

    private init() {
        check()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.check()
        }
        timer?.tolerance = 5

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.check() }
    }

    private func check() {
        let mic = AVCaptureDevice.default(for: .audio)?.isInUseByAnotherApplication ?? false
        let cam = AVCaptureDevice.default(for: .video)?.isInUseByAnotherApplication ?? false
        let inCall = mic || cam
        guard inCall != isInCall else { return }
        let wasInCall = isInCall
        DispatchQueue.main.async {
            self.isInCall = inCall
            // Call just ended — immediately check for in-progress meetings to join
            if wasInCall && !inCall {
                AutoJoinManager.shared.checkInProgressMeetings()
            }
        }
    }
}
