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

    func open(bundleIdentifier: String) throws {
        precondition(Thread.isMainThread)
        guard !bundleIdentifier.isEmpty else { throw SRFloatingError.invalidBundle }
        guard SRMainSceneHostingAvailable() else {
            throw SRFloatingError.unavailable(SRMainSceneHostingBlocker())
        }
        if let existing = controllers[bundleIdentifier] {
            existing.bringForward()
            return
        }
        let controller = SRFloatingController(bundleIdentifier: bundleIdentifier)
        try controller.attachAndPresent()
        controllers[bundleIdentifier] = controller
        controller.onClosed = { [weak self, weak controller] in
            guard let self = self, self.controllers[bundleIdentifier] === controller else { return }
            self.controllers.removeValue(forKey: bundleIdentifier)
        }
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
    private var panOrigin = CGPoint.zero
    private var pinchSize = CGSize.zero
    private var closed = false
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

    func attachAndPresent() throws {
        precondition(Thread.isMainThread)
        // Absolutely no empty window is shown as a successful launch.
        guard SRMainSceneHostingAvailable() else {
            throw SRFloatingError.unavailable(SRMainSceneHostingBlocker())
        }
        loadViewIfNeeded()
        let screen = UIScreen.main.bounds
        let width = min(320, screen.width * 0.85)
        let height = min(520, screen.height * 0.8)
        let frame = CGRect(x: screen.midX - width / 2, y: screen.midY - height / 2,
                           width: width, height: height)
        let window = UIWindow(frame: frame)
        window.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.normal.rawValue + 2)
        window.rootViewController = self
        view.frame = window.bounds
        view.layoutIfNeeded()
        var error: NSError?
        guard SRMainAttachScene(sceneSession, bundleIdentifier, appContainer, &error) else {
            _ = SRMainCloseScene(sceneSession, nil)
            window.rootViewController = nil
            if let error = error { throw error }
            throw SRFloatingError.unavailable("Scene attach failed without an error.")
        }
        floatingWindow = window
        window.isHidden = false
    }

    func bringForward() { floatingWindow?.isHidden = false }

    func close() {
        precondition(Thread.isMainThread)
        guard !closed else { return }
        // Remote cleanup first. On failure retain ownership and keep a usable close control.
        var error: NSError?
        guard SRMainCloseScene(sceneSession, &error) else {
            NSLog("[SthenoRebuild] Scene close failed: %@", error?.localizedDescription ?? "unknown")
            return
        }
        closed = true
        floatingWindow?.isHidden = true
        floatingWindow?.rootViewController = nil
        floatingWindow = nil
        onClosed?()
        onClosed = nil
    }
    @objc private func closeTapped() { close() }

    @objc private func drag(_ gesture: UIPanGestureRecognizer) {
        guard let window = floatingWindow else { return }
        if gesture.state == .began { panOrigin = window.frame.origin }
        let delta = gesture.translation(in: header)
        let screen = UIScreen.main.bounds
        var frame = window.frame
        frame.origin.x = min(max(screen.minX, panOrigin.x + delta.x), screen.maxX - frame.width)
        frame.origin.y = min(max(screen.minY, panOrigin.y + delta.y), screen.maxY - frame.height)
        window.frame = frame
    }

    @objc private func resize(_ gesture: UIPinchGestureRecognizer) {
        guard let window = floatingWindow else { return }
        if gesture.state == .began { pinchSize = window.bounds.size }
        let screen = UIScreen.main.bounds
        let scale = gesture.scale
        guard scale.isFinite, scale > 0 else { return }
        let width = min(max(160, pinchSize.width * scale), screen.width * 0.95)
        let height = min(max(200, pinchSize.height * scale), screen.height * 0.95)
        let bounds = CGRect(x: 0, y: 0, width: width, height: height - 36)
        var error: NSError?
        guard SRMainResizeScene(sceneSession, bounds, &error) else { return }
        var frame = window.frame
        frame.size = CGSize(width: width, height: height)
        frame.origin.x = min(max(screen.minX, frame.minX), screen.maxX - width)
        frame.origin.y = min(max(screen.minY, frame.minY), screen.maxY - height)
        window.frame = frame
        view.layoutIfNeeded()
    }
}
