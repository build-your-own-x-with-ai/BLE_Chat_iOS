//
//  BLEChatManager.swift
//  BLE_Chat
//
//  Created by BLE Chat Team on 2025/9/2.
//

import Foundation
import CoreBluetooth
import Combine

class BLEChatManager: NSObject, ObservableObject {
    // MARK: - Published Properties
    @Published var connectionState: BLEProtocol.BLEConnectionState = .disconnected
    @Published var discoveredDevices: [CBPeripheral] = []
    @Published var connectedDevice: CBPeripheral?
    @Published var isScanning: Bool = false
    @Published var isAdvertising: Bool = false
    @Published var receivedMessages: [ChatMessage] = []
    
    // MARK: - Private Properties
    private var centralManager: CBCentralManager?
    private var peripheralManager: CBPeripheralManager?
    private var connectedPeripheral: CBPeripheral?
    private var messageCharacteristic: CBCharacteristic?
    private var fileTransferCharacteristic: CBCharacteristic?
    private var controlCharacteristic: CBCharacteristic?
    
    // GATT Service and Characteristics for peripheral mode
    private var chatService: CBMutableService?
    private var messageChar: CBMutableCharacteristic?
    private var fileTransferChar: CBMutableCharacteristic?
    private var controlChar: CBMutableCharacteristic?
    
    // Message handling
    private var messageReassembly: [UInt32: MessageReassemblyData] = [:]
    private var messageIdCounter: UInt32 = 0
    private var messageIndex: Int = 0  // For unique message indexing
    
    // MARK: - Callbacks
    var onMessageReceived: ((ChatMessage) -> Void)?
    var onConnectionStateChanged: ((BLEProtocol.BLEConnectionState) -> Void)?
    var onError: ((BLEChatError) -> Void)?
    
    // MARK: - Initialization
    override init() {
        super.init()
        setupManagers()
    }
    
    private func setupManagers() {
        centralManager = CBCentralManager(delegate: self, queue: nil)
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
    }
    
    // MARK: - Public Methods
    
    /// Start scanning for nearby devices
    func startScanning() {
        guard let centralManager = centralManager,
              centralManager.state == .poweredOn else {
            updateConnectionState(.error)
            onError?(.bluetoothUnavailable)
            return
        }
        
        centralManager.scanForPeripherals(
            withServices: [BLEProtocol.CHAT_SERVICE_UUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        
        isScanning = true
        updateConnectionState(.scanning)
        
        // Stop scanning after timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(BLEProtocol.SCAN_TIMEOUT_MS)) {
            if self.isScanning {
                self.stopScanning()
            }
        }
    }
    
    /// Stop scanning for devices
    func stopScanning() {
        centralManager?.stopScan()
        isScanning = false
        if connectionState == .scanning {
            updateConnectionState(.disconnected)
        }
    }
    
    /// Start advertising as a peripheral
    func startAdvertising() {
        guard let peripheralManager = peripheralManager,
              peripheralManager.state == .poweredOn else {
            updateConnectionState(.error)
            onError?(.bluetoothUnavailable)
            return
        }
        
        setupGATTService()
        
        let advertisementData: [String: Any] = [
            CBAdvertisementDataServiceUUIDsKey: [BLEProtocol.CHAT_SERVICE_UUID],
            CBAdvertisementDataLocalNameKey: "BLE Chat"
        ]
        
        peripheralManager.startAdvertising(advertisementData)
        isAdvertising = true
        updateConnectionState(.advertising)
    }
    
    /// Stop advertising
    func stopAdvertising() {
        print("iOS: Stopping advertising")
        peripheralManager?.stopAdvertising()
        isAdvertising = false
        if connectionState == .advertising {
            updateConnectionState(.disconnected)
        }
    }
    
    /// Connect to a discovered device
    func connectToDevice(_ peripheral: CBPeripheral) {
        guard let centralManager = centralManager else { return }
        
        stopScanning()
        connectedPeripheral = peripheral
        peripheral.delegate = self
        updateConnectionState(.connecting)
        
        centralManager.connect(peripheral, options: nil)
        
        // Connection timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(BLEProtocol.CONNECTION_TIMEOUT_MS)) {
            if self.connectionState == .connecting {
                self.centralManager?.cancelPeripheralConnection(peripheral)
                self.updateConnectionState(.error)
                self.onError?(.connectionFailed)
            }
        }
    }
    
    /// Disconnect from current device
    func disconnect() {
        if let peripheral = connectedPeripheral {
            centralManager?.cancelPeripheralConnection(peripheral)
        }
        
        stopScanning()
        stopAdvertising()
        cleanup()
        updateConnectionState(.disconnected)
    }
    
    /// Send a text message
    func sendMessage(_ message: String) {
        let messageId = generateMessageId()
        let chatMessage = ChatMessage(
            id: messageId,
            type: .text,
            content: message,
            timestamp: Date(),
            isFromCurrentUser: true
        )
        
        sendChatMessage(chatMessage)
    }
    
    /// Send an image message
    func sendImage(_ imageData: Data) {
        let chatMessage = ChatMessage(
            id: generateMessageId(),
            type: .image,
            content: "Image",
            imageData: imageData,
            timestamp: Date(),
            isFromCurrentUser: true
        )
        
        sendChatMessage(chatMessage)
    }
    
    /// Send a video message
    func sendVideo(_ videoData: Data) {
        let chatMessage = ChatMessage(
            id: generateMessageId(),
            type: .video,
            content: "Video",
            videoData: videoData,
            timestamp: Date(),
            isFromCurrentUser: true
        )
        
        sendChatMessage(chatMessage)
    }
    
    // MARK: - Private Methods
    
    private func updateConnectionState(_ state: BLEProtocol.BLEConnectionState) {
        DispatchQueue.main.async {
            self.connectionState = state
            self.onConnectionStateChanged?(state)
        }
    }
    
    private func setupGATTService() {
        chatService = CBMutableService(type: BLEProtocol.CHAT_SERVICE_UUID, primary: true)
        
        // Message characteristic
        messageChar = CBMutableCharacteristic(
            type: BLEProtocol.MESSAGE_CHARACTERISTIC_UUID,
            properties: [.read, .write, .notify],
            value: nil,
            permissions: [.readable, .writeable]
        )
        
        // File transfer characteristic
        fileTransferChar = CBMutableCharacteristic(
            type: BLEProtocol.FILE_TRANSFER_CHARACTERISTIC_UUID,
            properties: [.read, .write, .notify],
            value: nil,
            permissions: [.readable, .writeable]
        )
        
        // Control characteristic
        controlChar = CBMutableCharacteristic(
            type: BLEProtocol.CONTROL_CHARACTERISTIC_UUID,
            properties: [.read, .write, .notify],
            value: nil,
            permissions: [.readable, .writeable]
        )
        
        chatService?.characteristics = [messageChar!, fileTransferChar!, controlChar!]
        peripheralManager?.add(chatService!)
    }
    
    private func generateMessageId() -> UInt32 {
        messageIdCounter += 1
        // Use high bit to distinguish our messages from received ones
        // Our messages: 0x80000000 + counter
        // Received messages: use their original ID
        return 0x80000000 + messageIdCounter
    }
    
    private func sendChatMessage(_ message: ChatMessage) {
        guard connectionState == .ready else { return }
        
        do {
            let messageData: Data
            let messageType: BLEProtocol.MessageType
            
            switch message.type {
            case .image:
                // For image messages, send binary data directly
                messageType = .image
                if let imageData = message.imageData {
                    // Create binary format: [metadata_length][metadata_json][image_data]
                    let metadata: [String: Any] = [
                        "id": String(message.id),
                        "type": "image",
                        "content": message.content,
                        "timestamp": String(message.timestamp),
                        "isFromCurrentUser": String(message.isFromCurrentUser)
                    ]
                    
                    let metadataJson = try JSONSerialization.data(withJSONObject: metadata)
                    let metadataLength = UInt16(metadataJson.count)
                    
                    var binaryData = Data()
                    binaryData.append(UInt8(metadataLength >> 8))
                    binaryData.append(UInt8(metadataLength & 0xFF))
                    binaryData.append(metadataJson)
                    binaryData.append(imageData)
                    
                    messageData = binaryData
                    print("iOS: Sending image message - metadata: \(metadataJson.count) bytes, image: \(imageData.count) bytes, total: \(messageData.count) bytes")
                } else {
                    print("iOS: Image message has no image data")
                    return
                }
                
            case .video:
                // For video messages, send binary data directly
                messageType = .video
                if let videoData = message.videoData {
                    let metadata: [String: Any] = [
                        "id": String(message.id),
                        "type": "video",
                        "content": message.content,
                        "timestamp": String(message.timestamp),
                        "isFromCurrentUser": String(message.isFromCurrentUser)
                    ]
                    
                    let metadataJson = try JSONSerialization.data(withJSONObject: metadata)
                    let metadataLength = UInt16(metadataJson.count)
                    
                    var binaryData = Data()
                    binaryData.append(UInt8(metadataLength >> 8))
                    binaryData.append(UInt8(metadataLength & 0xFF))
                    binaryData.append(metadataJson)
                    binaryData.append(videoData)
                    
                    messageData = binaryData
                    print("iOS: Sending video message - metadata: \(metadataJson.count) bytes, video: \(videoData.count) bytes, total: \(messageData.count) bytes")
                } else {
                    print("iOS: Video message has no video data")
                    return
                }
                
            default:
                // For text and other messages, use JSON
                messageType = .text
                let messageForJson = ChatMessage(
                    id: message.id,
                    type: message.type,
                    content: message.content,
                    imageData: nil, // Don't include binary data in JSON
                    videoData: nil,
                    timestamp: Date(timeIntervalSince1970: TimeInterval(message.timestamp) / 1000.0),
                    isFromCurrentUser: message.isFromCurrentUser
                )
                messageData = try JSONEncoder().encode(messageForJson)
                let messageString = String(data: messageData, encoding: .utf8) ?? "[Invalid UTF-8]"
                print("iOS: Sending text message JSON: \(messageString)")
            }
            
            let hexBytes = messageData.map { String(format: "%02X", $0) }.joined(separator: " ")
            print("iOS: Message data bytes (\(messageData.count) bytes): \(hexBytes)")
            let chunks = createMessageChunks(data: messageData, messageId: message.id, type: messageType)
            
            for chunk in chunks {
                sendChunk(chunk)
            }
            
            // Add to our own messages
            DispatchQueue.main.async {
                // Check if message already exists to avoid duplicates
                if !self.receivedMessages.contains(where: { $0.id == message.id && $0.isFromCurrentUser == message.isFromCurrentUser }) {
                    self.receivedMessages.append(message)
                }
            }
            
        } catch {
            onError?(.transmissionFailed)
        }
    }
    
    private func createMessageChunks(data: Data, messageId: UInt32, type: BLEProtocol.MessageType) -> [Data] {
        let maxPayloadSize = BLEProtocol.MAX_PAYLOAD_SIZE
        var chunks: [Data] = []
        let totalChunks = UInt16((data.count + maxPayloadSize - 1) / maxPayloadSize)
        
        print("iOS: Creating message chunks - messageId: \(messageId), totalSize: \(data.count), totalChunks: \(totalChunks)")
        print("iOS: Original message data (\(data.count) bytes): \(data.map { String(format: "%02X", $0) }.joined(separator: " "))")
        
        for chunkIndex in 0..<totalChunks {
            let startIndex = Int(chunkIndex) * maxPayloadSize
            let endIndex = min(startIndex + maxPayloadSize, data.count)
            let payload = data.subdata(in: startIndex..<endIndex)
            
            let header = BLEProtocol.MessageHeader(
                messageType: type,
                messageId: messageId,
                timestamp: UInt64(Date().timeIntervalSince1970 * 1000),
                chunkIndex: chunkIndex,
                totalChunks: totalChunks,
                payloadLength: UInt16(payload.count),
                flags: 0,
                crc32: calculateCRC32(payload)
            )
            
            var chunkData = header.toData()
            chunkData.append(payload)
            chunks.append(chunkData)
            
            print("iOS: Chunk \(chunkIndex): header (\(header.toData().count) bytes) + payload (\(payload.count) bytes) = total (\(chunkData.count) bytes)")
            print("iOS: Header bytes: \(header.toData().map { String(format: "%02X", $0) }.joined(separator: " "))")
            print("iOS: Payload bytes: \(payload.map { String(format: "%02X", $0) }.joined(separator: " "))")
        }
        
        return chunks
    }
    
    private func sendChunk(_ chunkData: Data) {
        // Print binary data being sent
        print("iOS: Sending chunk (\(chunkData.count) bytes): \(chunkData.map { String(format: "%02X", $0) }.joined(separator: " "))")
        
        if let peripheral = connectedPeripheral, let characteristic = messageCharacteristic {
            peripheral.writeValue(chunkData, for: characteristic, type: .withResponse)
        } else if let peripheralManager = peripheralManager, let characteristic = messageChar {
            peripheralManager.updateValue(chunkData, for: characteristic, onSubscribedCentrals: nil)
        }
    }
    
    private func handleReceivedChunk(_ data: Data) {
        // Print binary data being received
        print("iOS: Received chunk (\(data.count) bytes): \(data.map { String(format: "%02X", $0) }.joined(separator: " "))")
        
        // Validate minimum data size
        guard data.count >= BLEProtocol.HEADER_SIZE else {
            print("iOS: Received data too small for header (\(data.count) < \(BLEProtocol.HEADER_SIZE))")
            onError?(.invalidData)
            return
        }
        
        guard let header = BLEProtocol.MessageHeader.fromData(data) else {
            print("iOS: Failed to parse message header")
            onError?(.invalidData)
            return
        }
        
        print("iOS: Parsed header - messageId: \(header.messageId), type: \(header.messageType), chunkIndex: \(header.chunkIndex), totalChunks: \(header.totalChunks)")
        
        // Validate payload size matches header
        let expectedPayloadSize = Int(header.payloadLength)
        let actualDataSize = data.count - BLEProtocol.HEADER_SIZE
        
        guard actualDataSize >= expectedPayloadSize else {
            print("iOS: Payload size mismatch - expected: \(expectedPayloadSize), actual: \(actualDataSize)")
            onError?(.invalidData)
            return
        }
        
        let payload = data.subdata(in: BLEProtocol.HEADER_SIZE..<(BLEProtocol.HEADER_SIZE + expectedPayloadSize))
        print("iOS: Payload (\(payload.count) bytes): \(payload.map { String(format: "%02X", $0) }.joined(separator: " "))")
        
        // Verify CRC
        let calculatedCRC = calculateCRC32(payload)
        guard calculatedCRC == header.crc32 else {
            print("iOS: CRC mismatch - calculated: \(String(calculatedCRC, radix: 16)), received: \(String(header.crc32, radix: 16))")
            onError?(.invalidData)
            return
        }
        
        print("iOS: CRC verification passed")
        
        // Handle message reassembly
        if header.totalChunks == 1 {
            // Single chunk message
            print("iOS: Processing single chunk message")
            processCompleteMessage(payload, type: header.messageType)
        } else {
            // Multi-chunk message
            print("iOS: Processing multi-chunk message")
            reassembleMessage(header: header, payload: payload)
        }
    }
    
    private func reassembleMessage(header: BLEProtocol.MessageHeader, payload: Data) {
        let messageId = header.messageId
        
        if messageReassembly[messageId] == nil {
            messageReassembly[messageId] = MessageReassemblyData(
                totalChunks: header.totalChunks,
                messageType: header.messageType
            )
        }
        
        guard let reassemblyData = messageReassembly[messageId] else { return }
        reassemblyData.chunks[header.chunkIndex] = payload
        
        // Check if all chunks received
        if reassemblyData.chunks.count == reassemblyData.totalChunks {
            var completeData = Data()
            for i in 0..<reassemblyData.totalChunks {
                if let chunkData = reassemblyData.chunks[i] {
                    completeData.append(chunkData)
                }
            }
            
            processCompleteMessage(completeData, type: reassemblyData.messageType)
            messageReassembly.removeValue(forKey: messageId)
        }
    }
    
    private func processCompleteMessage(_ data: Data, type: BLEProtocol.MessageType) {
        do {
            switch type {
            case .image:
                // Handle binary image message
                guard data.count >= 2 else {
                    print("iOS: Invalid image message format - too short")
                    onError?(.invalidData)
                    return
                }
                
                let metadataLength = Int(data[0]) << 8 | Int(data[1])
                guard data.count >= 2 + metadataLength else {
                    print("iOS: Invalid image message format - metadata length mismatch")
                    onError?(.invalidData)
                    return
                }
                
                let metadataData = data.subdata(in: 2..<(2 + metadataLength))
                let imageData = data.subdata(in: (2 + metadataLength)..<data.count)
                
                guard let metadataString = String(data: metadataData, encoding: .utf8) else {
                    print("iOS: Failed to decode metadata")
                    onError?(.invalidData)
                    return
                }
                
                print("iOS: Processing image message - metadata: \(metadataString), image size: \(imageData.count) bytes")
                
                guard let metadataJson = try? JSONSerialization.jsonObject(with: metadataData) as? [String: Any] else {
                    print("iOS: Failed to parse metadata JSON")
                    onError?(.invalidData)
                    return
                }
                
                guard let idString = metadataJson["id"] as? String,
                      let messageId = UInt32(idString),
                      let content = metadataJson["content"] as? String,
                      let timestampString = metadataJson["timestamp"] as? String,
                      let timestamp = UInt64(timestampString) else {
                    print("iOS: Failed to parse metadata fields")
                    onError?(.invalidData)
                    return
                }
                
                let receivedMessage = ChatMessage(
                    id: messageId,
                    type: .image,
                    content: content,
                    imageData: imageData,
                    videoData: nil,
                    timestamp: Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000.0),
                    isFromCurrentUser: false
                )
                
                print("iOS: Successfully parsed image message - id: \(receivedMessage.id), content: \(receivedMessage.content), image size: \(imageData.count)")
                
                DispatchQueue.main.async {
                    let isDuplicate = self.receivedMessages.contains { existingMessage in
                        return existingMessage.id == receivedMessage.id &&
                               existingMessage.isFromCurrentUser == receivedMessage.isFromCurrentUser &&
                               existingMessage.timestamp == receivedMessage.timestamp
                    }
                    
                    if !isDuplicate {
                        self.receivedMessages.append(receivedMessage)
                        self.onMessageReceived?(receivedMessage)
                        print("iOS: Added image message to list, total messages: \(self.receivedMessages.count)")
                    } else {
                        print("iOS: Duplicate image message detected, skipping")
                    }
                }
                
            case .video:
                // Handle binary video message
                guard data.count >= 2 else {
                    print("iOS: Invalid video message format - too short")
                    onError?(.invalidData)
                    return
                }
                
                let metadataLength = Int(data[0]) << 8 | Int(data[1])
                guard data.count >= 2 + metadataLength else {
                    print("iOS: Invalid video message format - metadata length mismatch")
                    onError?(.invalidData)
                    return
                }
                
                let metadataData = data.subdata(in: 2..<(2 + metadataLength))
                let videoData = data.subdata(in: (2 + metadataLength)..<data.count)
                
                guard let metadataString = String(data: metadataData, encoding: .utf8) else {
                    print("iOS: Failed to decode video metadata")
                    onError?(.invalidData)
                    return
                }
                
                print("iOS: Processing video message - metadata: \(metadataString), video size: \(videoData.count) bytes")
                
                guard let metadataJson = try? JSONSerialization.jsonObject(with: metadataData) as? [String: Any] else {
                    print("iOS: Failed to parse video metadata JSON")
                    onError?(.invalidData)
                    return
                }
                
                guard let idString = metadataJson["id"] as? String,
                      let messageId = UInt32(idString),
                      let content = metadataJson["content"] as? String,
                      let timestampString = metadataJson["timestamp"] as? String,
                      let timestamp = UInt64(timestampString) else {
                    print("iOS: Failed to parse video metadata fields")
                    onError?(.invalidData)
                    return
                }
                
                let receivedMessage = ChatMessage(
                    id: messageId,
                    type: .video,
                    content: content,
                    imageData: nil,
                    videoData: videoData,
                    timestamp: Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000.0),
                    isFromCurrentUser: false
                )
                
                print("iOS: Successfully parsed video message - id: \(receivedMessage.id), content: \(receivedMessage.content), video size: \(videoData.count)")
                
                DispatchQueue.main.async {
                    let isDuplicate = self.receivedMessages.contains { existingMessage in
                        return existingMessage.id == receivedMessage.id &&
                               existingMessage.isFromCurrentUser == receivedMessage.isFromCurrentUser &&
                               existingMessage.timestamp == receivedMessage.timestamp
                    }
                    
                    if !isDuplicate {
                        self.receivedMessages.append(receivedMessage)
                        self.onMessageReceived?(receivedMessage)
                        print("iOS: Added video message to list, total messages: \(self.receivedMessages.count)")
                    } else {
                        print("iOS: Duplicate video message detected, skipping")
                    }
                }
                
            default:
                // Handle JSON text message
                let messageString = String(data: data, encoding: .utf8) ?? "[Invalid UTF-8]"
                print("iOS: Processing text message: \(messageString)")
                print("iOS: Message data bytes (\(data.count) bytes): \(data.map { String(format: "%02X", $0) }.joined(separator: " "))")
                
                // Validate JSON format
                guard let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []) else {
                    print("iOS: Invalid JSON format")
                    onError?(.invalidData)
                    return
                }
                
                let message = try JSONDecoder().decode(ChatMessage.self, from: data)
                var receivedMessage = message
                receivedMessage.isFromCurrentUser = false
                
                print("iOS: Successfully parsed text message - id: \(receivedMessage.id), content: \(receivedMessage.content)")
                
                DispatchQueue.main.async {
                    let isDuplicate = self.receivedMessages.contains { existingMessage in
                        return existingMessage.id == receivedMessage.id &&
                               existingMessage.isFromCurrentUser == receivedMessage.isFromCurrentUser &&
                               existingMessage.timestamp == receivedMessage.timestamp
                    }
                    
                    if !isDuplicate {
                        self.receivedMessages.append(receivedMessage)
                        self.onMessageReceived?(receivedMessage)
                        print("iOS: Added text message to list, total messages: \(self.receivedMessages.count)")
                    } else {
                        print("iOS: Duplicate text message detected, skipping")
                    }
                }
            }
        } catch {
            print("iOS: Failed to process message: \(error)")
            print("iOS: Raw data: \(String(data: data, encoding: .utf8) ?? "Invalid UTF-8")")
            onError?(.invalidData)
        }
    }
    
    private func calculateCRC32(_ data: Data) -> UInt32 {
        // Simple CRC32 implementation
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                if (crc & 1) != 0 {
                    crc = (crc >> 1) ^ 0xEDB88320
                } else {
                    crc >>= 1
                }
            }
        }
        return ~crc
    }
    
    private func cleanup() {
        connectedPeripheral = nil
        connectedDevice = nil
        messageCharacteristic = nil
        fileTransferCharacteristic = nil
        controlCharacteristic = nil
        messageReassembly.removeAll()
        discoveredDevices.removeAll()
    }
}

// MARK: - CBCentralManagerDelegate
extension BLEChatManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            break
        case .poweredOff, .unsupported, .unauthorized, .resetting, .unknown:
            updateConnectionState(.error)
            onError?(.bluetoothUnavailable)
        @unknown default:
            break
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        if !discoveredDevices.contains(where: { $0.identifier == peripheral.identifier }) {
            DispatchQueue.main.async {
                self.discoveredDevices.append(peripheral)
            }
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        updateConnectionState(.connected)
        connectedDevice = peripheral
        peripheral.discoverServices([BLEProtocol.CHAT_SERVICE_UUID])
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        cleanup()
        updateConnectionState(.disconnected)
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        updateConnectionState(.error)
        onError?(.connectionFailed)
    }
}

// MARK: - CBPeripheralDelegate
extension BLEChatManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        
        for service in services {
            if service.uuid == BLEProtocol.CHAT_SERVICE_UUID {
                peripheral.discoverCharacteristics([
                    BLEProtocol.MESSAGE_CHARACTERISTIC_UUID,
                    BLEProtocol.FILE_TRANSFER_CHARACTERISTIC_UUID,
                    BLEProtocol.CONTROL_CHARACTERISTIC_UUID
                ], for: service)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        
        for characteristic in characteristics {
            switch characteristic.uuid {
            case BLEProtocol.MESSAGE_CHARACTERISTIC_UUID:
                messageCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            case BLEProtocol.FILE_TRANSFER_CHARACTERISTIC_UUID:
                fileTransferCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            case BLEProtocol.CONTROL_CHARACTERISTIC_UUID:
                controlCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            default:
                break
            }
        }
        
        updateConnectionState(.ready)
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("iOS: Error receiving data: \(error)")
            onError?(.transmissionFailed)
            return
        }
        
        guard let data = characteristic.value else {
            print("iOS: No data received")
            return
        }
        
        print("iOS: Received notification with \(data.count) bytes")
        if data.count > 0 {
            handleReceivedChunk(data)
        } else {
            print("iOS: Received empty notification data")
        }
    }
}

// MARK: - CBPeripheralManagerDelegate
extension BLEChatManager: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            break
        case .poweredOff, .unsupported, .unauthorized, .resetting, .unknown:
            updateConnectionState(.error)
            onError?(.bluetoothUnavailable)
        @unknown default:
            break
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if error != nil {
            onError?(.unknownError("Failed to add service"))
        }
    }
    
    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if error != nil {
            onError?(.unknownError("Failed to start advertising"))
            isAdvertising = false
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        print("iOS: Central \(central.identifier) subscribed to \(characteristic.uuid)")
        // When a central subscribes, it means they're ready to communicate
        stopAdvertising()  // Stop advertising when connected
        print("iOS: Stopped advertising, updating state to connected")
        updateConnectionState(.connected)
        
        // Set connected device for UI purposes
        DispatchQueue.main.async {
            // Create a fake peripheral object for UI consistency
            // In real scenario, we'd need to track the central differently
            self.connectedDevice = nil // We don't have a CBPeripheral in this case
        }
        
        // Wait a moment then transition to ready state
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            print("iOS: Transitioning to ready state")
            self.updateConnectionState(.ready)
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            if let data = request.value {
                print("iOS: Received write request with \(data.count) bytes")
                if data.count > 0 {
                    handleReceivedChunk(data)
                    peripheral.respond(to: request, withResult: .success)
                } else {
                    print("iOS: Received empty data, responding with error")
                    peripheral.respond(to: request, withResult: .invalidAttributeValueLength)
                }
            } else {
                print("iOS: Received write request with no data")
                peripheral.respond(to: request, withResult: .invalidAttributeValueLength)
            }
        }
    }
}

// MARK: - Supporting Data Structures
class MessageReassemblyData {
    let totalChunks: UInt16
    let messageType: BLEProtocol.MessageType
    var chunks: [UInt16: Data] = [:]
    
    init(totalChunks: UInt16, messageType: BLEProtocol.MessageType) {
        self.totalChunks = totalChunks
        self.messageType = messageType
    }
}

struct ChatMessage: Codable, Identifiable, Equatable {
    let id: UInt32
    let type: MessageType
    let content: String
    let imageData: Data?
    let videoData: Data?
    let timestamp: UInt64  // Changed from Date to UInt64 to match Android
    var isFromCurrentUser: Bool
    
    enum MessageType: String, Codable {
        case text = "text"
        case image = "image"
        case video = "video"
        case audio = "audio"
        case file = "file"
        
        // Custom decoder to handle case-insensitive type matching
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let rawValue = try container.decode(String.self)
            
            switch rawValue.lowercased() {
            case "text":
                self = .text
            case "image":
                self = .image
            case "video":
                self = .video
            case "audio":
                self = .audio
            case "file":
                self = .file
            default:
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: decoder.codingPath,
                        debugDescription: "Cannot initialize MessageType from invalid String value \(rawValue)"
                    )
                )
            }
        }
        
        // Custom encoder to always use lowercase
        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(self.rawValue)
        }
    }
    
    init(id: UInt32, type: MessageType, content: String, imageData: Data? = nil, videoData: Data? = nil, timestamp: Date, isFromCurrentUser: Bool) {
        self.id = id
        self.type = type
        self.content = content
        self.imageData = imageData
        self.videoData = videoData
        self.timestamp = UInt64(timestamp.timeIntervalSince1970 * 1000)  // Convert Date to milliseconds timestamp
        self.isFromCurrentUser = isFromCurrentUser
    }
}
