import UIKit

public protocol VirtualControlsDelegate: AnyObject {
    func didTapTownCenterHotkey()
    func didTapIdleVillagerHotkey()
    func didTapEscapeKey()
    func didTapPauseKey()
    func didTapMenuKey()
    func didToggleControlMode(_ mode: TouchControlMode)
    func didToggleScalingFilter()
    func didRequestKeyboard()
    func didRequestLogViewer()
}

/// VirtualControlsOverlay
///
/// Sleek, semi-transparent HUD overlay providing rapid access to essential Age of Empires II hotkeys,
/// diagnostic logs, and touch mode toggles without obscuring the isometric battlefield.
public class VirtualControlsOverlay: UIView {
    
    public weak var delegate: VirtualControlsDelegate?
    
    private let stackView = UIStackView()
    private let modeToggleButton = UIButton(type: .system)
    private let filterButton = UIButton(type: .system)
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }
    
    private func setupUI() {
        backgroundColor = .clear
        
        stackView.axis = .horizontal
        stackView.distribution = .equalSpacing
        stackView.alignment = .center
        stackView.spacing = 8.0
        stackView.translatesAutoresizingMaskIntoConstraints = false
        
        // Background blur pill
        let blurEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
        let blurView = UIVisualEffectView(effect: blurEffect)
        blurView.layer.cornerRadius = 20.0
        blurView.clipsToBounds = true
        blurView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blurView)
        blurView.contentView.addSubview(stackView)
        
        // Buttons
        let tcButton = createHUDButton(title: "🏛️ TC", action: #selector(tcTapped))
        let idleButton = createHUDButton(title: "🚶 Idle", action: #selector(idleTapped))
        let escButton = createHUDButton(title: "ESC", action: #selector(escTapped))
        let pauseButton = createHUDButton(title: "⏸️ F3", action: #selector(pauseTapped))
        let kbdButton = createHUDButton(title: "⌨️", action: #selector(kbdTapped))
        let logButton = createHUDButton(title: "📜 Logs", action: #selector(logTapped))
        
        modeToggleButton.setTitle("🎯 Direct", for: .normal)
        formatHUDButton(modeToggleButton, action: #selector(modeToggled))
        
        filterButton.setTitle("📺 Crisp", for: .normal)
        formatHUDButton(filterButton, action: #selector(filterToggled))
        
        stackView.addArrangedSubview(tcButton)
        stackView.addArrangedSubview(idleButton)
        stackView.addArrangedSubview(escButton)
        stackView.addArrangedSubview(pauseButton)
        stackView.addArrangedSubview(kbdButton)
        stackView.addArrangedSubview(modeToggleButton)
        stackView.addArrangedSubview(filterButton)
        stackView.addArrangedSubview(logButton)
        
        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            
            stackView.topAnchor.constraint(equalTo: blurView.contentView.topAnchor, constant: 4),
            stackView.bottomAnchor.constraint(equalTo: blurView.contentView.bottomAnchor, constant: -4),
            stackView.leadingAnchor.constraint(equalTo: blurView.contentView.leadingAnchor, constant: 10),
            stackView.trailingAnchor.constraint(equalTo: blurView.contentView.trailingAnchor, constant: -10)
        ])
    }
    
    private func createHUDButton(title: String, action: Selector) -> UIButton {
        let btn = UIButton(type: .system)
        btn.setTitle(title, for: .normal)
        formatHUDButton(btn, action: action)
        return btn
    }
    
    private func formatHUDButton(_ btn: UIButton, action: Selector) {
        if #available(iOS 15.0, *) {
            var config = UIButton.Configuration.plain()
            config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10)
            config.baseForegroundColor = .white
            config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var outgoing = incoming
                outgoing.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
                return outgoing
            }
            btn.configuration = config
        } else {
            btn.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
            btn.setTitleColor(.white, for: .normal)
            btn.contentEdgeInsets = UIEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        }
        btn.backgroundColor = UIColor(white: 1.0, alpha: 0.12)
        btn.layer.cornerRadius = 14.0
        btn.addTarget(self, action: action, for: .touchUpInside)
    }
    
    // MARK: - Actions
    
    @objc private func tcTapped() {
        delegate?.didTapTownCenterHotkey()
    }
    
    @objc private func idleTapped() {
        delegate?.didTapIdleVillagerHotkey()
    }
    
    @objc private func escTapped() {
        delegate?.didTapEscapeKey()
    }
    
    @objc private func pauseTapped() {
        delegate?.didTapPauseKey()
    }
    
    @objc private func kbdTapped() {
        delegate?.didRequestKeyboard()
    }
    
    @objc private func logTapped() {
        delegate?.didRequestLogViewer()
    }
    
    @objc private func modeToggled() {
        if modeToggleButton.title(for: .normal)?.contains("Direct") == true {
            modeToggleButton.setTitle("🖱️ Trackpad", for: .normal)
            delegate?.didToggleControlMode(.trackpad)
        } else {
            modeToggleButton.setTitle("🎯 Direct", for: .normal)
            delegate?.didToggleControlMode(.direct)
        }
    }
    
    @objc private func filterToggled() {
        if filterButton.title(for: .normal)?.contains("Crisp") == true {
            filterButton.setTitle("🌊 Smooth", for: .normal)
        } else if filterButton.title(for: .normal)?.contains("Smooth") == true {
            filterButton.setTitle("📺 CRT", for: .normal)
        } else {
            filterButton.setTitle("📺 Crisp", for: .normal)
        }
        delegate?.didToggleScalingFilter()
    }
}
