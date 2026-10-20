import UIKit

public class LogViewerViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    
    private let segmentedControl = UISegmentedControl(items: ["All Logs", "⚠️ Errors", "💀 Crash Reports"])
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let textView = UITextView() // For viewing full crash reports
    
    private var filteredEntries: [LogEntry] = []
    private var crashFiles: [String] = []
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadData()
        
        // Subscribe to live log stream
        Logger.shared.onNewEntry = { [weak self] _ in
            guard let self = self, self.segmentedControl.selectedSegmentIndex != 2 else { return }
            self.refreshEntries()
        }
    }
    
    private func setupUI() {
        title = "Diagnostic Logs & Crash Reports"
        view.backgroundColor = UIColor(red: 0.08, green: 0.10, blue: 0.14, alpha: 0.98)
        
        // Navigation Bar Buttons
        let closeBtn = UIBarButtonItem(title: "Done", style: .done, target: self, action: #selector(closeTapped))
        closeBtn.tintColor = UIColor(red: 0.95, green: 0.85, blue: 0.55, alpha: 1.0)
        navigationItem.leftBarButtonItem = closeBtn
        
        let shareBtn = UIBarButtonItem(barButtonSystemItem: .action, target: self, action: #selector(shareTapped))
        shareBtn.tintColor = .white
        let clearBtn = UIBarButtonItem(barButtonSystemItem: .trash, target: self, action: #selector(clearTapped))
        clearBtn.tintColor = .systemRed
        navigationItem.rightBarButtonItems = [shareBtn, clearBtn]
        
        // Segmented Control
        segmentedControl.selectedSegmentIndex = 0
        segmentedControl.addTarget(self, action: #selector(segmentChanged), for: .valueChanged)
        segmentedControl.backgroundColor = UIColor(white: 1.0, alpha: 0.1)
        segmentedControl.selectedSegmentTintColor = UIColor(white: 1.0, alpha: 0.25)
        segmentedControl.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .normal)
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(segmentedControl)
        
        // Table View for Log Entries & Crash List
        tableView.backgroundColor = .clear
        tableView.separatorColor = UIColor(white: 1.0, alpha: 0.1)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "LogCell")
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        
        // Text View for Crash Log Details
        textView.backgroundColor = UIColor(red: 0.05, green: 0.06, blue: 0.08, alpha: 1.0)
        textView.textColor = UIColor(red: 0.9, green: 0.9, blue: 0.95, alpha: 1.0)
        textView.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.isEditable = false
        textView.isHidden = true
        textView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(textView)
        
        NSLayoutConstraint.activate([
            segmentedControl.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            segmentedControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            segmentedControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            segmentedControl.heightAnchor.constraint(equalToConstant: 32),
            
            tableView.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            textView.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 8),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    private func loadData() {
        refreshEntries()
        crashFiles = CrashReporter.availableCrashReports()
    }
    
    private func refreshEntries() {
        let all = Logger.shared.entries
        if segmentedControl.selectedSegmentIndex == 1 {
            filteredEntries = all.filter { $0.level == .error || $0.level == .fatal }
        } else {
            filteredEntries = all
        }
        tableView.reloadData()
        
        if filteredEntries.count > 0 {
            let lastIdx = IndexPath(row: filteredEntries.count - 1, section: 0)
            tableView.scrollToRow(at: lastIdx, at: .bottom, animated: false)
        }
    }
    
    // MARK: - Actions
    
    @objc private func segmentChanged() {
        if segmentedControl.selectedSegmentIndex == 2 {
            // Crash Reports
            textView.isHidden = true
            tableView.isHidden = false
            crashFiles = CrashReporter.availableCrashReports()
            tableView.reloadData()
        } else {
            textView.isHidden = true
            tableView.isHidden = false
            refreshEntries()
        }
    }
    
    @objc private func closeTapped() {
        dismiss(animated: true)
    }
    
    @objc private func shareTapped() {
        var itemsToShare: [Any] = []
        
        if segmentedControl.selectedSegmentIndex == 2 {
            if let latest = CrashReporter.availableCrashReports().first {
                itemsToShare.append(URL(fileURLWithPath: latest))
            }
        } else {
            if let logURL = Logger.shared.runtimeLogURL {
                itemsToShare.append(logURL)
            } else {
                itemsToShare.append(Logger.shared.readFullRuntimeLog())
            }
        }
        
        guard !itemsToShare.isEmpty else {
            let alert = UIAlertController(title: "No Logs", message: "No log files available to export.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }
        
        let activity = UIActivityViewController(activityItems: itemsToShare, applicationActivities: nil)
        activity.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItems?.first
        present(activity, animated: true)
    }
    
    @objc private func clearTapped() {
        let alert = UIAlertController(title: "Clear Logs", message: "Are you sure you want to delete all diagnostic logs and crash reports?", preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Delete All", style: .destructive) { [weak self] _ in
            Logger.shared.clearRuntimeLog()
            CrashReporter.clearCrashReports()
            self?.loadData()
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItems?.last
        present(alert, animated: true)
    }
    
    // MARK: - UITableViewDataSource & Delegate
    
    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if segmentedControl.selectedSegmentIndex == 2 {
            return crashFiles.isEmpty ? 1 : crashFiles.count
        }
        return filteredEntries.count
    }
    
    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "LogCell", for: indexPath)
        cell.backgroundColor = .clear
        cell.textLabel?.numberOfLines = 0
        cell.textLabel?.font = UIFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        
        if segmentedControl.selectedSegmentIndex == 2 {
            if crashFiles.isEmpty {
                cell.textLabel?.textColor = .systemGreen
                cell.textLabel?.text = "✅ No crash reports recorded! System is clean."
            } else {
                let filename = (crashFiles[indexPath.row] as NSString).lastPathComponent
                cell.textLabel?.textColor = .systemRed
                cell.textLabel?.text = "💀 \(filename) (Tap to view details)"
            }
            return cell
        }
        
        let entry = filteredEntries[indexPath.row]
        cell.textLabel?.text = "\(entry.level.emoji) \(entry.formattedText)"
        
        switch entry.level {
        case .debug:
            cell.textLabel?.textColor = UIColor(white: 0.6, alpha: 1.0)
        case .info:
            cell.textLabel?.textColor = UIColor(white: 0.9, alpha: 1.0)
        case .warn:
            cell.textLabel?.textColor = UIColor.systemYellow
        case .error:
            cell.textLabel?.textColor = UIColor(red: 1.0, green: 0.35, blue: 0.35, alpha: 1.0)
        case .fatal:
            cell.textLabel?.textColor = UIColor(red: 1.0, green: 0.2, blue: 0.2, alpha: 1.0)
        }
        
        return cell
    }
    
    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        if segmentedControl.selectedSegmentIndex == 2 && !crashFiles.isEmpty {
            let crashPath = crashFiles[indexPath.row]
            if let content = try? String(contentsOfFile: crashPath, encoding: .utf8) {
                textView.text = content
                textView.isHidden = false
                tableView.isHidden = true
                
                let backBtn = UIBarButtonItem(title: "Back to List", style: .plain, target: self, action: #selector(backToListTapped))
                navigationItem.leftBarButtonItem = backBtn
            }
        }
    }
    
    @objc private func backToListTapped() {
        textView.isHidden = true
        tableView.isHidden = false
        let closeBtn = UIBarButtonItem(title: "Done", style: .done, target: self, action: #selector(closeTapped))
        closeBtn.tintColor = UIColor(red: 0.95, green: 0.85, blue: 0.55, alpha: 1.0)
        navigationItem.leftBarButtonItem = closeBtn
    }
}
