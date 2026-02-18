import Foundation

public enum ColorSpace: String, CaseIterable, Sendable, Codable {
    case p3D65PQ = "P3-D65-PQ"
    case rec2020PQ = "Rec2020-PQ"
    case rec709 = "Rec709"
    case none = "None"

    public var displayName: String {
        switch self {
        case .p3D65PQ: return "P3-D65 / PQ (HDR)"
        case .rec2020PQ: return "Rec.2020 / PQ (HDR)"
        case .rec709: return "Rec.709 (SDR)"
        case .none: return "None (don't tag)"
        }
    }

    /// ffmpeg flags for container-level color metadata. nil means skip tagging.
    public var ffmpegColorFlags: [String]? {
        switch self {
        case .p3D65PQ:
            return ["-color_primaries", "smpte432", "-color_trc", "smpte2084", "-colorspace", "bt2020nc"]
        case .rec2020PQ:
            return ["-color_primaries", "bt2020", "-color_trc", "smpte2084", "-colorspace", "bt2020nc"]
        case .rec709:
            return ["-color_primaries", "bt709", "-color_trc", "bt709", "-colorspace", "bt709"]
        case .none:
            return nil
        }
    }

    /// Expected ffprobe values for this color space. nil means always skip (no tagging needed).
    public var expectedProbeValues: (primaries: String, transfer: String, space: String)? {
        switch self {
        case .p3D65PQ:
            return ("smpte432", "smpte2084", "bt2020nc")
        case .rec2020PQ:
            return ("bt2020", "smpte2084", "bt2020nc")
        case .rec709:
            return ("bt709", "bt709", "bt709")
        case .none:
            return nil
        }
    }
}
