//
//  BLEProtocol.swift
//  BLE_Chat
//
//  Created by BLE Chat Team on 2025/9/2.
//

import Foundation
import CoreBluetooth

/// BLE Protocol definitions for cross-platform compatibility
struct BLEProtocol {
    // GATT Service UUID
    static let CHAT_SERVICE_UUID = CBUUID(string: "550e8400-e29b-41d4-a716-446655440000")
    
    // Characteristic UUIDs
    static let MESSAGE_CHARACTERISTIC_UUID = CBUUID(string: "550e8400-e29b-41d4-a716-446655440001")
    static let FILE_TRANSFER_CHARACTERISTIC_UUID = CBUUID(string: "550e8400-e29b-41d4-a716-446655440002")
    static let CONTROL_CHARACTERISTIC_UUID = CBUUID(string: "550e8400-e29b-41d4-a716-446655440003")
    static let AUDIO_STREAM_CHARACTERISTIC_UUID = CBUUID(string: "550e8400-e29b-41d4-a716-446655440004")
    static let VIDEO_STREAM_CHARACTERISTIC_UUID = CBUUID(string: "550e8400-e29b-41d4-a716-446655440005")
    
    // Protocol constants
    static let MAX_MTU_SIZE = 517
    static let MIN_MTU_SIZE = 23
    static let HEADER_SIZE = 25
    static let MAX_PAYLOAD_SIZE = MAX_MTU_SIZE - HEADER_SIZE
    static let SCAN_TIMEOUT_MS: Int = 30000
    static let CONNECTION_TIMEOUT_MS: Int = 10000
    
    // Message types
    enum MessageType: UInt8, CaseIterable {
        case text = 0x01
        case image = 0x02
        case video = 0x03
        case audio = 0x04
        case file = 0x05
        case control = 0x06
        case ack = 0x07
        case heartbeat = 0x08
        case call_request = 0x09
        case call_response = 0x0A
        case call_end = 0x0B
    }
    
    // Connection states
    enum BLEConnectionState: String, CaseIterable {
        case disconnected = "Disconnected"
        case scanning = "Scanning"
        case advertising = "Advertising"
        case connecting = "Connecting"
        case connected = "Connected"
        case ready = "Ready"
        case error = "Error"
    }
    
    // Message header structure (25 bytes)
    struct MessageHeader {
        let version: UInt8 = 1
        let messageType: MessageType
        let messageId: UInt32
        let timestamp: UInt64
        let chunkIndex: UInt16
        let totalChunks: UInt16
        let payloadLength: UInt16
        let flags: UInt8
        let crc32: UInt32
        
        func toData() -> Data {
            var data = Data()
            data.append(version)
            data.append(messageType.rawValue)
            data.append(contentsOf: withUnsafeBytes(of: messageId.bigEndian) { Array($0) })
            data.append(contentsOf: withUnsafeBytes(of: timestamp.bigEndian) { Array($0) })
            data.append(contentsOf: withUnsafeBytes(of: chunkIndex.bigEndian) { Array($0) })
            data.append(contentsOf: withUnsafeBytes(of: totalChunks.bigEndian) { Array($0) })
            data.append(contentsOf: withUnsafeBytes(of: payloadLength.bigEndian) { Array($0) })
            data.append(flags)
            data.append(contentsOf: withUnsafeBytes(of: crc32.bigEndian) { Array($0) })
            return data
        }
        
        static func fromData(_ data: Data) -> MessageHeader? {
            guard data.count >= HEADER_SIZE else { return nil }
            
            let version = data[0]
            guard let messageType = MessageType(rawValue: data[1]) else { return nil }
            
            let messageId = data.subdata(in: 2..<6).withUnsafeBytes { $0.bindMemory(to: UInt32.self).first!.bigEndian }
            let timestamp = data.subdata(in: 6..<14).withUnsafeBytes { $0.bindMemory(to: UInt64.self).first!.bigEndian }
            let chunkIndex = data.subdata(in: 14..<16).withUnsafeBytes { $0.bindMemory(to: UInt16.self).first!.bigEndian }
            let totalChunks = data.subdata(in: 16..<18).withUnsafeBytes { $0.bindMemory(to: UInt16.self).first!.bigEndian }
            let payloadLength = data.subdata(in: 18..<20).withUnsafeBytes { $0.bindMemory(to: UInt16.self).first!.bigEndian }
            let flags = data[20]
            let crc32 = data.subdata(in: 21..<25).withUnsafeBytes { $0.bindMemory(to: UInt32.self).first!.bigEndian }
            
            return MessageHeader(
                messageType: messageType,
                messageId: messageId,
                timestamp: timestamp,
                chunkIndex: chunkIndex,
                totalChunks: totalChunks,
                payloadLength: payloadLength,
                flags: flags,
                crc32: crc32
            )
        }
    }
}

// MARK: - Error Types
enum BLEChatError: Error, LocalizedError {
    case bluetoothUnavailable
    case bluetoothUnauthorized
    case connectionFailed
    case transmissionFailed
    case invalidData
    case timeout
    case unknownError(String)
    
    var errorDescription: String? {
        switch self {
        case .bluetoothUnavailable:
            return "Bluetooth is not available on this device"
        case .bluetoothUnauthorized:
            return "Bluetooth permission is required"
        case .connectionFailed:
            return "Failed to connect to device"
        case .transmissionFailed:
            return "Failed to transmit data"
        case .invalidData:
            return "Invalid data received"
        case .timeout:
            return "Operation timed out"
        case .unknownError(let message):
            return "Unknown error: \(message)"
        }
    }
}