import Foundation

public struct Project: Identifiable, Hashable, Sendable {
    public let id: String
    public let displayName: String
    public let s3Bucket: String
    public let s3BasePath: String
    public let episodeNumber: Int
    public let colorSpace: ColorSpace
    /// Episodes 201-204 use "01_Plates"/"03_VFX"; 205-207 use "Plates"/"VFX"
    public let platesFolder: String
    public let vfxFolder: String

    public init(
        id: String, displayName: String, s3Bucket: String, s3BasePath: String,
        episodeNumber: Int, colorSpace: ColorSpace,
        platesFolder: String, vfxFolder: String
    ) {
        self.id = id
        self.displayName = displayName
        self.s3Bucket = s3Bucket
        self.s3BasePath = s3BasePath
        self.episodeNumber = episodeNumber
        self.colorSpace = colorSpace
        self.platesFolder = platesFolder
        self.vfxFolder = vfxFolder
    }
}

public enum ProjectCatalog {
    private static let bucket = "sync-services"
    private static let myshowBase = "CLIENTS/Sync_Reed/03_MyShow/MYSHOW_S02"

    public static let all: [Project] = (201...207).map { ep in
        let usesNumberedFolders = ep <= 204
        return Project(
            id: "myshow_\(ep)",
            displayName: "MyShow \(ep)",
            s3Bucket: bucket,
            s3BasePath: "\(myshowBase)/\(ep)/20_WORKING",
            episodeNumber: ep,
            colorSpace: .p3D65PQ,
            platesFolder: usesNumberedFolders ? "01_Plates" : "Plates",
            vfxFolder: usesNumberedFolders ? "03_VFX" : "VFX"
        )
    }

    public static func find(byEpisode episode: Int) -> Project? {
        all.first { $0.episodeNumber == episode }
    }
}
