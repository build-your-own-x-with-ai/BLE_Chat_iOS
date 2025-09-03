//
//  DeviceListView.swift
//  BLE_Chat
//
//  Created by BLE Chat Team on 2025/9/2.
//

import SwiftUI
import CoreBluetooth

struct DeviceListView: View {
    @ObservedObject var bleManager: BLEChatManager
    @Binding var showingChat: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    var body: some View {
        NavigationView {
            VStack {
                // Header
                VStack(spacing: 10) {
                    HStack {
                        Image(systemName: "magnifyingglass.circle.fill")
                            .font(.title)
                            .foregroundColor(.blue)
                        
                        Text("搜索设备")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Spacer()
                        
                        // Scanning indicator
                        if bleManager.isScanning {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                    }
                    
                    Text("扫描附近的BLE聊天设备...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(15)
                .padding(.horizontal)
                
                // Connection Status
                if bleManager.connectionState != .disconnected && bleManager.connectionState != .scanning {
                    HStack {
                        Circle()
                            .fill(connectionStateColor)
                            .frame(width: 10, height: 10)
                        
                        Text(connectionStateText)
                            .font(.caption)
                            .foregroundColor(connectionStateColor)
                    }
                    .padding(.top, 5)
                }
                
                // Device List
                if bleManager.discoveredDevices.isEmpty {
                    Spacer()
                    
                    VStack(spacing: 20) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 50))
                            .foregroundColor(.gray)
                        
                        VStack(spacing: 10) {
                            Text("正在搜索设备...")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            Text("请确保目标设备已开启广播\n并且在蓝牙范围内")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    
                    Spacer()
                } else {
                    List {
                        ForEach(bleManager.discoveredDevices, id: \.identifier) { device in
                            DeviceRow(device: device) {
                                connectToDevice(device)
                            }
                        }
                    }
                    .listStyle(PlainListStyle())
                }
                
                // Control Buttons
                HStack(spacing: 20) {
                    // Cancel/Close Button
                    Button("取消") {
                        bleManager.stopScanning()
                        dismiss()
                    }
                    .foregroundColor(.red)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(10)
                    
                    // Refresh Button
                    Button("刷新") {
                        refreshScan()
                    }
                    .foregroundColor(.blue)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(10)
                    .disabled(bleManager.connectionState == .connecting)
                }
                .padding()
            }
            .navigationTitle("")
            .navigationBarHidden(true)
        }
        .alert("连接错误", isPresented: $showingAlert) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
        .onAppear {
            setupErrorHandling()
        }
        .onReceive(bleManager.$connectionState) { state in
            if state == .ready {
                showingChat = true
                dismiss()
            }
        }
    }
    
    private var connectionStateColor: Color {
        switch bleManager.connectionState {
        case .connected, .ready:
            return .green
        case .connecting:
            return .orange
        case .scanning:
            return .blue
        case .error:
            return .red
        default:
            return .gray
        }
    }
    
    private var connectionStateText: String {
        switch bleManager.connectionState {
        case .connecting:
            return "连接中..."
        case .connected:
            return "已连接"
        case .ready:
            return "就绪"
        case .error:
            return "连接错误"
        default:
            return ""
        }
    }
    
    private func connectToDevice(_ device: CBPeripheral) {
        bleManager.connectToDevice(device)
    }
    
    private func refreshScan() {
        bleManager.discoveredDevices.removeAll()
        if !bleManager.isScanning {
            bleManager.startScanning()
        }
    }
    
    private func setupErrorHandling() {
        bleManager.onError = { error in
            DispatchQueue.main.async {
                self.alertMessage = error.localizedDescription
                self.showingAlert = true
            }
        }
    }
}

struct DeviceRow: View {
    let device: CBPeripheral
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(deviceName)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(device.identifier.uuidString)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                VStack {
                    Image(systemName: "iphone")
                        .font(.title2)
                        .foregroundColor(.blue)
                    
                    Text("连接")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var deviceName: String {
        return device.name ?? "未知设备"
    }
}

struct DeviceListView_Previews: PreviewProvider {
    static var previews: some View {
        DeviceListView(
            bleManager: BLEChatManager(),
            showingChat: .constant(false)
        )
    }
}