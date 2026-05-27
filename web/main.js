let localPeerConnection = null;
let roomCode = "";
let eventSource = null;
let isConnected = false;

// DOM Elements
const roomInput = document.getElementById('room-input');
const connectBtn = document.getElementById('connect-btn');
const logTerminal = document.getElementById('log-terminal');
const connectionBadge = document.getElementById('connection-badge');
const remoteVideo = document.getElementById('remote-video');
const placeholder = document.getElementById('placeholder');
const videoWrapper = document.getElementById('video-wrapper');
const rotateBtn = document.getElementById('rotate-btn');
const fullscreenBtn = document.getElementById('fullscreen-btn');
const clearLogsBtn = document.getElementById('clear-logs');

// Initialize random room code on web launch
roomInput.value = String(Math.floor(100000 + Math.random() * 900000));

// Setup Logging
function log(message) {
    const now = new Date();
    const timeStr = now.toTimeString().split(' ')[0];
    
    const line = document.createElement('div');
    line.className = 'log-line';
    line.innerHTML = `<span class="log-time">[${timeStr}]</span> ${message}`;
    logTerminal.appendChild(line);
    
    // Auto scroll to bottom
    logTerminal.scrollTop = logTerminal.scrollHeight;
}

// Clear Logs
clearLogsBtn.addEventListener('click', () => {
    logTerminal.innerHTML = '';
    log("Đã xóa nhật ký.");
});

// UI Rotations
rotateBtn.addEventListener('click', () => {
    videoWrapper.classList.toggle('rotated');
    log("Đã xoay màn hình hiển thị.");
});

// Fullscreen mode
fullscreenBtn.addEventListener('click', () => {
    if (remoteVideo.requestFullscreen) {
        remoteVideo.requestFullscreen();
    } else if (remoteVideo.webkitRequestFullscreen) {
        remoteVideo.webkitRequestFullscreen();
    } else if (remoteVideo.msRequestFullscreen) {
        remoteVideo.msRequestFullscreen();
    }
});

// Button connection control
connectBtn.addEventListener('click', () => {
    if (isConnected) {
        disconnect();
    } else {
        connect();
    }
});

function connect() {
    roomCode = roomInput.value.trim();
    if (roomCode.length !== 6 || isNaN(roomCode)) {
        alert("Vui lòng nhập mã phòng gồm 6 số!");
        return;
    }
    
    isConnected = true;
    connectBtn.innerHTML = "Ngắt Kết Nối";
    connectBtn.className = "btn connected";
    connectionBadge.style.color = "var(--primary)";
    connectionBadge.innerHTML = `<span style="display:inline-block; width:8px; height:8px; border-radius:50%; background:currentColor; animation: pulse 1s infinite;"></span> Đang kết nối...`;
    
    log(`Bắt đầu kết nối. Mã kết nối: ${roomCode}`);
    
    // Initialize WebRTC peer connection
    initWebRTC();
}

function disconnect() {
    isConnected = false;
    connectBtn.innerHTML = "Kết Nối Với iPhone";
    connectBtn.className = "btn";
    connectionBadge.style.color = "var(--accent)";
    connectionBadge.innerHTML = `<span style="display:inline-block; width:8px; height:8px; border-radius:50%; background:currentColor;"></span> Đã ngắt kết nối`;
    
    if (eventSource) {
        eventSource.close();
        eventSource = null;
    }
    
    if (localPeerConnection) {
        localPeerConnection.close();
        localPeerConnection = null;
    }
    
    remoteVideo.srcObject = null;
    placeholder.style.display = "flex";
    log("Đã đóng kết nối VNC.");
}

function initWebRTC() {
    const config = {
        iceServers: [{ urls: "stun:stun.l.google.com:19302" }]
    };
    
    localPeerConnection = new RTCPeerConnection(config);
    
    // Handle remote stream video track addition
    localPeerConnection.ontrack = (event) => {
        log("Đã nhận được luồng video trực tiếp từ iPhone!");
        if (event.streams && event.streams[0]) {
            remoteVideo.srcObject = event.streams[0];
            placeholder.style.display = "none";
            
            connectionBadge.style.color = "#80e280";
            connectionBadge.innerHTML = `<span style="display:inline-block; width:8px; height:8px; border-radius:50%; background:currentColor;"></span> Đang phát màn hình`;
        }
    };
    
    // Handle local ICE candidates gathering
    localPeerConnection.onicecandidate = (event) => {
        if (event.candidate) {
            sendSignalingMessage("candidate", JSON.stringify(event.candidate));
        }
    };
    
    // Handle connection state changes
    localPeerConnection.onconnectionstatechange = () => {
        log(`Trạng thái WebRTC: ${localPeerConnection.connectionState}`);
        if (localPeerConnection.connectionState === 'disconnected' || localPeerConnection.connectionState === 'failed') {
            disconnect();
        }
    };
    
    // Start listening for signaling events from ntfy.sh (Server-Sent Events)
    const topic = `viewman_iphone_${roomCode}`;
    log(`Lắng nghe bắt tay tại ntfy.sh/${topic}...`);
    
    eventSource = new EventSource(`https://ntfy.sh/${topic}/sse`);
    
    eventSource.onmessage = (event) => {
        const payload = JSON.parse(event.data);
        // Only process standard publish events with message content
        if (payload.event === 'message' && payload.message) {
            try {
                const signal = JSON.parse(payload.message);
                handleRemoteSignaling(signal.type, signal.data);
            } catch (err) {
                // Ignore parsing errors of non-JSON messages
            }
        }
    };
    
    eventSource.onerror = () => {
        log("Lỗi máy chủ kết nối ntfy.sh. Đang thử kết nối lại...");
    };
}

async function handleRemoteSignaling(type, data) {
    if (!localPeerConnection) return;
    
    if (type === "offer") {
        log("Đã nhận SDP Offer từ iPhone. Đang cấu hình và tạo Answer...");
        
        try {
            await localPeerConnection.setRemoteDescription(new RTCSessionDescription({
                type: "offer",
                sdp: data
            }));
            
            const answer = await localPeerConnection.createAnswer();
            await localPeerConnection.setLocalDescription(answer);
            
            log("Đã tạo và thiết lập local SDP Answer thành công. Đang gửi tín hiệu phản hồi...");
            sendSignalingMessage("answer", answer.sdp);
            
        } catch (err) {
            log(`Lỗi thiết lập SDP Offer: ${err.message}`);
        }
        
    } else if (type === "candidate") {
        try {
            const candidateInfo = JSON.parse(data);
            await localPeerConnection.addIceCandidate(new RTCIceCandidate(candidateInfo));
        } catch (err) {
            // Ignore minor ICE candidate gathering race condition errors
        }
    }
}

// Send signal (Answer / ICE Candidate) to iPhone via ntfy.sh
function sendSignalingMessage(type, data) {
    const topic = `viewman_pc_${roomCode}`;
    const payload = JSON.stringify({ type: type, data: data });
    
    fetch(`https://ntfy.sh/${topic}`, {
        method: 'POST',
        body: payload,
        headers: {
            'Content-Type': 'application/json'
        }
    }).catch(err => {
        log(`Lỗi gửi gói tin bắt tay: ${err.message}`);
    });
}
