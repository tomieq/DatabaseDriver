//
//  ServerHandshake.swift
//  DatabaseDriver
//
//  Created by: tomieq on 18/05/2026
//
import Foundation

struct ServerHandshake {
    let scramble: Data
    let authPluginName: String
}
