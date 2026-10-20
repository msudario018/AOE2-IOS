import UIKit
import UniformTypeIdentifiers

public protocol DocumentPickerDelegate: AnyObject {
    func didCompleteImport(gameDirectory: URL)
}

/// DocumentPickerView
///
/// Displayed when `EMPIRES2.EXE` is not detected in the app's `Documents/` directory.
/// Explains iTunes / Apple Finder file sharing and presents a document picker to import files.
public class DocumentPickerView: UIView, UIDocumentPickerDelegate {
    
    public weak var delegate: DocumentPickerDelegate?
    private weak var presentingViewController: UIViewController?
    
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let mainStack = UIStackView()
    private let leftStack = UIStackView()
    private let rightStack = UIStackView()
    
    private let pickButton = UIButton(type: .system)
    private let refreshButton = UIButton(type: .system)
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private let statusLabel = UILabel()
    
    public init(frame: CGRect, presentingViewController: UIViewController) {
        self.presentingViewController = presentingViewController
        super.init(frame: frame)
        setupUI()
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        updateLayoutForSize(bounds.size)
    }
    
    private func updateLayoutForSize(_ size: CGSize) {
        // In landscape (width >= 580), use a side-by-side 2-column layout so buttons are immediately accessible
        if size.width >= 580 {
            mainStack.axis = .horizontal
            mainStack.alignment = .top
            mainStack.distribution = .fillEqually
            mainStack.spacing = 24.0
        } else {
            mainStack.axis = .vertical
            mainStack.alignment = .fill
            mainStack.distribution = .fill
            mainStack.spacing = 18.0
        }
    }
    
    private func setupUI() {
        backgroundColor = UIColor(red: 0.05, green: 0.07, blue: 0.10, alpha: 0.98)
        
        // 1. Root ScrollView to guarantee no element is ever cut off on any screen size
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = true
        scrollView.indicatorStyle = .white
        addSubview(scrollView)
        
        contentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentView)
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor),
            
            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])
        
        let minHeightConstraint = contentView.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.frameLayoutGuide.heightAnchor)
        minHeightConstraint.priority = .defaultLow
        minHeightConstraint.isActive = true
        
        // 2. Main Stack
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(mainStack)
        
        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            mainStack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -20),
            mainStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            mainStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20)
        ])
        
        // 3. Build Left Panel (Hero, Title, Badges & Interactive Buttons)
        leftStack.axis = .vertical
        leftStack.alignment = .fill
        leftStack.spacing = 12.0
        
        let headerRow = UIStackView()
        headerRow.axis = .horizontal
        headerRow.spacing = 12.0
        headerRow.alignment = .center
        
        let iconLabel = UILabel()
        iconLabel.text = "🏰"
        iconLabel.font = UIFont.systemFont(ofSize: 42)
        
        let titlesStack = UIStackView()
        titlesStack.axis = .vertical
        titlesStack.spacing = 4.0
        
        let titleLabel = UILabel()
        titleLabel.text = "Age of Empires II"
        titleLabel.font = UIFont.systemFont(ofSize: 22, weight: .black)
        titleLabel.textColor = UIColor(red: 0.95, green: 0.85, blue: 0.55, alpha: 1.0)
        
        let subtitleBadgeContainer = UIView()
        subtitleBadgeContainer.backgroundColor = UIColor(red: 0.75, green: 0.22, blue: 0.17, alpha: 0.35)
        subtitleBadgeContainer.layer.borderColor = UIColor(red: 0.85, green: 0.30, blue: 0.25, alpha: 0.8).cgColor
        subtitleBadgeContainer.layer.borderWidth = 1.0
        subtitleBadgeContainer.layer.cornerRadius = 6.0
        subtitleBadgeContainer.translatesAutoresizingMaskIntoConstraints = false
        
        let subtitleLabel = UILabel()
        subtitleLabel.text = "  ⚠️ Game Data Required  "
        subtitleLabel.font = UIFont.systemFont(ofSize: 12, weight: .bold)
        subtitleLabel.textColor = UIColor(red: 1.0, green: 0.65, blue: 0.60, alpha: 1.0)
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleBadgeContainer.addSubview(subtitleLabel)
        
        NSLayoutConstraint.activate([
            subtitleLabel.topAnchor.constraint(equalTo: subtitleBadgeContainer.topAnchor, constant: 3),
            subtitleLabel.bottomAnchor.constraint(equalTo: subtitleBadgeContainer.bottomAnchor, constant: -3),
            subtitleLabel.leadingAnchor.constraint(equalTo: subtitleBadgeContainer.leadingAnchor, constant: 4),
            subtitleLabel.trailingAnchor.constraint(equalTo: subtitleBadgeContainer.trailingAnchor, constant: -4)
        ])
        
        titlesStack.addArrangedSubview(titleLabel)
        let badgeRow = UIStackView(arrangedSubviews: [subtitleBadgeContainer, UIView()])
        badgeRow.axis = .horizontal
        titlesStack.addArrangedSubview(badgeRow)
        
        headerRow.addArrangedSubview(iconLabel)
        headerRow.addArrangedSubview(titlesStack)
        leftStack.addArrangedSubview(headerRow)
        
        let promptLabel = UILabel()
        promptLabel.text = "To start playing, import your PC game files or copy them to this device's Documents folder."
        promptLabel.numberOfLines = 0
        promptLabel.font = UIFont.systemFont(ofSize: 13, weight: .regular)
        promptLabel.textColor = UIColor(white: 0.78, alpha: 1.0)
        leftStack.addArrangedSubview(promptLabel)
        
        // Pick Game Folder Button
        pickButton.setTitle("📂 Select Game Folder / ZIP", for: .normal)
        pickButton.translatesAutoresizingMaskIntoConstraints = false
        pickButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
        if #available(iOS 15.0, *) {
            var config = UIButton.Configuration.filled()
            config.baseBackgroundColor = UIColor(red: 0.18, green: 0.44, blue: 0.82, alpha: 1.0)
            config.baseForegroundColor = .white
            config.cornerStyle = .medium
            config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16)
            config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var outgoing = incoming
                outgoing.font = UIFont.systemFont(ofSize: 15, weight: .bold)
                return outgoing
            }
            pickButton.configuration = config
        } else {
            pickButton.titleLabel?.font = UIFont.systemFont(ofSize: 15, weight: .bold)
            pickButton.setTitleColor(.white, for: .normal)
            pickButton.backgroundColor = UIColor(red: 0.18, green: 0.44, blue: 0.82, alpha: 1.0)
            pickButton.layer.cornerRadius = 10.0
            pickButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)
        }
        pickButton.layer.cornerRadius = 10.0
        pickButton.layer.shadowColor = UIColor.black.cgColor
        pickButton.layer.shadowOpacity = 0.4
        pickButton.layer.shadowOffset = CGSize(width: 0, height: 2)
        pickButton.layer.shadowRadius = 4
        pickButton.addTarget(self, action: #selector(didTapPickFolder), for: .touchUpInside)
        leftStack.addArrangedSubview(pickButton)
        
        // Refresh Button
        refreshButton.setTitle("🔄 Refresh & Check Documents", for: .normal)
        refreshButton.translatesAutoresizingMaskIntoConstraints = false
        refreshButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        if #available(iOS 15.0, *) {
            var config = UIButton.Configuration.tinted()
            config.baseBackgroundColor = UIColor(red: 0.95, green: 0.85, blue: 0.55, alpha: 0.15)
            config.baseForegroundColor = UIColor(red: 0.95, green: 0.85, blue: 0.55, alpha: 1.0)
            config.cornerStyle = .medium
            config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
            config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var outgoing = incoming
                outgoing.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
                return outgoing
            }
            refreshButton.configuration = config
        } else {
            refreshButton.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
            refreshButton.setTitleColor(UIColor(red: 0.95, green: 0.85, blue: 0.55, alpha: 1.0), for: .normal)
            refreshButton.backgroundColor = UIColor(white: 0.15, alpha: 0.6)
            refreshButton.layer.cornerRadius = 10.0
            refreshButton.layer.borderColor = UIColor(red: 0.95, green: 0.85, blue: 0.55, alpha: 0.4).cgColor
            refreshButton.layer.borderWidth = 1.0
            refreshButton.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        }
        refreshButton.layer.cornerRadius = 10.0
        refreshButton.addTarget(self, action: #selector(didTapRefresh), for: .touchUpInside)
        leftStack.addArrangedSubview(refreshButton)
        
        // Status Row (Activity spinner & progress label)
        let statusRow = UIStackView()
        statusRow.axis = .horizontal
        statusRow.spacing = 8.0
        statusRow.alignment = .center
        activityIndicator.hidesWhenStopped = true
        activityIndicator.color = UIColor(red: 0.95, green: 0.85, blue: 0.55, alpha: 1.0)
        statusLabel.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        statusLabel.textColor = UIColor(white: 0.7, alpha: 1.0)
        statusLabel.numberOfLines = 0
        statusRow.addArrangedSubview(activityIndicator)
        statusRow.addArrangedSubview(statusLabel)
        leftStack.addArrangedSubview(statusRow)
        
        // 4. Build Right Panel (Detailed Guide & Instruction Cards)
        rightStack.axis = .vertical
        rightStack.spacing = 10.0
        rightStack.alignment = .fill
        
        let card1 = createInfoCard(
            badge: "OPTION 1",
            title: "Direct Files App Import (Recommended)",
            body: "Tap 'Select Game Folder / ZIP' on the left. Pick your Age of Empires II folder or ZIP archive from Files or iCloud Drive. Files are copied automatically."
        )
        
        let card2 = createInfoCard(
            badge: "OPTION 2",
            title: "PC / Mac USB File Sharing",
            body: "Connect your iPhone/iPad to PC or Mac via USB. Open iTunes or Finder > File Sharing > AoE2 iOS, and drag your game folder directly into Documents. Then tap Refresh."
        )
        
        let card3 = createInfoCard(
            badge: "COMPATIBILITY",
            title: "Supported PC Versions",
            body: "Age of Empires II (1999), The Conquerors (2000), UserPatch 1.5, or HD Edition (2013) with EMPIRES2.EXE or AoK HD.exe."
        )
        
        rightStack.addArrangedSubview(card1)
        rightStack.addArrangedSubview(card2)
        rightStack.addArrangedSubview(card3)
        
        mainStack.addArrangedSubview(leftStack)
        mainStack.addArrangedSubview(rightStack)
        
        updateLayoutForSize(bounds.size)
    }
    
    private func createInfoCard(badge: String, title: String, body: String) -> UIView {
        let card = UIView()
        card.backgroundColor = UIColor(white: 0.12, alpha: 0.7)
        card.layer.cornerRadius = 10.0
        card.layer.borderColor = UIColor(white: 0.25, alpha: 0.6).cgColor
        card.layer.borderWidth = 1.0
        
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 4.0
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        
        let headerRow = UIStackView()
        headerRow.axis = .horizontal
        headerRow.spacing = 6.0
        headerRow.alignment = .center
        
        let badgeLabel = UILabel()
        badgeLabel.text = " \(badge) "
        badgeLabel.font = UIFont.systemFont(ofSize: 10, weight: .black)
        badgeLabel.textColor = UIColor(red: 0.95, green: 0.85, blue: 0.55, alpha: 1.0)
        badgeLabel.backgroundColor = UIColor(red: 0.95, green: 0.85, blue: 0.55, alpha: 0.15)
        badgeLabel.layer.cornerRadius = 4.0
        badgeLabel.layer.masksToBounds = true
        
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = UIFont.systemFont(ofSize: 12, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 1
        
        headerRow.addArrangedSubview(badgeLabel)
        headerRow.addArrangedSubview(titleLabel)
        headerRow.addArrangedSubview(UIView())
        
        let bodyLabel = UILabel()
        bodyLabel.text = body
        bodyLabel.font = UIFont.systemFont(ofSize: 11, weight: .regular)
        bodyLabel.textColor = UIColor(white: 0.75, alpha: 1.0)
        bodyLabel.numberOfLines = 0
        
        stack.addArrangedSubview(headerRow)
        stack.addArrangedSubview(bodyLabel)
        
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -8),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -10)
        ])
        
        return card
    }
    
    @objc private func didTapPickFolder() {
        let picker: UIDocumentPickerViewController
        if #available(iOS 14.0, *) {
            picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder, .zip, .archive], asCopy: true)
        } else {
            picker = UIDocumentPickerViewController(documentTypes: ["public.folder", "public.zip-archive"], in: .import)
        }
        picker.delegate = self
        picker.allowsMultipleSelection = false
        presentingViewController?.present(picker, animated: true)
    }
    
    @objc private func didTapRefresh() {
        activityIndicator.startAnimating()
        statusLabel.text = "Checking game files..."
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self else { return }
            self.activityIndicator.stopAnimating()
            
            let status = GameFileManager.shared.verifyGameInstallation()
            switch status {
            case .ready(let gameDir, _, _):
                self.statusLabel.text = "Game data verified! Booting..."
                self.delegate?.didCompleteImport(gameDirectory: gameDir)
                self.removeFromSuperview()
            case .missingFiles, .uninitialized:
                self.statusLabel.text = "EMPIRES2.EXE / AoK HD.exe not found."
                let alert = UIAlertController(
                    title: "Files Not Found",
                    message: "EMPIRES2.EXE or AoK HD.exe was not detected in the app Documents folder.\n\nPlease ensure your game directory contains the executable and data files.",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                self.presentingViewController?.present(alert, animated: true)
            }
        }
    }
    
    // MARK: - UIDocumentPickerDelegate
    
    public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let pickedURL = urls.first else { return }
        
        activityIndicator.startAnimating()
        pickButton.isEnabled = false
        refreshButton.isEnabled = false
        statusLabel.text = "Importing \(pickedURL.lastPathComponent)... Please wait."
        
        GameFileManager.shared.importFromURL(pickedURL) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.activityIndicator.stopAnimating()
                self.pickButton.isEnabled = true
                self.refreshButton.isEnabled = true
                
                switch result {
                case .success(let destURL):
                    self.statusLabel.text = "Import successful! Verifying..."
                    self.delegate?.didCompleteImport(gameDirectory: destURL)
                    self.removeFromSuperview()
                case .failure(let err):
                    self.statusLabel.text = "Import failed: \(err.localizedDescription)"
                    let alert = UIAlertController(title: "Import Error", message: err.localizedDescription, preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    self.presentingViewController?.present(alert, animated: true)
                }
            }
        }
    }
}
