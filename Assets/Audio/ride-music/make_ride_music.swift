// Writes the ride's music (Sources/Macrowavers/Resources/MusicRide.caf) from "Persian" by Echobrainz (Pixabay,
// Assets/Audio/music_ride_persian.mp3, 1:47): 7 of its 9.6 s phrases (67.2 s at 100 BPM), from 22.44 s, past the
// intro, to 89.64 s, before the ending. It loops seamlessly: the music after the end crossfades into the start over
// one beat. The two points are where the track sounds most alike around them (the energy in 16 frequency bands for
// 3 s on either side), a whole number of phrases apart; the end is then aligned on the start's waveform within 20 ms.
//
// usage: swift Assets/Audio/ride-music/make_ride_music.swift Assets/Audio/music_ride_persian.mp3 \
//            Sources/Macrowavers/Resources/MusicRide.caf
// (Apple Lossless: AAC would add a silent gap at the loop point.)
import AVFoundation

let loopStart = 22.442
let loopEnd = 89.641
let crossfade = 0.6
let alignment = 0.02

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    print("usage: swift make_ride_music.swift <music_ride_persian.mp3> <MusicRide.caf>")
    exit(1)
}
let source = try AVAudioFile(forReading: URL(fileURLWithPath: arguments[1]))
let format = source.processingFormat
guard let track = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(source.length)),
      let samples = track.floatChannelData else { exit(1) }
try source.read(into: track)
let rate = format.sampleRate
let channels = (0..<Int(format.channelCount)).map { samples[$0] }

/// Mono sample `index` of the track.
func mono(_ index: Int) -> Float {
    channels.reduce(0) { $0 + $1[index] } / Float(channels.count)
}

/// How alike the track is from `first` and from `second` over `count` samples (-1...1).
func correlation(_ first: Int, _ second: Int, count: Int) -> Float {
    var dot: Float = 0, firstPower: Float = 0, secondPower: Float = 0
    for offset in 0..<count {
        let one = mono(first + offset), other = mono(second + offset)
        dot += one * other
        firstPower += one * one
        secondPower += other * other
    }
    return dot / max(sqrt(firstPower * secondPower), 1e-9)
}

let start = Int(loopStart * rate)
let fade = Int(crossfade * rate)
let shifts = -Int(alignment * rate)...Int(alignment * rate)
let end = shifts.map { Int(loopEnd * rate) + $0 }.max {
    correlation(start, $0, count: fade) < correlation(start, $1, count: fade)
} ?? Int(loopEnd * rate)
let alike = correlation(start, end, count: fade)

// The loop: the track from its start to its end, its first beat a crossfade from the music after the end (where the
// last sample left off) to the start's. Equal power, corrected for how alike the two are.
let length = end - start
guard let loop = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(length)),
      let output = loop.floatChannelData else { exit(1) }
loop.frameLength = AVAudioFrameCount(length)
var peak: Float = 0
for (channel, input) in channels.enumerated() {
    for index in 0..<length {
        var value = input[start + index]
        if index < fade {
            let progress = Float(index) / Float(fade) * .pi / 2
            let incoming = sin(progress), outgoing = cos(progress)
            let power = sqrt(1 + 2 * incoming * outgoing * alike)
            value = (value * incoming + input[end + index] * outgoing) / power
        }
        output[channel][index] = value
        peak = max(peak, abs(value))
    }
}
// Never clipped.
if peak > 0.98 {
    for channel in channels.indices {
        for index in 0..<length { output[channel][index] *= 0.98 / peak }
    }
}

let settings: [String: Any] = [AVFormatIDKey: kAudioFormatAppleLossless, AVSampleRateKey: rate,
                               AVNumberOfChannelsKey: format.channelCount, AVEncoderBitDepthHintKey: 16]
let destination = URL(fileURLWithPath: arguments[2])
try? FileManager.default.removeItem(at: destination)
let file = try AVAudioFile(forWriting: destination, settings: settings, commonFormat: .pcmFormatFloat32,
                           interleaved: false)
try file.write(from: loop)
// Its header written before the script ends.
file.close()
print(String(format: "%.3f s loop, end moved %+.1f ms, the two sides %.2f alike, peak %.2f", Double(length) / rate,
             Double(end - Int(loopEnd * rate)) / rate * 1000, alike, peak))
