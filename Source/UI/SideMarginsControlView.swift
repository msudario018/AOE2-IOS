import SwiftUI
import UIKit

/// SideMarginsAction
public enum SideMarginsAction {
    case townCenter        // 'H' (0x23)
    case idleVillager      // '.' (0x34)
    case cycleMilitary     // ',' (0x33)
    case focusSelection    // Space (0x39)
    case econBuildMenu     // 'B' (0x30)
    case milBuildMenu      // 'V' (0x2F)
    case repair            // 'R' (0x13)
    case garrison          // 'T' (0x14)
    case deleteSelected    // Delete (0xD3)
    case toggleLoupe       // Toggle 2.2x Command Bar Zoom Loupe
    case openLogs          // Open Diagnostics
}

public protocol SideMarginsDelegate: AnyObject {
    func didTriggerMarginAction(_ action: SideMarginsAction)
}

/// SideMarginsControlView
///
/// Native SwiftUI tactical flanks that leverage the unused pillarbox margins on wide 19.5:9 iPhone displays.
/// Automatically hides on 4:3 iPads where margins are negligible.
public struct SideMarginsControlView: View {
    public weak var delegate: SideMarginsDelegate?
    
    public var leftMarginWidth: CGFloat
    public var rightMarginWidth: CGFloat
    public var isLoupeActive: Bool
    
    private let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
    
    public init(delegate: SideMarginsDelegate?,
                leftMarginWidth: CGFloat,
                rightMarginWidth: CGFloat,
                isLoupeActive: Bool = true) {
        self.delegate = delegate
        self.leftMarginWidth = leftMarginWidth
        self.rightMarginWidth = rightMarginWidth
        self.isLoupeActive = isLoupeActive
    }
    
    public var body: some View {
        HStack(spacing: 0) {
            // LEFT FLANK: Map Cycling
            if leftMarginWidth >= 52 {
                VStack(spacing: 8) {
                    Text("CYCLE")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundColor(Color(red: 0.95, green: 0.85, blue: 0.55))
                        .tracking(1.5)
                        .padding(.top, 6)
                    
                    tacticalButton(title: "TC", subtitle: "H", icon: "building.columns.fill", action: .townCenter)
                    tacticalButton(title: "Idle Vil", subtitle: ".", icon: "person.crop.circle.badge.questionmark", action: .idleVillager)
                    tacticalButton(title: "Military", subtitle: ",", icon: "shield.lefthalf.filled", action: .cycleMilitary)
                    tacticalButton(title: "Focus", subtitle: "SPC", icon: "scope", action: .focusSelection)
                    
                    Spacer()
                }
                .frame(width: max(0, leftMarginWidth - 8))
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(red: 0.08, green: 0.10, blue: 0.14).opacity(0.85))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color(red: 0.95, green: 0.85, blue: 0.55).opacity(0.25), lineWidth: 1)
                        )
                )
                .padding(.leading, 4)
            }
            
            Spacer()
            
            // RIGHT FLANK: Command Toggles
            if rightMarginWidth >= 52 {
                VStack(spacing: 8) {
                    Text("COMMANDS")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundColor(Color(red: 0.95, green: 0.85, blue: 0.55))
                        .tracking(1.5)
                        .padding(.top, 6)
                    
                    tacticalButton(title: "Econ", subtitle: "B", icon: "hammer.fill", action: .econBuildMenu)
                    tacticalButton(title: "Mil Bld", subtitle: "V", icon: "shield.fill", action: .milBuildMenu)
                    tacticalButton(title: "Repair", subtitle: "R", icon: "wrench.and.screwdriver.fill", action: .repair)
                    tacticalButton(title: "Garrison", subtitle: "T", icon: "arrow.down.to.line.circle.fill", action: .garrison)
                    tacticalButton(title: "Delete", subtitle: "DEL", icon: "trash.fill", color: Color.red.opacity(0.85), action: .deleteSelected)
                    
                    Divider().background(Color.white.opacity(0.2)).padding(.horizontal, 8)
                    
                    // Loupe Toggle Button
                    Button(action: {
                        impactFeedback.impactOccurred()
                        delegate?.didTriggerMarginAction(.toggleLoupe)
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: isLoupeActive ? "magnifyingglass.circle.fill" : "magnifyingglass.circle")
                                .font(.system(size: 13, weight: .bold))
                            Text("Loupe")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(isLoupeActive ? Color(red: 0.95, green: 0.85, blue: 0.55) : Color.white.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(isLoupeActive ? Color.yellow.opacity(0.18) : Color.white.opacity(0.08))
                        .cornerRadius(8)
                        .padding(.horizontal, 6)
                    }
                    
                    Spacer()
                }
                .frame(width: max(0, rightMarginWidth - 8))
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(red: 0.08, green: 0.10, blue: 0.14).opacity(0.85))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color(red: 0.95, green: 0.85, blue: 0.55).opacity(0.25), lineWidth: 1)
                        )
                )
                .padding(.trailing, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(true)
    }
    
    private func tacticalButton(title: String,
                                subtitle: String,
                                icon: String,
                                color: Color = Color.white.opacity(0.92),
                                action: SideMarginsAction) -> some View {
        Button(action: {
            impactFeedback.impactOccurred()
            delegate?.didTriggerMarginAction(action)
        }) {
            VStack(spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .bold))
                    Text(title)
                        .font(.system(size: 11, weight: .bold))
                }
                Text("[\(subtitle)]")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundColor(Color.white.opacity(0.5))
            }
            .foregroundColor(color)
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background(Color.white.opacity(0.10))
            .cornerRadius(8)
            .padding(.horizontal, 6)
        }
    }
}
