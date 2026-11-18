import Accelerate
import Foundation

/// Turns the latest audio samples into bar heights 0...1 for the keyboard's music page.
/// Log-spaced bands, a gentle treble lift (music has less energy up high), automatic gain
/// that follows the loudness, fast rise and slower fall so the bars look smooth.
public final class MusicAnalyzer {
    public let bandCount: Int
    public let sampleRate: Double
    public let fftSize = 2048
    /// 0...1. Higher makes quiet parts taller.
    public var sensitivity = 0.5

    /// RMS of the last frame. Below `silenceRMS` counts as silence.
    public private(set) var lastRMS: Float = 0
    public static let silenceRMS: Float = 0.0005
    /// Where the loudest band sits, 0...1.
    public static let headroom = 0.95

    private let log2n: vDSP_Length
    private let setup: FFTSetup
    private let window: [Float]
    private let edges: [Int]            // bandCount + 1 bin indices
    private let lift: [Double]          // dB added per band
    private var smoothed: [Double]
    private var reference = -60.0       // automatic gain: loudest recent band, in dB

    public init(bandCount: Int = 21, sampleRate: Double = 48_000, lowHz: Double = 40, highHz: Double = 16_000) {
        self.bandCount = bandCount
        self.sampleRate = sampleRate
        log2n = vDSP_Length(log2(Double(fftSize)))
        setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: fftSize, isHalfWindow: false)

        let binHz = sampleRate / Double(fftSize)
        let top = min(highHz, sampleRate / 2 * 0.95)
        var e = [Int]()
        for i in 0...bandCount {
            let f = lowHz * pow(top / lowHz, Double(i) / Double(bandCount))
            var bin = Int((f / binHz).rounded())
            if let last = e.last, bin <= last { bin = last + 1 }   // every band gets at least one bin
            e.append(min(bin, fftSize / 2))
        }
        edges = e
        lift = (0..<bandCount).map { i in
            let centre = lowHz * pow(top / lowHz, (Double(i) + 0.5) / Double(bandCount))
            return 3 * log2(centre / lowHz)                        // +3 dB per octave
        }
        smoothed = Array(repeating: 0, count: bandCount)
    }

    deinit { vDSP_destroy_fftsetup(setup) }

    /// Uses the last `fftSize` samples (zero-padded if fewer). Returns `bandCount` levels 0...1.
    public func process(_ samples: [Float]) -> [Double] {
        var frame = [Float](repeating: 0, count: fftSize)
        let tail = samples.suffix(fftSize)
        frame.replaceSubrange((fftSize - tail.count)..<fftSize, with: tail)
        lastRMS = vDSP.rootMeanSquare(frame)

        var targets = [Double](repeating: 0, count: bandCount)
        if lastRMS >= Self.silenceRMS {
            let power = spectrum(vDSP.multiply(frame, window))
            var db = [Double](repeating: -120, count: bandCount)
            for b in 0..<bandCount {
                let lo = edges[b], hi = max(edges[b] + 1, edges[b + 1])
                var sum: Float = 0
                for k in lo..<min(hi, power.count) { sum += power[k] }
                db[b] = 10 * log10(Double(sum) / Double(hi - lo) + 1e-12) + lift[b]
            }
            // Gain follows the loudest band: jumps up at once, relaxes about 3 dB per second at 60 frames/s.
            reference = max(db.max() ?? -60, reference - 0.05, -60)
            let range = 25 + 35 * min(1, max(0, sensitivity))      // dB shown from bottom to top
            // The loudest band sits just under the top, so only a real jump in loudness reaches full scale.
            for b in 0..<bandCount { targets[b] = min(1, max(0, Self.headroom + (db[b] - reference) / range)) }
        }
        for b in 0..<bandCount {
            let rate = targets[b] > smoothed[b] ? 0.7 : 0.22
            smoothed[b] += (targets[b] - smoothed[b]) * rate
            if smoothed[b] < 0.005 { smoothed[b] = 0 }
        }
        return smoothed
    }

    /// Power per bin 0..<fftSize/2.
    private func spectrum(_ x: [Float]) -> [Float] {
        let half = fftSize / 2
        var real = [Float](repeating: 0, count: half)
        var imag = [Float](repeating: 0, count: half)
        var power = [Float](repeating: 0, count: half)
        real.withUnsafeMutableBufferPointer { rp in
            imag.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                x.withUnsafeBufferPointer { xp in
                    xp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(half))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                split.imagp[0] = 0                                   // drop the packed Nyquist term
                vDSP_zvmags(&split, 1, &power, 1, vDSP_Length(half))
            }
        }
        return power
    }

    /// Resamples levels to another bar count (the cable takes 18, the dongle 21).
    public static func resample(_ levels: [Double], to count: Int) -> [Double] {
        guard levels.count > 1, count > 1 else { return Array(repeating: levels.first ?? 0, count: count) }
        return (0..<count).map { i in
            let x = Double(i) * Double(levels.count - 1) / Double(count - 1)
            let j = Int(x), t = x - Double(j)
            return j + 1 < levels.count ? levels[j] * (1 - t) + levels[j + 1] * t : levels[j]
        }
    }
}

/// A small ring of recent mono samples, written by the audio thread and read by the sender.
public final class SampleRing: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer: [Float]
    private var head = 0

    public init(capacity: Int = 8192) { buffer = Array(repeating: 0, count: capacity) }

    public func append(_ samples: UnsafeBufferPointer<Float>) {
        lock.lock(); defer { lock.unlock() }
        for s in samples {
            buffer[head] = s
            head = (head + 1) % buffer.count
        }
    }

    public func reset() {
        lock.lock(); defer { lock.unlock() }
        for i in buffer.indices { buffer[i] = 0 }
    }

    /// The newest `count` samples, oldest first.
    public func latest(_ count: Int) -> [Float] {
        lock.lock(); defer { lock.unlock() }
        let n = min(count, buffer.count)
        var out = [Float](repeating: 0, count: n)
        for i in 0..<n { out[i] = buffer[(head - n + i + buffer.count) % buffer.count] }
        return out
    }
}
