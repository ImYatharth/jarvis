//
//  JarvisAnalytics.swift
//  Jarvis
//
//  Publication-safe analytics shim. Jarvis intentionally ships with no
//  bundled third-party telemetry configuration in the open source build.
//

import Foundation

enum JarvisAnalytics {
    static func configure() {}
    static func trackAppOpened() {}
    static func trackOnboardingStarted() {}
    static func trackOnboardingReplayed() {}
    static func trackOnboardingDemoTriggered() {}
    static func trackAllPermissionsGranted() {}
    static func trackPermissionGranted(permission: String) {}
    static func trackPushToTalkStarted() {}
    static func trackPushToTalkReleased() {}
    static func trackUserMessageSent(transcript: String) {}
}
