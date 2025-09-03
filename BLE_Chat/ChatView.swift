//
//  ChatView.swift
//  BLE_Chat
//
//  Created by BLE Chat Team on 2025/9/2.
//

import SwiftUI
import PhotosUI
import AVFoundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct ChatView: View {
    @ObservedObject var bleManager: BLEChatManager
    @Environment(\.dismiss) private var dismiss
    @State private var messageText = ""
    @State private var showingImagePicker = false
    @State private var showingCamera = false
    @State private var showingVideoPicker = false
    #if canImport(UIKit)
    @State private var selectedImage: UIImage?
    #elseif canImport(AppKit)
    @State private var selectedImage: NSImage?
    #endif
    @State private var selectedVideoURL: URL?
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Chat Header
                chatHeader
                
                // Messages List
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(Array(bleManager.receivedMessages.enumerated()), id: \.offset) { index, message in
                                MessageBubble(message: message)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: bleManager.receivedMessages.count) { _ in
                        if let lastMessage = bleManager.receivedMessages.last {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                }
                
                // Message Input Area
                messageInputArea
            }
            .navigationTitle("")
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(selectedImage: $selectedImage)
        }
        .sheet(isPresented: $showingCamera) {
            CameraView(selectedImage: $selectedImage)
        }
        .sheet(isPresented: $showingVideoPicker) {
            VideoPicker(selectedVideoURL: $selectedVideoURL)
        }
        .alert("错误", isPresented: $showingAlert) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
        .onChange(of: selectedImage) { image in
            if let image = image {
                sendImage(image)
                selectedImage = nil
            }
        }
        .onChange(of: selectedVideoURL) { url in
            if let url = url {
                sendVideo(url)
                selectedVideoURL = nil
            }
        }
        .onAppear {
            setupErrorHandling()
        }
    }
    
    private var chatHeader: some View {
        HStack {
            // Back Button
            Button(action: {
                bleManager.disconnect()
                dismiss()
            }) {
                HStack {
                    Image(systemName: "chevron.left")
                        .font(.title2)
                    Text("返回")
                        .font(.headline)
                }
                .foregroundColor(.blue)
            }
            
            Spacer()
            
            // Connection Info
            VStack {
                Text(bleManager.connectedDevice?.name ?? "未知设备")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                HStack {
                    Circle()
                        .fill(connectionStateColor)
                        .frame(width: 8, height: 8)
                    
                    Text(connectionStateText)
                        .font(.caption)
                        .foregroundColor(connectionStateColor)
                }
            }
            
            Spacer()
            
            // Settings Button
            Button(action: {
                // TODO: Add settings
            }) {
                Image(systemName: "ellipsis.circle")
                    .font(.title2)
                    .foregroundColor(.blue)
            }
        }
        .padding()
        .background(Color(UIColor.systemGray6))
        .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 1)
    }
    
    private var messageInputArea: some View {
        VStack(spacing: 0) {
            Divider()
            
            HStack(spacing: 12) {
                // Media Buttons
                HStack(spacing: 8) {
                    // Camera Button
                    Button(action: {
                        showingCamera = true
                    }) {
                        Image(systemName: "camera.fill")
                            .font(.title2)
                            .foregroundColor(.blue)
                    }
                    
                    // Photo Library Button
                    Button(action: {
                        showingImagePicker = true
                    }) {
                        Image(systemName: "photo.fill")
                            .font(.title2)
                            .foregroundColor(.green)
                    }
                    
                    // Video Button
                    Button(action: {
                        showingVideoPicker = true
                    }) {
                        Image(systemName: "video.fill")
                            .font(.title2)
                            .foregroundColor(.purple)
                    }
                }
                
                // Text Input
                HStack {
                    TextField("输入消息...", text: $messageText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...4)
                    
                    if !messageText.isEmpty {
                        Button("发送") {
                            sendMessage()
                        }
                        .foregroundColor(.blue)
                        .fontWeight(.semibold)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(UIColor.systemGray5))
                .cornerRadius(20)
            }
            .padding()
        }
        .background(Color(UIColor.systemBackground))
    }
    
    private var connectionStateColor: Color {
        switch bleManager.connectionState {
        case .ready:
            return .green
        case .connected:
            return .orange
        case .error:
            return .red
        default:
            return .gray
        }
    }
    
    private var connectionStateText: String {
        switch bleManager.connectionState {
        case .ready:
            return "已连接"
        case .connected:
            return "连接中"
        case .error:
            return "连接错误"
        default:
            return "未连接"
        }
    }
    
    private func sendMessage() {
        guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        bleManager.sendMessage(messageText.trimmingCharacters(in: .whitespacesAndNewlines))
        messageText = ""
    }
    
    private func sendImage(_ image: UIImage) {
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            showError("无法处理图片")
            return
        }
        
        // Compress if too large (limit to 1MB for BLE transmission)
        let maxSize = 1024 * 1024 // 1MB
        let finalData: Data
        
        if imageData.count > maxSize {
            if let compressedData = image.jpegData(compressionQuality: 0.3) {
                finalData = compressedData
            } else {
                showError("图片压缩失败")
                return
            }
        } else {
            finalData = imageData
        }
        
        bleManager.sendImage(finalData)
    }
    
    private func sendVideo(_ url: URL) {
        do {
            let videoData = try Data(contentsOf: url)
            
            // Check size limit (5MB for video)
            let maxSize = 5 * 1024 * 1024 // 5MB
            if videoData.count > maxSize {
                showError("视频文件过大，请选择小于5MB的视频")
                return
            }
            
            bleManager.sendVideo(videoData)
        } catch {
            showError("无法读取视频文件")
        }
    }
    
    private func setupErrorHandling() {
        bleManager.onError = { error in
            DispatchQueue.main.async {
                self.showError(error.localizedDescription)
            }
        }
    }
    
    private func showError(_ message: String) {
        alertMessage = message
        showingAlert = true
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    
    var body: some View {
        HStack {
            if message.isFromCurrentUser {
                Spacer()
            }
            
            VStack(alignment: message.isFromCurrentUser ? .trailing : .leading, spacing: 4) {
                // Message Content
                switch message.type {
                case .text:
                    Text(message.content)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(messageBackgroundColor)
                        .foregroundColor(messageTextColor)
                        .cornerRadius(18)
                
                case .image:
                    if let imageData = message.imageData, let uiImage = UIImage(data: imageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 200, maxHeight: 200)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                    } else {
                        Text("图片")
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(messageBackgroundColor)
                            .foregroundColor(messageTextColor)
                            .cornerRadius(18)
                    }
                
                case .video:
                    HStack {
                        Image(systemName: "play.circle.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                        
                        Text("视频")
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.purple)
                    .cornerRadius(18)
                
                default:
                    Text(message.content)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(messageBackgroundColor)
                        .foregroundColor(messageTextColor)
                        .cornerRadius(18)
                }
                
                // Timestamp
                Text(formatTimestamp(message.timestamp))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: 250, alignment: message.isFromCurrentUser ? .trailing : .leading)
            
            if !message.isFromCurrentUser {
                Spacer()
            }
        }
    }
    
    private var messageBackgroundColor: Color {
        message.isFromCurrentUser ? .blue : Color(UIColor.systemGray5)
    }
    
    private var messageTextColor: Color {
        message.isFromCurrentUser ? .white : .primary
    }
    
    private func formatTimestamp(_ timestamp: UInt64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000.0)  // Convert milliseconds to seconds
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Supporting Views
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            if let result = results.first {
                result.itemProvider.loadObject(ofClass: UIImage.self) { object, error in
                    if let image = object as? UIImage {
                        DispatchQueue.main.async {
                            self.parent.selectedImage = image
                        }
                    }
                }
            }
            parent.dismiss()
        }
    }
}

struct CameraView: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraView
        
        init(_ parent: CameraView) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.selectedImage = image
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

struct VideoPicker: UIViewControllerRepresentable {
    @Binding var selectedVideoURL: URL?
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.mediaTypes = ["public.movie"]
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: VideoPicker
        
        init(_ parent: VideoPicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let url = info[.mediaURL] as? URL {
                parent.selectedVideoURL = url
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

struct ChatView_Previews: PreviewProvider {
    static var previews: some View {
        ChatView(bleManager: BLEChatManager())
    }
}