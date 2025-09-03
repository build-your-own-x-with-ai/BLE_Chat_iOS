//
//  ContentView.swift
//  BLE_Chat
//
//  Created by i on 2025/9/1.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var bleManager = BLEChatManager()
    @State private var showingDeviceList = false
    @State private var showingChat = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                // App Title
                VStack {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)
                    
                    Text("BLE Chat")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("蓝牙聊天应用")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 50)
                
                // Connection Status
                HStack {
                    Circle()
                        .fill(connectionStateColor)
                        .frame(width: 12, height: 12)
                    
                    Text(connectionStateText)
                        .font(.headline)
                        .foregroundColor(connectionStateColor)
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(20)
                
                Spacer()
                
                // Main Action Buttons
                VStack(spacing: 20) {
                    // Scan Button
                    Button(action: {
                        if bleManager.isScanning {
                            bleManager.stopScanning()
                        } else {
                            bleManager.startScanning()
                            showingDeviceList = true
                        }
                    }) {
                        HStack {
                            Image(systemName: bleManager.isScanning ? "stop.circle" : "magnifyingglass.circle")
                                .font(.title2)
                            Text(bleManager.isScanning ? "停止扫描" : "扫描设备")
                                .font(.headline)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(bleManager.isScanning ? Color.red : Color.blue)
                        .cornerRadius(15)
                    }
                    .disabled(bleManager.connectionState == .connecting)
                    
                    // Broadcast Button
                    Button(action: {
                        if bleManager.isAdvertising {
                            bleManager.stopAdvertising()
                        } else {
                            bleManager.startAdvertising()
                        }
                    }) {
                        HStack {
                            Image(systemName: bleManager.isAdvertising ? "stop.circle" : "radio.fill")
                                .font(.title2)
                            Text(bleManager.isAdvertising ? "停止广播" : "开始广播")
                                .font(.headline)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(bleManager.isAdvertising ? Color.red : Color.green)
                        .cornerRadius(15)
                    }
                    .disabled(bleManager.connectionState == .connecting)
                }
                .padding(.horizontal, 30)
                
                Spacer()
                
                // Instructions
                VStack(alignment: .leading, spacing: 10) {
                    Text("使用说明:")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text("• 扫描: 搜索附近的BLE聊天设备")
                    Text("• 广播: 让其他设备发现你的设备")
                    Text("• 点击发现的设备进行连接")
                }
                .font(.footnote)
                .foregroundColor(.secondary)
                .padding(.horizontal, 30)
                .padding(.bottom, 30)
            }
            .navigationTitle("")
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $showingDeviceList) {
            DeviceListView(bleManager: bleManager, showingChat: $showingChat)
        }
        .fullScreenCover(isPresented: $showingChat) {
            ChatView(bleManager: bleManager)
        }
        .onReceive(bleManager.$connectionState) { state in
            print("ContentView: Connection state changed to \(state), isAdvertising: \(bleManager.isAdvertising), showingDeviceList: \(showingDeviceList)")
            switch state {
            case .ready:
                // Always show chat when ready
                print("ContentView: Transitioning to chat (ready state)")
                showingDeviceList = false
                showingChat = true
            case .connected:
                // If we were advertising (not scanning), transition to chat on connection
                if !showingDeviceList {
                    print("ContentView: Transitioning to chat (connected while advertising)")
                    showingChat = true
                }
            case .disconnected:
                print("ContentView: Hiding chat (disconnected)")
                showingChat = false
                showingDeviceList = false
            default:
                break
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
        case .advertising:
            return .purple
        case .error:
            return .red
        case .disconnected:
            return .gray
        }
    }
    
    private var connectionStateText: String {
        switch bleManager.connectionState {
        case .disconnected:
            return "未连接"
        case .scanning:
            return "扫描中"
        case .advertising:
            return "广播中"
        case .connecting:
            return "连接中"
        case .connected:
            return "已连接"
        case .ready:
            return "就绪"
        case .error:
            return "错误"
        }
    }
}

#Preview {
    ContentView()
}
