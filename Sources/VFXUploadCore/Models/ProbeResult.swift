import Foundation

public struct ProbeResult: Sendable {
    public let hasAudioTrack: Bool
    public let colorPrimaries: String?
    public let colorTransfer: String?
    public let colorSpace: String?

    /// Returns true if the file already has the correct color metadata for the target,
    /// or if the target is `.none` (skip tagging).
    public func alreadyTagged(as target: ColorSpace) -> Bool {
        guard let expected = target.expectedProbeValues else { return true }

        guard let primaries = colorPrimaries, primaries != "unknown",
              let transfer = colorTransfer, transfer != "unknown",
              let space = colorSpace, space != "unknown"
        else { return false }

        return primaries == expected.primaries
            && transfer == expected.transfer
            && space == expected.space
    }
}
