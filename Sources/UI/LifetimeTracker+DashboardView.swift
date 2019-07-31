//
//  LifetimeTracker+DashboardView.swift
//  LifetimeTracker
//
//  Created by Krzysztof Zablocki on 9/25/17.
//

import UIKit

fileprivate extension String {
    #if swift(>=4.0)
    typealias AttributedStringKey = NSAttributedString.Key
    static let foregroundColorAttributeName = NSAttributedString.Key.foregroundColor
    #else
    typealias AttributedStringKey = String
    static let foregroundColorAttributeName = NSForegroundColorAttributeName
    #endif
    
    func attributed(_ attributes: [AttributedStringKey: Any] = [:]) -> NSAttributedString {
        return NSAttributedString(string: self, attributes: attributes)
    }
}

extension NSAttributedString {
    fileprivate static func + (left: NSAttributedString, right: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: left)
        result.append(right)
        return result
    }
}

public typealias EntryModel = (color: UIColor, description: String)
typealias GroupModel = (color: UIColor, title: String, groupName: String, groupCount: Int, groupMaxCount: Int, entries: [EntryModel])

@objc public final class LifetimeTrackerDashboardIntegration: NSObject {

    public enum Style {
        case bar
        case circular

        internal func makeViewable() -> UIViewController & LifetimeTrackerViewable {
            switch self {
            case .bar: return BarDashboardViewController.makeFromNib()
            case .circular: return CircularDashboardViewController.makeFromNib()
            }
        }
    }

    public enum Visibility {
        case alwaysHidden
        case alwaysVisible
        case visibleWithIssuesDetected

        func windowIsHidden(hasIssuesToDisplay: Bool) -> Bool {
            switch self {
            case .alwaysHidden: return true
            case .alwaysVisible: return false
            case .visibleWithIssuesDetected: return !hasIssuesToDisplay
            }
        }
    }

    private lazy var lifetimeTrackerView: UIViewController & LifetimeTrackerViewable = {
        return self.style.makeViewable()
    }()

    private lazy var window: UIWindow = {
        let window = UIWindow(frame: .zero)
        window.windowLevel = UIWindow.Level.statusBar
        window.frame =  UIScreen.main.bounds
        window.rootViewController = self.lifetimeTrackerView
        return window
    }()

    public var style: Style = .bar
    
    public var visibility: Visibility = .visibleWithIssuesDetected
    
    convenience public init(visibility: Visibility, style: Style = .bar) {
        self.init()
        self.visibility = visibility
        self.style = style
    }

    @objc public func refreshUI(trackedGroups: [String: LifetimeTracker.EntriesGroup]) {
        DispatchQueue.main.async {
            self.window.isHidden = self.visibility.windowIsHidden(hasIssuesToDisplay: self.hasIssuesToDisplay(from: trackedGroups))

            let entries = self.entries(from: trackedGroups)
            let vm = BarDashboardViewModel(leaksCount: entries.leaksCount, summary: self.summary(from: trackedGroups), sections: entries.groups)
            self.lifetimeTrackerView.update(with: vm)
        }
    }
    
    private func summary(from trackedGroups: [String: LifetimeTracker.EntriesGroup]) -> NSAttributedString {
        let groupNames = trackedGroups.keys.sorted(by: >)
        let leakyGroupSummaries = groupNames.filter { groupName in
            return trackedGroups[groupName]?.lifetimeState == .leaky
            }.map { groupName in
                let group = trackedGroups[groupName]!
                let maxCountString = group.maxCount == Int.max ? "∞" : "\(group.maxCount)"
                return "\(group.name ?? "Others") (\(group.count)/\(maxCountString))"
            }.joined(separator: ", ")
        
        if leakyGroupSummaries.isEmpty {
            return "No issues detected".attributed([
                String.foregroundColorAttributeName: UIColor.green
                ])
        }
        
        return ("Detected: ").attributed([
            String.foregroundColorAttributeName: UIColor.red
            ]) + leakyGroupSummaries.attributed()
    }
    
    private func entries(from trackedGroups: [String: LifetimeTracker.EntriesGroup]) -> (groups: [GroupModel], leaksCount: Int) {
        var leaksCount = 0
        var sections = [GroupModel]()
        let filteredGroups = trackedGroups.filter { (_, group: LifetimeTracker.EntriesGroup) -> Bool in
            group.count > 0
        }
        filteredGroups
            .sorted { (lhs: (key: String, value: LifetimeTracker.EntriesGroup), rhs: (key: String, value: LifetimeTracker.EntriesGroup)) -> Bool in
                return (lhs.value.maxCount - lhs.value.count) < (rhs.value.maxCount - rhs.value.count)
            }
            .forEach { (groupName: String, group: LifetimeTracker.EntriesGroup) in
                var groupColor: UIColor
                switch group.lifetimeState {
                case .valid: groupColor = .green
                case .leaky: groupColor = .red
                }
                let groupMaxCountString = group.maxCount == Int.max ? "∞" : "\(group.maxCount)"
                let title = "\(group.name ?? "Others") (\(group.count)/\(groupMaxCountString))"
                var rows: [EntryModel] = []
                leaksCount += group.leakCount(rows: &rows)
                sections.append((color: groupColor, title: title, groupName: "\(group.name ?? "Others")", groupCount: group.count, groupMaxCount: group.maxCount, entries: rows))
        }
        return (groups: sections, leaksCount: leaksCount)
    }
    
    public func hasIssuesToDisplay(from trackedGroups: [String: LifetimeTracker.EntriesGroup]) -> Bool {
        let aDetectedIssue = trackedGroups.keys.first { trackedGroups[$0]?.lifetimeState == .leaky }
        return aDetectedIssue != nil
    }
}

// MARK: - Objective-C Configuration Helper

extension LifetimeTrackerDashboardIntegration {

    @objc public func setVisibleWhenIssueDetected() {
        self.visibility = .visibleWithIssuesDetected
    }

    @objc public func setAlwaysVisible() {
        self.visibility = .alwaysVisible
    }

    @objc public func setAlwaysHidden() {
        self.visibility = .alwaysHidden
    }

    @objc public func useBarStyle() {
        self.style = .bar
    }

    @objc public func useCircularStyle() {
        self.style = .circular
    }
}

// MARK: - Deprecated Configuration Helper

extension LifetimeTrackerDashboardIntegration {

    @available(*, deprecated, message: "Use `LifetimeTrackerDashboardIntegration(visibility: Visibility, style: Style)` in Swift or `setVisibleWhenIssueDetected` instead")
    @objc public static func visibleWhenIssueDetected() -> LifetimeTrackerDashboardIntegration {
        return LifetimeTrackerDashboardIntegration(visibility: .visibleWithIssuesDetected)
    }

    @available(*, deprecated, message: "Use `LifetimeTrackerDashboardIntegration(visibility: Visibility, style: Style)` in Swift or `setAlwaysVisible` instead")
    @objc public static func alwaysVisible() -> LifetimeTrackerDashboardIntegration {
        return LifetimeTrackerDashboardIntegration(visibility: .alwaysVisible)
    }

    @available(*, deprecated, message: "Use `LifetimeTrackerDashboardIntegration(visibility: Visibility, style: Style)` in Swift or `setAlwaysHidden` instead")
    @objc public static func alwaysHidden() -> LifetimeTrackerDashboardIntegration {
        return LifetimeTrackerDashboardIntegration(visibility: .alwaysHidden)
    }
}
