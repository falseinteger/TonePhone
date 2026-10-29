//
//  AppLog.swift
//  TonePhone
//
//  App-side errors go to the unified log and to the TonePhone log file,
//  so they show up in Console and in the Logs window.
//

import os

enum AppLog {
    private static let logger = Logger(subsystem: "io.falseinteger.tonephone", category: "app")

    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
        TonePhoneCore.log(message, level: .error)
    }
}
