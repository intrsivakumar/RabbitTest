
import Foundation
import UserNotifications
import UserNotificationsUI

@available(iOSApplicationExtension 10.0, *)
class NotificationContentExtension: UIViewController, UNNotificationContentExtension {
    
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var bodyLabel: UILabel!
    @IBOutlet weak var mediaImageView: UIImageView!
    @IBOutlet weak var actionButton: UIButton!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }
    
    func didReceive(_ notification: UNNotification) {
        let content = notification.request.content
        
        titleLabel.text = content.title
        bodyLabel.text = content.body
        
        // Handle media attachments
        if let attachment = content.attachments.first {
            loadMediaAttachment(attachment)
        }
        
        // Customize based on user info
        if let customData = content.userInfo["custom_data"] as? [String: Any] {
            customizeContent(with: customData)
        }
    }
    
    func didReceive(_ response: UNNotificationResponse,
                   completionHandler completion: @escaping (UNNotificationContentExtensionResponseOption) -> Void) {
        
        if response.actionIdentifier == "view_details" {
            // Handle custom action
            handleViewDetailsAction(response)
            completion(.dismiss)
        } else {
            completion(.doNotDismiss)
        }
    }
    
    // MARK: - Private Methods
    
    private func setupUI() {
        view.backgroundColor = UIColor.systemBackground
        
        titleLabel.font = UIFont.boldSystemFont(ofSize: 18)
        titleLabel.textColor = UIColor.label
        
        bodyLabel.font = UIFont.systemFont(ofSize: 16)
        bodyLabel.textColor = UIColor.secondaryLabel
        bodyLabel.numberOfLines = 0
        
        actionButton.backgroundColor = UIColor.systemBlue
        actionButton.setTitleColor(UIColor.white, for: .normal)
        actionButton.layer.cornerRadius = 8
    }
    
    private func loadMediaAttachment(_ attachment: UNNotificationAttachment) {
        guard attachment.url.startAccessingSecurityScopedResource() else {
            return
        }
        
        defer {
            attachment.url.stopAccessingSecurityScopedResource()
        }
        
        if attachment.type.hasPrefix("image") {
            loadImage(from: attachment.url)
        } else if attachment.type.hasPrefix("video") {
            loadVideoThumbnail(from: attachment.url)
        }
    }
    
    private func loadImage(from url: URL) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let data = try? Data(contentsOf: url),
                  let image = UIImage(data: data) else {
                return
            }
            
            DispatchQueue.main.async {
                self.mediaImageView.image = image
                self.mediaImageView.isHidden = false
            }
        }
    }
    
    private func loadVideoThumbnail(from url: URL) {
        // Implementation for video thumbnail extraction
        // This would use AVAssetImageGenerator to create thumbnail
    }
    
    private func customizeContent(with customData: [String: Any]) {
        if let buttonTitle = customData["button_title"] as? String {
            actionButton.setTitle(buttonTitle, for: .normal)
            actionButton.isHidden = false
        }
        
        if let backgroundColor = customData["background_color"] as? String {
            view.backgroundColor = UIColor(hexString: backgroundColor)
        }
    }
    
    private func handleViewDetailsAction(_ response: UNNotificationResponse) {
        // Track the action
        let actionData: [String: Any] = [
            "action": "view_details",
            "campaign_id": response.notification.request.content.userInfo["campaign_id"] as? String ?? "",
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        
        // This would typically be sent to analytics via shared container or other mechanism
        NotificationCenter.default.post(name: .notificationActionTracked, object: actionData)
    }
}

// MARK: - Extensions

extension Notification.Name {
    static let notificationActionTracked = Notification.Name("notificationActionTracked")
}

extension UIColor {
    convenience init?(hexString: String) {
        var hexSanitized = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.hasPrefix("#") ? String(hexSanitized.dropFirst()) : hexSanitized
        
        guard hexSanitized.count == 6 else { return nil }
        
        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)
        
        let r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
        let b = CGFloat(rgb & 0x0000FF) / 255.0
        
        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
}
