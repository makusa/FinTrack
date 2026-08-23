//
//  AppLogger.swift
//  FinTrack
//
//  Centralised OSLog loggers with privacy: .private on sensitive fields.
//  Use these instead of print() so that financial data never appears in
//  Console.app on a device not in developer mode (FIN-005).
//

import os

enum AppLogger {
    /// Persistence errors (SwiftData save/delete failures).
    static let persistence = Logger(subsystem: "ca.bmsk.fintrack", category: "persistence")
    /// Notification scheduling and permission errors.
    static let notifications = Logger(subsystem: "ca.bmsk.fintrack", category: "notifications")
    /// StoreKit / entitlement errors.
    static let entitlements = Logger(subsystem: "ca.bmsk.fintrack", category: "entitlements")
    /// CSV export operations.
    static let export = Logger(subsystem: "ca.bmsk.fintrack", category: "export")
    /// Seed / migration operations.
    static let seed = Logger(subsystem: "ca.bmsk.fintrack", category: "seed")
}
