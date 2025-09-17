
import Foundation
import UIKit

@objc public enum InAppNotificationType: Int {
    case banner = 0
    case modal = 1
    case fullScreen = 2
    case custom = 3
}

@objc public class InAppNotificationContent: NSObject {
    @objc public var title: String = ""
    @objc public var message: String = ""
    @objc public var imageUrl: String?
    @objc public var buttonText: String?
    @objc public var buttonAction: String?
    @objc public var backgroundColor: UIColor = .systemBackground
    @objc public var textColor: UIColor = .label
    @objc public var campaignId: String?
    @objc public var customData: [String: Any] = [:]
    
    public override init() {
        super.init()
    }
}

class InAppNotificationManager: NSObject {
    
    private let eventTracker: ManualEventTracker
    private let ruleEngine: LocalRuleEngine
    private var currentNotification: InAppNotificationViewController?
    
    init(eventTracker: ManualEventTracker = ManualEventTracker(),
         ruleEngine: LocalRuleEngine = LocalRuleEngine()) {
        self.eventTracker = eventTracker
        self.ruleEngine = ruleEngine
        super.init()
    }
    
    // MARK: - Public Methods
    
    func presentInAppNotification(_ content: InAppNotificationContent, type: InAppNotificationType) {
        guard !isNotificationCurrentlyDisplayed() else {
            Logger.warning("In-app notification already displayed")
            return
        }
        
        DispatchQueue.main.async {
            self.showNotification(content, type: type)
        }
    }
    
    func presentInAppMessage(for trigger: String, context: [String: Any] = [:]) {
        // Evaluate rules to determine if notification should be shown
        ruleEngine.evaluateInAppMessageTrigger(trigger, context: context) { [weak self] shouldShow, content in
            if shouldShow, let content = content {
                self?.presentInAppNotification(content, type: .banner)
            }
        }
    }
    
    func dismissCurrentNotification() {
        DispatchQueue.main.async {
            self.currentNotification?.dismiss()
            self.currentNotification = nil
        }
    }
    
    // MARK: - Private Methods
    
    private func isNotificationCurrentlyDisplayed() -> Bool {
        return currentNotification != nil && currentNotification?.view.superview != nil
    }
    
    private func showNotification(_ content: InAppNotificationContent, type: InAppNotificationType) {
        guard let topViewController = getTopViewController() else {
            Logger.error("Could not find top view controller for in-app notification")
            return
        }
        
        let notificationVC = InAppNotificationViewController(content: content, type: type)
        notificationVC.delegate = self
        
        currentNotification = notificationVC
        
        switch type {
        case .banner:
            showBannerNotification(notificationVC, in: topViewController)
        case .modal:
            showModalNotification(notificationVC, in: topViewController)
        case .fullScreen:
            showFullScreenNotification(notificationVC, in: topViewController)
        case .custom:
            showCustomNotification(notificationVC, in: topViewController)
        }
        
        trackNotificationDisplayed(content)
    }
    
    private func showBannerNotification(_ notificationVC: InAppNotificationViewController, in parentVC: UIViewController) {
        parentVC.addChild(notificationVC)
        parentVC.view.addSubview(notificationVC.view)
        notificationVC.didMove(toParent: parentVC)
        
        // Setup constraints for banner at top
        notificationVC.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            notificationVC.view.topAnchor.constraint(equalTo: parentVC.view.safeAreaLayoutGuide.topAnchor),
            notificationVC.view.leadingAnchor.constraint(equalTo: parentVC.view.leadingAnchor),
            notificationVC.view.trailingAnchor.constraint(equalTo: parentVC.view.trailingAnchor),
            notificationVC.view.heightAnchor.constraint(equalToConstant: 100)
        ])
        
        // Animate in
        notificationVC.view.transform = CGAffineTransform(translationX: 0, y: -100)
        UIView.animate(withDuration: 0.3) {
            notificationVC.view.transform = .identity
        }
        
        // Auto dismiss after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            self.dismissCurrentNotification()
        }
    }
    
    private func showModalNotification(_ notificationVC: InAppNotificationViewController, in parentVC: UIViewController) {
        notificationVC.modalPresentationStyle = .pageSheet
        parentVC.present(notificationVC, animated: true)
    }
    
    private func showFullScreenNotification(_ notificationVC: InAppNotificationViewController, in parentVC: UIViewController) {
        notificationVC.modalPresentationStyle = .fullScreen
        parentVC.present(notificationVC, animated: true)
    }
    
    private func showCustomNotification(_ notificationVC: InAppNotificationViewController, in parentVC: UIViewController) {
        // Custom implementation based on specific requirements
        showModalNotification(notificationVC, in: parentVC)
    }
    
    private func getTopViewController() -> UIViewController? {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            return nil
        }
        
        var topController = window.rootViewController
        while let presentedController = topController?.presentedViewController {
            topController = presentedController
        }
        return topController
    }
    
    private func trackNotificationDisplayed(_ content: InAppNotificationContent) {
        let displayData: [String: Any] = [
            "campaign_id": content.campaignId ?? "",
            "notification_title": content.title,
            "notification_type": "in_app",
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "session_id": SessionManager.shared.getCurrentSessionId() ?? ""
        ]
        
        eventTracker.trackEvent(name: "in_app_notification_displayed", data: displayData)
    }
}

// MARK: - InAppNotificationDelegate

extension InAppNotificationManager: InAppNotificationDelegate {
    
    func inAppNotificationDidAppear(_ notification: InAppNotificationViewController) {
        let appearData: [String: Any] = [
            "campaign_id": notification.content.campaignId ?? "",
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        
        eventTracker.trackEvent(name: "in_app_notification_appeared", data: appearData)
    }
    
    func inAppNotificationDidDismiss(_ notification: InAppNotificationViewController) {
        let dismissData: [String: Any] = [
            "campaign_id": notification.content.campaignId ?? "",
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        
        eventTracker.trackEvent(name: "in_app_notification_dismissed", data: dismissData)
        currentNotification = nil
    }
    
    func inAppNotificationDidTapButton(_ notification: InAppNotificationViewController) {
        let tapData: [String: Any] = [
            "campaign_id": notification.content.campaignId ?? "",
            "button_action": notification.content.buttonAction ?? "",
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        
        eventTracker.trackEvent(name: "in_app_notification_button_tapped", data: tapData)
    }
}


protocol InAppNotificationDelegate: AnyObject {
    func inAppNotificationDidAppear(_ notification: InAppNotificationViewController)
    func inAppNotificationDidDismiss(_ notification: InAppNotificationViewController)
    func inAppNotificationDidTapButton(_ notification: InAppNotificationViewController)
}

class InAppNotificationViewController: UIViewController {
    
    weak var delegate: InAppNotificationDelegate?
    private(set) var content: InAppNotificationContent!
    private(set) var notificationType: InAppNotificationType!
    
    private let containerView = UIView()
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let imageView = UIImageView()
    private let actionButton = UIButton(type: .system)
    private let dismissButton = UIButton(type: .system)
    
    init(content: InAppNotificationContent, type: InAppNotificationType) {
        self.content = content
        self.notificationType = type
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        configureWithContent()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        delegate?.inAppNotificationDidAppear(self)
    }
    
    private func setupUI() {
        view.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        
        // Container View
        containerView.backgroundColor = content.backgroundColor
        containerView.layer.cornerRadius = 12
        containerView.layer.masksToBounds = true
        
        // Title Label
        titleLabel.font = UIFont.boldSystemFont(ofSize: 18)
        titleLabel.textColor = content.textColor
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        
        // Message Label
        messageLabel.font = UIFont.systemFont(ofSize: 16)
        messageLabel.textColor = content.textColor.withAlphaComponent(0.8)
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        
        // Image View
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        
        // Action Button
        actionButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 16)
        actionButton.backgroundColor = UIColor.systemBlue
        actionButton.setTitleColor(UIColor.white, for: .normal)
        actionButton.layer.cornerRadius = 8
        actionButton.addTarget(self, action: #selector(actionButtonTapped), for: .touchUpInside)
        
        // Dismiss Button
        dismissButton.setTitle("×", for: .normal)
        dismissButton.titleLabel?.font = UIFont.systemFont(ofSize: 24, weight: .light)
        dismissButton.setTitleColor(content.textColor.withAlphaComponent(0.6), for: .normal)
        dismissButton.addTarget(self, action: #selector(dismissButtonTapped), for: .touchUpInside)
        
        // Add subviews
        view.addSubview(containerView)
        [titleLabel, messageLabel, imageView, actionButton, dismissButton].forEach {
            containerView.addSubview($0)
            $0.translatesAutoresizingMaskIntoConstraints = false
        }
        
        containerView.translatesAutoresizingMaskIntoConstraints = false
        
        setupConstraints()
    }
    
    private func setupConstraints() {
        let containerConstraints: [NSLayoutConstraint]
        
        switch notificationType {
        case .banner:
            containerConstraints = [
                containerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
                containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
                containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
                containerView.heightAnchor.constraint(lessThanOrEqualToConstant: 120)
            ]
        case .modal:
            containerConstraints = [
                containerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                containerView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                containerView.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 40),
                containerView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -40),
                containerView.heightAnchor.constraint(lessThanOrEqualToConstant: 400)
            ]
        case .fullScreen:
            containerConstraints = [
                containerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                containerView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
            ]
        default:
            containerConstraints = [
                containerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                containerView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                containerView.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 20),
                containerView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20)
            ]
        }
        
        NSLayoutConstraint.activate(containerConstraints)
        
        NSLayoutConstraint.activate([
            // Dismiss Button
            dismissButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            dismissButton.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 16),
            dismissButton.widthAnchor.constraint(equalToConstant: 30),
            dismissButton.heightAnchor.constraint(equalToConstant: 30),
            
            // Title Label
            titleLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 24),
            titleLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: dismissButton.leadingAnchor, constant: -16),
            
            // Image View
            imageView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            imageView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            imageView.heightAnchor.constraint(equalToConstant: 80),
            imageView.widthAnchor.constraint(equalToConstant: 80),
            
            // Message Label
            messageLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 16),
            messageLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 24),
            messageLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -24),
            
            // Action Button
            actionButton.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 24),
            actionButton.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 24),
            actionButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -24),
            actionButton.heightAnchor.constraint(equalToConstant: 44),
            actionButton.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -24)
        ])
    }
    
    private func configureWithContent() {
        titleLabel.text = content.title
        messageLabel.text = content.message
        
        if let buttonText = content.buttonText, !buttonText.isEmpty {
            actionButton.setTitle(buttonText, for: .normal)
            actionButton.isHidden = false
        } else {
            actionButton.isHidden = true
        }
        
        if let imageUrlString = content.imageUrl, let imageUrl = URL(string: imageUrlString) {
            loadImage(from: imageUrl)
        } else {
            imageView.isHidden = true
        }
    }
    
    private func loadImage(from url: URL) {
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let data = data, let image = UIImage(data: data) else {
                DispatchQueue.main.async {
                    self?.imageView.isHidden = true
                }
                return
            }
            
            DispatchQueue.main.async {
                self?.imageView.image = image
                self?.imageView.isHidden = false
            }
        }.resume()
    }
    
    @objc private func actionButtonTapped() {
        delegate?.inAppNotificationDidTapButton(self)
        dismiss()
    }
    
    @objc private func dismissButtonTapped() {
        dismiss()
    }
    
    func dismiss() {
        delegate?.inAppNotificationDidDismiss(self)
        
        if presentingViewController != nil {
            dismiss(animated: true)
        } else {
            removeFromParent()
            view.removeFromSuperview()
        }
    }
}
