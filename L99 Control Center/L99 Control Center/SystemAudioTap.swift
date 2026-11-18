import AudioToolbox
import CoreAudio
import Foundation
import L99Core

/// Listens to everything the Mac plays, through a Core Audio process tap (macOS 14.2+).
/// macOS asks once for "System Audio Recording" permission. Audio stays in memory: a few
/// thousand recent samples in `ring`, never saved or sent anywhere. Only the bar heights leave the Mac's memory.
nonisolated final class SystemAudioTap: @unchecked Sendable {
    let ring = SampleRing(capacity: 8192)
    private(set) var sampleRate: Double = 48_000
    private(set) var isRunning = false

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "L99 audio tap", qos: .userInteractive)

    func start() throws {
        guard !isRunning else { return }
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.uuid = UUID()
        description.name = "L99 Control Center music bars"
        description.isPrivate = true
        description.muteBehavior = .unmuted

        var tap = AudioObjectID(kAudioObjectUnknown)
        try check(AudioHardwareCreateProcessTap(description, &tap), "create the audio tap")
        tapID = tap

        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        if AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &format) == noErr, format.mSampleRate > 0 {
            sampleRate = format.mSampleRate
        }

        var aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "L99 Control Center tap",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString,
                                               kAudioSubTapDriftCompensationKey: true]],
        ]
        if let output = Self.defaultOutputUID() {
            aggregate[kAudioAggregateDeviceMainSubDeviceKey] = output
            aggregate[kAudioAggregateDeviceSubDeviceListKey] = [[kAudioSubDeviceUIDKey: output]]
        }
        var device = AudioObjectID(kAudioObjectUnknown)
        do {
            try check(AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &device), "create the listening device")
        } catch { stop(); throw error }
        aggregateID = device

        let ring = self.ring
        var proc: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(&proc, device, queue) { _, input, _, _, _ in
            let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
            guard let first = buffers.first, let data = first.mData else { return }
            let channels = max(1, Int(first.mNumberChannels))
            let frames = Int(first.mDataByteSize) / MemoryLayout<Float>.size / channels
            guard frames > 0 else { return }
            let samples = data.assumingMemoryBound(to: Float.self)
            if channels == 1 {
                ring.append(UnsafeBufferPointer(start: samples, count: frames))
            } else {
                var mono = [Float](repeating: 0, count: frames)
                for f in 0..<frames {
                    var sum: Float = 0
                    for c in 0..<channels { sum += samples[f * channels + c] }
                    mono[f] = sum / Float(channels)
                }
                mono.withUnsafeBufferPointer { ring.append($0) }
            }
        }
        do {
            try check(status, "listen to the Mac's sound")
            procID = proc
            try check(AudioDeviceStart(device, proc), "start listening")
        } catch { stop(); throw error }
        isRunning = true
    }

    func stop() {
        if aggregateID != kAudioObjectUnknown {
            if let procID {
                AudioDeviceStop(aggregateID, procID)
                AudioDeviceDestroyIOProcID(aggregateID, procID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        procID = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
        isRunning = false
        ring.reset()
    }

    private static func defaultOutputUID() -> String? {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr else { return nil }
        var uid: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        address.mSelector = kAudioDevicePropertyDeviceUID
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &uid) == noErr, let uid else { return nil }
        return uid.takeRetainedValue() as String
    }

    private func check(_ status: OSStatus, _ what: String) throws {
        guard status == noErr else { throw LinkErrorText("Couldn't \(what) (Core Audio error \(status)).") }
    }
}

struct LinkErrorText: Error, LocalizedError {
    let text: String
    init(_ text: String) { self.text = text }
    var errorDescription: String? { text }
}
