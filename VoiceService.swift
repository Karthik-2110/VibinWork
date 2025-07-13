import Foundation
import AgoraRtcKit

class VoiceService: NSObject, ObservableObject, AgoraRtcEngineDelegate {
    private var agoraEngine: AgoraRtcEngineKit?
    @Published var isMuted: Bool = false

    override init() {
        super.init()
        initializeAgoraEngine()
    }

    private func initializeAgoraEngine() {
        let config = AgoraRtcEngineConfig()
        config.appId = AgoraCredentials.appId
        agoraEngine = AgoraRtcEngineKit.sharedEngine(with: config, delegate: self)
    }

    func joinChannel(room: Room) {
        guard let engine = agoraEngine else { return }
        
        engine.enableAudio()
        engine.setChannelProfile(.communication)

        let option = AgoraRtcChannelMediaOptions()
        option.clientRoleType = .broadcaster
        option.channelProfile = .communication

        let result = engine.joinChannel(
            byToken: nil, // Use nil for testing, generate a token for production
            channelId: room.id,
            uid: 0, // 0 lets Agora assign a UID
            mediaOptions: option
        )
        
        if result == 0 {
            print("[Agora] Joined channel successfully")
        } else {
            print("[Agora] Failed to join channel, error code: \(result)")
        }
    }

    func leaveChannel() {
        agoraEngine?.leaveChannel(nil)
        print("[Agora] Left channel")
    }
    
    func toggleMute() {
        isMuted.toggle()
        agoraEngine?.muteLocalAudioStream(isMuted)
    }
    
    // MARK: - AgoraRtcEngineDelegate
    
    func rtcEngine(_ engine: AgoraRtcEngineKit, didOccurError errorCode: AgoraErrorCode) {
        print("[Agora] Error: \(errorCode.rawValue)")
    }
    
    func rtcEngine(_ engine: AgoraRtcEngineKit, didJoinChannel channel: String, withUid uid: UInt, elapsed: Int) {
        print("[Agora] Joined channel \(channel) with uid \(uid)")
    }
    
    func rtcEngine(_ engine: AgoraRtcEngineKit, didJoinedOfUid uid: UInt, elapsed: Int) {
        print("[Agora] Remote user joined with uid \(uid)")
    }
    
    func rtcEngine(_ engine: AgoraRtcEngineKit, didLeaveChannelWith stats: AgoraChannelStats) {
        print("[Agora] Left channel with stats")
    }
} 