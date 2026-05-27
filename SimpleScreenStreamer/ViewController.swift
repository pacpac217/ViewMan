import UIKit
import ReplayKit
import CoreMedia
import WebRTC
import AVFoundation

class ViewController: UIViewController {

    private var webRTCClient: WebRTCClient?
    private var isStreaming = false
    
    // UI Elements
    private let backgroundGradient = CAGradientLayer()
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "View Màn Hình"
        label.textColor = .white
        label.font = UIFont.systemFont(ofSize: 28, weight: .bold)
        label.textAlignment = .center
        return label
    }()
    
    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.text = "Truyền phát trực tiếp lên trình duyệt Chrome"
        label.textColor = UIColor.white.withAlphaComponent(0.6)
        label.font = UIFont.systemFont(ofSize: 14, weight: .regular)
        label.textAlignment = .center
        return label
    }()
    
    private let roomCodeTextField: UITextField = {
        let tf = UITextField()
        tf.placeholder = "Nhập mã phòng (ví dụ: 123456)"
        tf.textColor = .white
        tf.backgroundColor = UIColor.white.withAlphaComponent(0.1)
        tf.borderStyle = .none
        tf.layer.cornerRadius = 12
        tf.layer.borderWidth = 1
        tf.layer.borderColor = UIColor.white.withAlphaComponent(0.2).cgColor
        tf.textAlignment = .center
        tf.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        tf.keyboardType = .numberPad
        
        // Add padding
        let padding = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        tf.leftView = padding
        tf.leftViewMode = .always
        
        // Placeholder color
        tf.attributedPlaceholder = NSAttributedString(
            string: "Mã kết nối (6 số)",
            attributes: [NSAttributedString.Key.foregroundColor: UIColor.white.withAlphaComponent(0.4)]
        )
        return tf
    }()
    
    private let startButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle("Bắt Đầu Truyền Phát", for: .normal)
        btn.setTitleColor(.white, for: .normal)
        btn.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .bold)
        btn.backgroundColor = UIColor(red: 35/255.0, green: 158/255.0, blue: 171/255.0, alpha: 1.0)
        btn.layer.cornerRadius = 14
        btn.layer.shadowColor = UIColor(red: 35/255.0, green: 158/255.0, blue: 171/255.0, alpha: 0.4).cgColor
        btn.layer.shadowOpacity = 0.8
        btn.layer.shadowOffset = CGSize(width: 0, height: 4)
        btn.layer.shadowRadius = 8
        return btn
    }()
    
    private let logTextView: UITextView = {
        let tv = UITextView()
        tv.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        tv.textColor = UIColor(red: 128/255.0, green: 226/255.0, blue: 128/255.0, alpha: 1.0) // Matrix Green
        tv.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        tv.layer.cornerRadius = 12
        tv.layer.borderWidth = 1
        tv.layer.borderColor = UIColor.white.withAlphaComponent(0.1).cgColor
        tv.isEditable = false
        return tv
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        setupBackground()
        setupUI()
        
        // Generate a random room code by default
        let randomCode = String(format: "%06d", Int.random(in: 0...999999))
        roomCodeTextField.text = randomCode
        
        self.webRTCClient = WebRTCClient()
        self.webRTCClient?.onLog = { [weak self] message in
            DispatchQueue.main.async {
                self?.log(message)
            }
        }
        
        startButton.addTarget(self, action: #selector(startBtnTapped), for: .touchUpInside)
        
        // Dismiss keyboard when tapping outside
        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        self.view.addGestureRecognizer(tap)
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        backgroundGradient.frame = view.bounds
    }
    
    private func setupBackground() {
        backgroundGradient.colors = [
            UIColor(red: 15/255.0, green: 20/255.0, blue: 35/255.0, alpha: 1.0).cgColor, // Dark Blue
            UIColor(red: 25/255.0, green: 30/255.0, blue: 50/255.0, alpha: 1.0).cgColor
        ]
        backgroundGradient.locations = [0.0, 1.0]
        view.layer.insertSublayer(backgroundGradient, at: 0)
    }
    
    private func setupUI() {
        view.addSubview(titleLabel)
        view.addSubview(subtitleLabel)
        view.addSubview(roomCodeTextField)
        view.addSubview(startButton)
        view.addSubview(logTextView)
        
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        roomCodeTextField.translatesAutoresizingMaskIntoConstraints = false
        startButton.translatesAutoresizingMaskIntoConstraints = false
        logTextView.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 40),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            subtitleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            subtitleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            roomCodeTextField.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 40),
            roomCodeTextField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 30),
            roomCodeTextField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -30),
            roomCodeTextField.heightAnchor.constraint(equalToConstant: 50),
            
            startButton.topAnchor.constraint(equalTo: roomCodeTextField.bottomAnchor, constant: 24),
            startButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 30),
            startButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -30),
            startButton.heightAnchor.constraint(equalToConstant: 55),
            
            logTextView.topAnchor.constraint(equalTo: startButton.bottomAnchor, constant: 30),
            logTextView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            logTextView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            logTextView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20)
        ])
        
        log("Chào mừng bạn đến với View Màn Hình!")
        log("Nhập mã phòng và bấm Bắt đầu truyền phát.")
    }
    
    private func log(_ text: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let timestamp = formatter.string(from: Date())
        
        let newLog = "[\(timestamp)] \(text)\n"
        logTextView.text += newLog
        
        // Scroll to bottom
        let range = NSRange(location: logTextView.text.count - 1, length: 1)
        logTextView.scrollRangeToVisible(range)
    }
    
    @objc private func startBtnTapped() {
        self.view.endEditing(true)
        
        if isStreaming {
            stopStreaming()
        } else {
            startStreaming()
        }
    }
    
    @objc private func dismissKeyboard() {
        self.view.endEditing(true)
    }
    
    private func startStreaming() {
        guard let code = roomCodeTextField.text, !code.isEmpty else {
            log("Lỗi: Vui lòng nhập mã phòng!")
            return
        }
        
        self.isStreaming = true
        self.startButton.setTitle("Dừng Truyền Phát", for: .normal)
        self.startButton.backgroundColor = .systemRed
        self.startButton.layer.shadowColor = UIColor.systemRed.cgColor
        self.roomCodeTextField.isEnabled = false
        
        log("Khởi chạy dịch vụ truyền phát...")
        
        // Start WebRTC connection
        self.webRTCClient?.start(roomCode: code)
        
        // Start ReplayKit Screen Capture
        log("Đang kích hoạt ReplayKit...")
        RPScreenRecorder.shared().startCapture(handler: { [weak self] (sampleBuffer, sampleBufferType, error) in
            guard let self = self, error == nil else { return }
            if sampleBufferType == .video {
                if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                    self.webRTCClient?.sendFrame(pixelBuffer)
                }
            }
        }, completionHandler: { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.log("Lỗi ReplayKit: \(error.localizedDescription)")
                    self?.stopStreaming()
                } else {
                    self?.log("ReplayKit đang chụp màn hình ứng dụng!")
                }
            }
        })
    }
    
    private func stopStreaming() {
        self.isStreaming = false
        self.startButton.setTitle("Bắt Đầu Truyền Phát", for: .normal)
        self.startButton.backgroundColor = UIColor(red: 35/255.0, green: 158/255.0, blue: 171/255.0, alpha: 1.0)
        self.startButton.layer.shadowColor = UIColor(red: 35/255.0, green: 158/255.0, blue: 171/255.0, alpha: 0.4).cgColor
        self.roomCodeTextField.isEnabled = true
        
        log("Đang dừng ReplayKit...")
        RPScreenRecorder.shared().stopCapture { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.log("Lỗi khi dừng ReplayKit: \(error.localizedDescription)")
                }
                self?.webRTCClient?.stop()
            }
        }
    }
}
