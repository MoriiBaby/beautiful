import Foundation
import UIKit

// New minimal-window interaction design, NOT a claim to reproduce original gesture physics.
// This controller cannot present anything until the real scene provider reports ready AND attaches.
enum SRFloatingError: LocalizedError {
    case unavailable(String)
    case invalidBundle
    var errorDescription: String? {
        switch self {
        case .unavailable(let reason): return reason
        case .invalidBundle: return "A nonempty bundle identifier is required."
        }
    }
}

final class SRFloatingCoordinator {
    static let shared = SRFloatingCoordinator()
    private var controllers: [String: SRFloatingController] = [:]

    func open(bundleIdentifier: String, completion: @escaping (Error?) -> Void) {
        precondition(Thread.isMainThread)
        guard !bundleIdentifier.isEmpty else {
            DispatchQueue.main.async { completion(SRFloatingError.invalidBundle) }; return
        }
        guard SRMainSceneHostingAvailable() else {
            let error = SRFloatingError.unavailable(SRMainSceneHostingBlocker())
            DispatchQueue.main.async { completion(error) }; return
        }
        if let existing = controllers[bundleIdentifier] {
            existing.attachAndPresent(completion: completion)
            return
        }
        let controller = SRFloatingController(bundleIdentifier: bundleIdentifier)
        // Retain while asynchronous acquisition is pending; closeAll cancels pending starts too.
        controllers[bundleIdentifier] = controller
        controller.onClosed = { [weak self, weak controller] in
            guard let self = self, self.controllers[bundleIdentifier] === controller else { return }
            self.controllers.removeValue(forKey: bundleIdentifier)
        }
        controller.attachAndPresent(completion: completion)
    }

    func closeAll() {
        precondition(Thread.isMainThread)
        // Copy before callbacks mutate the registry.
        for controller in Array(controllers.values) { controller.close() }
    }
}

private final class SRFloatingController: UIViewController {
    private let bundleIdentifier: String
    private let sceneSession = SRMainCreateSceneSession()
    private var floatingWindow: UIWindow?
    private let appContainer = UIView()
    private let header = UIView()
    private enum Phase { case idle, opening, attached, closing, closed }
    private var phase: Phase = .idle
    private var panOrigin = CGPoint.zero
    private var pinchSize = CGSize.zero
    private var openCompletions: [(Error?) -> Void] = []
    private var resizeInFlight = false
    private var queuedFrame: CGRect?
    private var displayGeneration: UInt64 = 0
    var onClosed: (() -> Void)?

    init(bundleIdentifier: String) {
        self.bundleIdentifier = bundleIdentifier
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { return nil }

    override func loadView() {
        view = UIView()
        view.backgroundColor = .secondarySystemBackground
        view.layer.cornerRadius = 16
        view.clipsToBounds = true
        header.backgroundColor = .tertiarySystemBackground
        let title = UILabel()
        title.text = bundleIdentifier
        title.font = .systemFont(ofSize: 12, weight: .medium)
        title.lineBreakMode = .byTruncatingMiddle
        let close = UIButton(type: .system)
        close.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        close.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        for child in [header, appContainer, title, close] { child.translatesAutoresizingMaskIntoConstraints = false }
        view.addSubview(header); view.addSubview(appContainer)
        header.addSubview(title); header.addSubview(close)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.topAnchor),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 36),
            appContainer.topAnchor.constraint(equalTo: header.bottomAnchor),
            appContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            appContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            appContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            close.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -8),
            close.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            close.widthAnchor.constraint(equalToConstant: 28), close.heightAnchor.constraint(equalToConstant: 28),
            title.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 12),
            title.trailingAnchor.constraint(equalTo: close.leadingAnchor, constant: -8),
            title.centerYAnchor.constraint(equalTo: header.centerYAnchor)
        ])
        header.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(drag(_:))))
        header.addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(resize(_:))))
    }

    func attachAndPresent(completion: @escaping (Error?) -> Void) {
        precondition(Thread.isMainThread)
        if phase == .attached {
            floatingWindow?.isHidden = false
            DispatchQueue.main.async { completion(nil) }; return
        }
        if phase == .opening { openCompletions.append(completion); return }
        guard phase == .idle else {
            DispatchQueue.main.async { completion(SRFloatingError.unavailable("Session is closing or closed.")) }; return
        }
        guard SRMainSceneHostingAvailable() else {
            phase = .closed
            DispatchQueue.main.async { completion(SRFloatingError.unavailable(SRMainSceneHostingBlocker())) }
            onClosed?()
            onClosed = nil
            return
        }
        phase = .opening
        openCompletions.append(completion)
        loadViewIfNeeded()
        let screen = UIScreen.main.bounds
        let width = min(320, screen.width * 0.85)
        let height = min(520, screen.height * 0.8)
        var frame = CGRect(x: screen.midX - width / 2, y: screen.midY - height / 2,
                           width: width, height: height)
        guard SRMainConstrainWindow(frame, screen, &frame) else {
            finishOpen(SRFloatingError.unavailable("Invalid display geometry.")); close(); return
        }
        let window = UIWindow(frame: frame)
        window.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.normal.rawValue + 2)
        window.rootViewController = self
        view.frame = window.bounds
        view.layoutIfNeeded()
        // Hidden UIWindow supplies a real UIKit window hierarchy during asynchronous preparation.
        // Do not makeKeyAndVisible: focus/input routing is NOT implicitly claimed by drawing layers.
        window.isHidden = true
        floatingWindow = window
        SRMainSetInvalidationHandler(sceneSession) { [weak self] error in
            guard let self = self else { return }
            self.finishOpen(error ?? SRFloatingError.unavailable("Scene invalidated."))
            self.close()
        }
        SRMainAttachSceneAsync(sceneSession, bundleIdentifier, appContainer) { [weak self, weak window] error in
            guard let self = self else { return }
            guard self.phase == .opening else { return } // closed/cancelled generation never reveals a window
            if let error = error { self.finishOpen(error); self.close(); return }
            guard let window = window, window === self.floatingWindow else {
                self.finishOpen(SRFloatingError.unavailable("Window identity changed.")); self.close(); return
            }
            self.phase = .attached
            window.isHidden = false // only after actual host views are attached
            self.finishOpen(nil)
        }
    }

    private func finishOpen(_ error: Error?) {
        let callbacks = openCompletions
        openCompletions.removeAll()
        for callback in callbacks {
            DispatchQueue.main.async { [weak self] in
                if error == nil && self?.phase != .attached {
                    callback(SRFloatingError.unavailable("Opening was cancelled before callback delivery."))
                } else { callback(error) }
            }
        }
    }

    func close() {
        precondition(Thread.isMainThread)
        guard phase != .closing && phase != .closed else { return }
        phase = .closing
        displayGeneration &+= 1
        queuedFrame = nil
        floatingWindow?.isHidden = true
        finishOpen(SRFloatingError.unavailable("Window was closed before its opening completed."))
        SRMainCloseSceneAsync(sceneSession) { [weak self] error in
            guard let self = self, self.phase == .closing else { return }
            if let error = error {
                // Local views are detached, but do NOT report an uncertain foreground rollback as success.
                NSLog("[SthenoRebuild] Scene close incomplete: %@", error.localizedDescription)
            }
            self.phase = .closed
            self.floatingWindow?.rootViewController = nil
            self.floatingWindow = nil
            self.onClosed?()
            self.onClosed = nil
        }
    }
    @objc private func closeTapped() { close() }

    @objc private func drag(_ gesture: UIPanGestureRecognizer) {
        guard phase == .attached, let window = floatingWindow else { return }
        if gesture.state == .began { panOrigin = window.frame.origin }
        let delta = gesture.translation(in: header)
        var requested = window.frame
        requested.origin = gesture.state == .cancelled ? panOrigin :
            CGPoint(x: panOrigin.x + delta.x, y: panOrigin.y + delta.y)
        var constrained = requested
        if SRMainConstrainWindow(requested, UIScreen.main.bounds, &constrained) { window.frame = constrained }
    }

    @objc private func resize(_ gesture: UIPinchGestureRecognizer) {
        guard phase == .attached, let window = floatingWindow else { return }
        if gesture.state == .began { pinchSize = window.bounds.size }
        let scale = gesture.state == .cancelled ? 1 : gesture.scale
        guard scale.isFinite, scale > 0 else { return }
        var requested = window.frame
        requested.size = CGSize(width: pinchSize.width * scale, height: pinchSize.height * scale)
        var frame = requested
        guard SRMainConstrainWindow(requested, UIScreen.main.bounds, &frame) else { return }
        queuedFrame = frame
        applyQueuedResize()
    }

    private func applyQueuedResize() {
        guard phase == .attached, !resizeInFlight, let requested = queuedFrame,
              let window = floatingWindow else { return }
        queuedFrame = nil
        resizeInFlight = true
        let previous = window.frame
        let generation = displayGeneration
        window.frame = requested
        view.layoutIfNeeded()
        SRMainResizeSceneAsync(sceneSession, appContainer.bounds) { [weak self, weak window] error in
            guard let self = self, self.phase == .attached,
                  self.displayGeneration == generation, let window = window,
                  window === self.floatingWindow else { return }
            self.resizeInFlight = false
            if let error = error {
                window.frame = previous
                self.view.layoutIfNeeded()
                NSLog("[SthenoRebuild] Display resize failed: %@", error.localizedDescription)
                self.close()
                return
            }
            self.applyQueuedResize() // coalesce rapid pinch changes, no out-of-order frame rollback
        }
    }
}
