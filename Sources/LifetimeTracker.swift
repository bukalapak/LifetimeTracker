//
//  LifetimeTracker.swift
//  LifetimeTracker
//
//  Created by Krzysztof Zablocki on 9/25/17.
//  Copyright © 2017 LifetimeTracker. All rights reserved.
//

import Foundation
import UIKit

/// Holds the properties which are needed to configure a `LifetimeTrackable`
@objc public final class LifetimeConfiguration: NSObject {
    
    /// Maximum count of valid instances
    ///
    /// LifetimeTracker will show a warning if more instance of the class are alive.
    @objc public var maxCount: Int
    
    /// Name which defines that the instance should be tracked as part of the chosen group.
    ///
    /// A group will automatically be created if there is none with a matching name.
    ///
    /// The usage is optional. The instances will be tracked as standalone items based on their class names if no group is chosen.
    @objc public var groupName: String? = nil
    
    /// Maximum count of valid entries in the whole group.
    ///
    /// LifetimeTracker will through a warning if `groupMaxCount` is too high although all members didn't reach their own `maxCount`
    /// Set a value here if you want the group's `maxCount` to be different than the sum of the `maxCount` of all members.
    ///
    /// The usage is optional. No value or `nil` defines that `groupMaxCount` is the sum of all `maxCount` values of the members of the group.
    /// - Note: The usage of `groupMaxCount` requires that a group is defined by setting `groupName`.
    public var groupMaxCount: Int? = nil
    
    public var instanceName: String = ""
    public var pointerString: String = ""
    
    /// Defines objects which are tracked based on their class names.
    ///
    /// LifetimeTracker will show a warning if more instances of the class are alive.
    ///
    /// Use `LifetimeConfiguration(maxCount:groupName:)` or `LifetimeConfiguration(maxCount:groupName:groupMaxCount:)` if you want to add the class to an existing or new group.
    ///
    /// - Parameters:
    ///   - maxCount: Maximum count of valid instances
    @objc public init(maxCount: Int) {
        self.maxCount = maxCount
    }
    
    /// Defines objects which are tracked based in their class names and as part of a group.
    ///
    /// LifetimeTracker will show a warning if more instances of the class or group are alive.
    ///
    /// Use `LifetimeConfiguration(maxCount:)` if you want to track the class without a group membership.
    ///
    /// Use `LifetimeConfiguration(maxCount:groupName:groupMaxCount:)` if you want the group's `maxCount` to be different than the sum of the `maxCount` of all members.
    ///
    /// - Parameters:
    ///   - maxCount: Maximum count of valid instances
    ///   - groupName: Name which defines that the instance should be tracked as part of the chosen group. A group will automatically be created if there is none with a matching name.
    @objc public init(maxCount: Int, groupName: String) {
        self.maxCount = maxCount
        self.groupName = groupName
    }
    
    /// Defines objects which are tracked based in their class names and as part of a group with a custom `groupMaxCount`.
    ///
    /// LifetimeTracker will show a warning if more instances of the class or group are alive.
    ///
    /// Use `LifetimeConfiguration(maxCount:)` if you want to track the class without a group membership.
    ///
    /// Use `LifetimeConfiguration(maxCount:groupName:)` if you want the group's `maxCount` to be the sum of the `maxCount` of all members.
    ///
    /// - Parameters:
    ///   - maxCount: Maximum count of valid instances. LifetimeTracker will show a warning if more instances of the class are alive
    ///   - groupName: Name which defines that the instance should be tracked as part of the chosen group. A group will automatically be created if there is none with a matching name.
    ///   - groupMaxCount: Maximum count of valid entries in the whole group. LifetimeTracker will through a warning if `groupMaxCount` is too high although all members didn't reach their own `maxCount`
    @objc public init(maxCount: Int, groupName: String, groupMaxCount: Int) {
        self.maxCount = maxCount
        self.groupName = groupName
        self.groupMaxCount = groupMaxCount
    }
    
    internal static func makeCompleteConfiguration(with instance: LifetimeTrackable) -> LifetimeConfiguration {
        let instanceType = type(of: instance)
        let configuration = instanceType.lifetimeConfiguration
        configuration.instanceName = String(describing: instanceType)
        configuration.pointerString = "\(Unmanaged<AnyObject>.passUnretained(instance as AnyObject).toOpaque())"
        return configuration
    }
}


/// Defines a type that can have its lifetime tracked
@objc public protocol LifetimeTrackable: class {
    
    /// Configuration for lifetime tracking, contains identifier and leak classifier
    static var lifetimeConfiguration: LifetimeConfiguration { get }
}

public extension LifetimeTrackable {
    /// Starts tracking lifetime, should be called in each initializer
    func trackLifetime() {
        LifetimeTracker.instance?.track(self, configuration: type(of: self).lifetimeConfiguration)
    }
}

@objc public extension NSObject {
    /// Starts tracking lifetime, should be called in each initializer
    @objc func trackLifetime() {
        if let object = self as? LifetimeTrackable {
            LifetimeTracker.instance?.track(self, configuration: type(of: object).lifetimeConfiguration)
        }
    }
}

@objc public final class LifetimeTracker: NSObject {
    public typealias UpdateClosure = (_ trackedGroups: [String: LifetimeTracker.EntriesGroup]) -> Void
    public internal(set) static var instance: LifetimeTracker?
    private let lock = NSRecursiveLock()
    
    internal var trackedGroups = [String: EntriesGroup]()
    
    enum LifetimeState {
        case valid
        case leaky
    }
    
    public final class Entry {
        var maxCount: Int
        let name: String
        fileprivate(set) var count: Int
        fileprivate(set) var pointers: Set<String>
        
        init(name: String, maxCount: Int) {
            self.maxCount = maxCount
            self.name = name
            self.count = 0
            self.pointers = Set<String>()
        }
        
        func update(pointerString pointer: String, for countDelta: Int) {
            count += countDelta
            if countDelta > 0 {
                pointers.insert(pointer)
            } else {
                pointers.remove(pointer)
            }
        }
        
        var lifetimeState: LifetimeState {
            return count > maxCount ? .leaky : .valid
        }
    }
    
    @objc public final class EntriesGroup: NSObject {
        var maxCount: Int = 0
        var name: String? = nil
        fileprivate(set) var count: Int = 0
        public fileprivate(set) var entries = [String: Entry]()
        private var usedMaxCountOverride = false
        
        init(name: String) {
            if name != Constants.Identifier.EntryGroup.none {
                self.name = name
            }
        }
        
        var lifetimeState: LifetimeState {
            // Mark the group as leaky if the count per group highter than it's max count
            guard count <= maxCount else {
                return .leaky
            }
            // If the group total count isn't leaky, check if at least one entry is leaky
            let leakyEntries = entries.filter { (key: String, entry: LifetimeTracker.Entry) -> Bool in
                return entry.lifetimeState == .leaky
            }
            return leakyEntries.isEmpty ? .valid : .leaky
        }
        
        func updateEntry(_ configuration: LifetimeConfiguration, with countDelta: Int) {

            let entryName = configuration.instanceName
            let didEntryExistBefore = entries[entryName] != nil

            let entry = entries[entryName] ?? Entry(name: entryName, maxCount:configuration.maxCount)
            // Calculate the offset between the current and former maxCount in case the value was changed dynamically during the runtime
            let entryMaxCountOffset = configuration.maxCount - entry.maxCount
            entry.maxCount += entryMaxCountOffset
            entry.update(pointerString: configuration.pointerString, for: countDelta)
            entries[entryName] = entry

            count += countDelta

            if let groupMaxCount = configuration.groupMaxCount {
                usedMaxCountOverride = true
                maxCount = groupMaxCount
            } else if !usedMaxCountOverride && !didEntryExistBefore {
                maxCount += configuration.maxCount
            } else if entryMaxCountOffset != 0 {
                maxCount += entryMaxCountOffset
            }
        }
        
        public func stackDescription() -> [String: Any] {
            var stackEntries: [String: Any] = [:]
            entries.forEach {
                stackEntries[$1.name] = $1.count
            }
            
            return stackEntries
        }
        
        public func leakCount(rows: inout [EntryModel]) -> Int {
            var leaksCount = 0
            entries.sorted { (
                lhs: (key: String, value: LifetimeTracker.Entry),
                rhs: (key: String, value: LifetimeTracker.Entry)) -> Bool in
                lhs.value.count > rhs.value.count
                }
                .filter { (_, entry: LifetimeTracker.Entry) -> Bool in
                    entry.count > 0
                }.forEach { (_, entry: LifetimeTracker.Entry) in
                    var color: UIColor
                    switch entry.lifetimeState {
                    case .valid: color = .green
                    case .leaky:
                        color = .red
                        leaksCount += entry.count - entry.maxCount
                    }
                    
                    let entryMaxCountString = entry.maxCount == Int.max ? "∞" : "\(entry.maxCount)"
                    let description = "\(entry.name) (\(entry.count)/\(entryMaxCountString)):\n\(entry.pointers.joined(separator: ", "))"
                    rows.append((color: color, description: description))
            }
            return leaksCount
        }
    }
    
    @objc public static func setup(onUpdate: @escaping UpdateClosure) {
        assert(instance == nil)
        instance = LifetimeTracker(onUpdate: onUpdate)
    }
    
    private let onUpdate: UpdateClosure
    private init(onUpdate: @escaping UpdateClosure) {
        self.onUpdate = onUpdate
    }
    
    public func track(_ instance: Any, configuration: LifetimeConfiguration, file: String = #file) {
        lock.lock()
        defer {
            self.onUpdate(self.trackedGroups)
            lock.unlock()
        }
        
        var instanceName = ""
        let instanceTypeName = "\(String(reflecting: Swift.type(of: instance)))"
        let instanceTypeNames = instanceTypeName.components(separatedBy: ".")
        if instanceTypeNames.count == 2 {
            if let lastScreenName = instanceTypeNames.last {
                instanceName = lastScreenName
            } else {
                instanceName = ""
            }
        } else if instanceTypeNames.count == 3 {
            instanceName = instanceTypeNames.suffix(2).joined(separator: ".")
        } else {
            instanceName = instanceTypeName
        }

        var configuration = configuration
        configuration.instanceName = instanceName
        configuration.pointerString = "\(Unmanaged<AnyObject>.passUnretained(instance as AnyObject).toOpaque())"
        
        func update(_ configuration: LifetimeConfiguration, with countDelta: Int) {
            
            let groupName = configuration.groupName ?? Constants.Identifier.EntryGroup.none
            
            let group = self.trackedGroups[groupName] ?? EntriesGroup(name: groupName)
            group.updateEntry(configuration, with: countDelta)
            
            self.trackedGroups[groupName] = group
        }
        
        update(configuration, with: +1)
        
        onDealloc(of: instance) {
            self.lock.lock()
            defer {
                self.onUpdate(self.trackedGroups)
                self.lock.unlock()
            }
            
            update(configuration, with: -1)
        }
    }
    
    override public var debugDescription: String {
        lock.lock()
        defer {
            lock.unlock()
        }
        
        let keys = trackedGroups.keys.sorted(by: >)
        return keys.reduce("") { acc, key in
            if let group = trackedGroups[key], group.lifetimeState == .leaky {
                return acc + "\(String(describing: group.name)): \(group.count)\n"
            }
            
            return acc
        }
    }
}
