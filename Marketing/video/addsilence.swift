// Adds a silent stereo AAC track (48 kHz) to a video, as App Store Connect's
// app preview spec expects one. The video stream is copied untouched.
//
//   swiftc -O -o /tmp/tidy-silence Marketing/video/addsilence.swift && /tmp/tidy-silence in.mp4 out.mp4
import AVFoundation

let input = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
let silence = FileManager.default.temporaryDirectory.appendingPathComponent("tidy-silence.m4a")

func makeSilence(seconds: Double) throws {
    try? FileManager.default.removeItem(at: silence)
    let writer = try AVAssetWriter(outputURL: silence, fileType: .m4a)
    let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: [
        AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 256_000,
    ])
    writer.add(audio)
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)
    var asbd = AudioStreamBasicDescription(mSampleRate: 48_000, mFormatID: kAudioFormatLinearPCM,
                                           mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
                                           mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4, mChannelsPerFrame: 2,
                                           mBitsPerChannel: 16, mReserved: 0)
    var format: CMAudioFormatDescription?
    CMAudioFormatDescriptionCreate(allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format)
    let chunk = 4800, total = Int(seconds * 48_000)
    var written = 0
    while written < total {
        let frames = min(chunk, total - written)
        var block: CMBlockBuffer?
        CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: frames * 4, blockAllocator: nil, customBlockSource: nil,
                                           offsetToData: 0, dataLength: frames * 4, flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block)
        CMBlockBufferFillDataBytes(with: 0, blockBuffer: block!, offsetIntoDestination: 0, dataLength: frames * 4)
        var sample: CMSampleBuffer?
        CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: nil, dataBuffer: block!, formatDescription: format!, sampleCount: frames,
                                                             presentationTimeStamp: CMTime(value: CMTimeValue(written), timescale: 48_000),
                                                             packetDescriptions: nil, sampleBufferOut: &sample)
        while !audio.isReadyForMoreMediaData { usleep(1000) }
        audio.append(sample!)
        written += frames
    }
    audio.markAsFinished()
    let done = DispatchSemaphore(value: 0)
    writer.finishWriting { done.signal() }
    done.wait()
}

let sem = DispatchSemaphore(value: 0)
Task {
    let videoAsset = AVURLAsset(url: input)
    let duration = try await videoAsset.load(.duration)
    try makeSilence(seconds: duration.seconds + 0.2)
    let audioAsset = AVURLAsset(url: silence)
    let comp = AVMutableComposition()
    let range = CMTimeRange(start: .zero, duration: duration)
    let vTrack = try await videoAsset.loadTracks(withMediaType: .video).first!
    let aTrack = try await audioAsset.loadTracks(withMediaType: .audio).first!
    try comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!.insertTimeRange(range, of: vTrack, at: .zero)
    try comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!.insertTimeRange(range, of: aTrack, at: .zero)
    try? FileManager.default.removeItem(at: output)
    let export = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetPassthrough)!
    try await export.export(to: output, as: .mp4)
    print("wrote \(output.path)")
    sem.signal()
}
sem.wait()
