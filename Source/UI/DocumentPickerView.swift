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
    
    public init(frame: CGRect, presentingViewController: UIViewController) {
        self.presentingViewController = presentingViewController
        super.init(frame: frame)
        setupUI()
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }
    
    private func setupUI() {
        backgroundColor = UIColor(red: 0.07, green: 0.09, blue: 0.12, alpha: 0.96)
        
        let container = UIStackView()
        container.axis = .vertical
        container.alignment = .center
        container.spacing = 16.0
        container.translatesAutoresizingMaskIntoConstraints = false
        addSubview(container)
        
        let iconView = UILabel()
        iconView.text = "🏰"
        iconView.font = UIFont.systemFont(ofSize: 64)
        
        let titleLabel = UILabel()
        titleLabel.text = "Age of Empires II (1999)"
        titleLabel.font = UIFont.systemFont(ofSize: 26, weight: .bold)
        titleLabel.textColor = UIColor(red: 0.95, green: 0.85, blue: 0.55, alpha: 1.0)
        
        let subtitleLabel = UILabel()
        subtitleLabel.text = "Game Data Required"
        subtitleLabel.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        subtitleLabel.textColor = .white
        
        let instructionsLabel = UILabel()
        instructionsLabel.numberOfLines = 0
        instructionsLabel.textAlignment = .center
        instructionsLabel.font = UIFont.systemFont(ofSize: 14, weight: .regular)
        instructionsLabel.textColor = UIColor(white: 0.8, alpha: 1.0)
        instructionsLabel.text = """
        To play on iOS/iPadOS, copy your original PC game folder:
        
        Option A (iTunes / Apple Finder):
        1. Connect your device to Mac or PC via USB.
        2. In Finder / iTunes File Sharing, drag your Age of Empires II folder into 'AoE2 iOS'.
        
        Option B (Files App):
        1. Tap 'Select Game Folder / ZIP' below.
        2. Pick your PC 'Age of Empires II' directory or a ZIP archive containing EMPIRES2.EXE.
        """
        
        let pickButton = UIButton(type: .system)
        pickButton.setTitle("📂 Select Game Folder / ZIP", for: .normal)
        if #available(iOS 15.0, *) {
            var config = UIButton.Configuration.filled()
            config.baseBackgroundColor = UIColor(red: 0.22, green: 0.45, blue: 0.85, alpha: 1.0)
            config.baseForegroundColor = .white
            config.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 24, bottom: 12, trailing: 24)
            config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var outgoing = incoming
                outgoing.font = UIFont.systemFont(ofSize: 16, weight: .bold)
                return outgoing
            }
            pickButton.configuration = config
        } else {
            pickButton.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .bold)
            pickButton.setTitleColor(.white, for: .normal)
            pickButton.backgroundColor = UIColor(red: 0.22, green: 0.45, blue: 0.85, alpha: 1.0)
            pickButton.contentEdgeInsets = UIEdgeInsets(top: 12, left: 24, bottom: 12, right: 24)
        }
        pickButton.layer.cornerRadius = 14.0
        pickButton.addTarget(self, action: #selector(didTapPickFolder), for: .touchUpInside)
        
        let refreshButton = UIButton(type: .system)
        refreshButton.setTitle("🔄 Refresh & Check Documents", for: .normal)
        refreshButton.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        refreshButton.setTitleColor(UIColor(red: 0.95, green: 0.85, blue: 0.55, alpha: 1.0), for: .normal)
        refreshButton.addTarget(self, action: #selector(didTapRefresh), for: .touchUpInside)
        
        container.addArrangedSubview(iconView)
        container.addArrangedSubview(titleLabel)
        container.addArrangedSubview(subtitleLabel)
        container.addArrangedSubview(instructionsLabel)
        container.addArrangedSubview(pickButton)
        container.addArrangedSubview(refreshButton)
        
        NSLayoutConstraint.activate([
            container.centerXAnchor.constraint(equalTo: centerXAnchor),
            container.centerYAnchor.constraint(equalTo: centerYAnchor),
            container.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            container.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24)
        ])
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
        let status = GameFileManager.shared.verifyGameInstallation()
        switch status {
        case .ready(let gameDir, _, _):
            delegate?.didCompleteImport(gameDirectory: gameDir)
            removeFromSuperview()
        case .missingFiles, .uninitialized:
            let alert = UIAlertController(title: "Files Not Found", message: "EMPIRES2.EXE not found in Documents. Please ensure the full game installation folder has been transferred.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            presentingViewController?.present(alert, animated: true)
        }
    }
    
    // MARK: - UIDocumentPickerDelegate
    
    public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let pickedURL = urls.first else { return }
        GameFileManager.shared.importFromURL(pickedURL) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let destURL):
                    self?.delegate?.didCompleteImport(gameDirectory: destURL)
                    self?.removeFromSuperview()
                case .failure(let err):
                    let alert = UIAlertController(title: "Import Error", message: err.localizedDescription, preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    self?.presentingViewController?.present(alert, animated: true)
                }
            }
        }
    }
}
