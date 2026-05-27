import Foundation
import WebRTC

class WebRTCClient: NSObject, RTCPeerConnectionDelegate {
    
    private static let factory: RTCPeerConnectionFactory = {
        RTCInitializeSSL()
        let videoEncoderFactory = RTCDefaultVideoEncoderFactory()
        let videoDecoderFactory = RTCDefaultVideoDecoderFactory()
        return RTCPeerConnectionFactory(encoderFactory: videoEncoderFactory, decoderFactory: videoDecoderFactory)
    }()
    
    private var peerConnection: RTCPeerConnection?
    private var videoSource: RTCVideoSource?
    private var videoTrack: RTCVideoTrack?
    private var videoCapturer: RTCCameraVideoCapturer?
    
    var roomCode: String = ""
    var onConnectionStateChange: ((RTCIceConnectionState) -> Void)?
    var onLog: ((String) -> Void)?
    
    private var signalingTimer: Timer?
    private var seenMessageIds = Set<String>()
    
    override init() {
        super.init()
        self.videoSource = Self.factory.videoSource()
        self.videoTrack = Self.factory.videoTrack(with: self.videoSource!, trackId: "video0")
        self.videoCapturer = RTCCameraVideoCapturer(delegate: self.videoSource!)
    }
    
    func start(roomCode: String) {
        self.roomCode = roomCode
        self.seenMessageIds.removeAll()
        
        let config = RTCConfiguration()
        let iceServer = RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"])
        config.iceServers = [iceServer]
        config.sdpSemantics = .unifiedPlan
        
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        
        self.peerConnection = Self.factory.peerConnection(with: config, constraints: constraints, delegate: self)
        
        // Add video track
        if let videoTrack = self.videoTrack {
            self.peerConnection?.add(videoTrack, streamIds: ["stream0"])
        }
        
        self.onLog?("Đang tạo SDP Offer...")
        
        // Create offer
        let offerConstraints = RTCMediaConstraints(mandatoryConstraints: [
            kRTCMediaConstraintsOfferToReceiveVideo: kRTCMediaConstraintsValueFalse,
            kRTCMediaConstraintsOfferToReceiveAudio: kRTCMediaConstraintsValueFalse
        ], optionalConstraints: nil)
        
        self.peerConnection?.offer(for: offerConstraints, completionHandler: { [weak self] (sdp, error) in
            guard let self = self, let sdp = sdp else {
                self?.onLog?("Lỗi tạo Offer: \(error?.localizedDescription ?? "Unknown")")
                return
            }
            
            self.peerConnection?.setLocalDescription(sdp, completionHandler: { [weak self] (error) in
                guard let self = self else { return }
                if let error = error {
                    self.onLog?("Lỗi setLocalDescription: \(error.localizedDescription)")
                    return
                }
                
                self.onLog?("Đã lưu local SDP. Đang gửi lên ntfy.sh...")
                self.sendSignalingMessage(type: "offer", data: sdp.sdpDescription)
                self.startListeningForSignaling()
            })
        })
    }
    
    func stop() {
        self.signalingTimer?.invalidate()
        self.signalingTimer = nil
        self.peerConnection?.close()
        self.peerConnection = nil
        self.onLog?("Đã ngắt kết nối.")
    }
    
    func sendFrame(_ pixelBuffer: CVPixelBuffer) {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let timeStampNs = Int64(Date().timeIntervalSince1970 * 1_000_000_000)
        
        let rtcPixelBuffer = RTCCVPixelBuffer(pixelBuffer: pixelBuffer)
        let rtcFrame = RTCVideoFrame(buffer: rtcPixelBuffer, rotation: ._0, timeStampNs: timeStampNs)
        
        self.videoSource?.adaptOutputFormat(toWidth: Int32(width), height: Int32(height), fps: 30)
        if let capturer = self.videoCapturer, let delegate = self.videoSource as? RTCVideoCapturerDelegate {
            delegate.capturer(capturer, didCapture: rtcFrame)
        }
    }
    
    // MARK: - Signaling via ntfy.sh
    
    private func sendSignalingMessage(type: String, data: String) {
        let topic = "viewman_iphone_\(self.roomCode)"
        guard let url = URL(string: "https://ntfy.sh/\(topic)") else { return }
        
        let payload: [String: String] = ["type": type, "data": data]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload) else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        URLSession.shared.dataTask(with: request) { [weak self] _, _, error in
            if let error = error {
                self?.onLog?("Lỗi gửi tín hiệu: \(error.localizedDescription)")
            }
        }.resume()
    }
    
    private func startListeningForSignaling() {
        self.signalingTimer?.invalidate()
        
        let topic = "viewman_pc_\(self.roomCode)"
        guard let url = URL(string: "https://ntfy.sh/\(topic)/json") else { return }
        
        self.onLog?("Đang đợi Chrome kết nối (Mã phòng: \(self.roomCode))...")
        
        self.signalingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
                guard let self = self, let data = data, error == nil else { return }
                
                // ntfy /json endpoint returns newline-delimited JSON messages.
                let responseString = String(data: data, encoding: .utf8) ?? ""
                let lines = responseString.components(separatedBy: "\n")
                
                for line in lines {
                    if line.isEmpty { continue }
                    guard let lineData = line.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                          let id = json["id"] as? String,
                          !self.seenMessageIds.contains(id) else {
                        continue
                    }
                    
                    self.seenMessageIds.insert(id)
                    
                    if let messageText = json["message"] as? String,
                       let messageData = messageText.data(using: .utf8),
                       let msgJson = try? JSONSerialization.jsonObject(with: messageData) as? [String: String],
                       let type = msgJson["type"],
                       let dataStr = msgJson["data"] {
                        
                        DispatchQueue.main.async {
                            self.handleRemoteSignaling(type: type, data: dataStr)
                        }
                    }
                }
            }.resume()
        }
    }
    
    private func handleRemoteSignaling(type: String, data: String) {
        guard let peerConnection = self.peerConnection else { return }
        
        if type == "answer" {
            self.onLog?("Đã nhận SDP Answer từ Chrome. Đang thiết lập kết nối...")
            let sdp = RTCSessionDescription(type: .answer, sdp: data)
            peerConnection.setRemoteDescription(sdp, completionHandler: { [weak self] error in
                if let error = error {
                    self?.onLog?("Lỗi setRemoteDescription: \(error.localizedDescription)")
                } else {
                    self?.onLog?("Đã kết nối thành công SDP!")
                }
            })
        } else if type == "candidate" {
            guard let candidateData = data.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: candidateData) as? [String: Any],
                  let sdpMid = json["sdpMid"] as? String,
                  let sdpMLineIndex = json["sdpMLineIndex"] as? Int32,
                  let sdp = json["candidate"] as? String else {
                return
            }
            
            let candidate = RTCIceCandidate(sdp: sdp, sdpMLineIndex: sdpMLineIndex, sdpMid: sdpMid)
            peerConnection.add(candidate) { [weak self] error in
                if let error = error {
                    self?.onLog?("Lỗi addIceCandidate: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // MARK: - RTCPeerConnectionDelegate
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        self.onLog?("Đã thêm stream.")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    
    func peerConnectionShouldTriggerIceRestart(_ peerConnection: RTCPeerConnection) -> Bool { return true }
    
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        DispatchQueue.main.async {
            self.onLog?("Trạng thái ICE: \(newState.rawValue)")
            self.onConnectionStateChange?(newState)
            switch newState {
            case .connected, .completed:
                self.onLog?("Đã kết nối trực tiếp P2P với Chrome!")
            case .disconnected, .failed:
                self.onLog?("Đã ngắt kết nối.")
            default:
                break
            }
        }
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        let payload: [String: Any] = [
            "candidate": candidate.sdp,
            "sdpMid": candidate.sdpMid ?? "",
            "sdpMLineIndex": candidate.sdpMLineIndex
        ]
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: payload),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            self.sendSignalingMessage(type: "candidate", data: jsonString)
        }
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
}
