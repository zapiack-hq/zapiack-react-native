import Foundation

/// Picks the file type a downloaded picture is shown as; the system decides from the extension.
public struct ImageFile: Equatable {
    public var fileExtension: String

    public static func kind(mimeType: String?, url: URL) -> ImageFile? {
        switch mimeType?.lowercased() {
        case "image/jpeg", "image/jpg": return ImageFile(fileExtension: "jpg")
        case "image/png": return ImageFile(fileExtension: "png")
        case "image/gif": return ImageFile(fileExtension: "gif")
        case "image/webp": return nil
        default:
            switch url.pathExtension.lowercased() {
            case "jpg", "jpeg": return ImageFile(fileExtension: "jpg")
            case "png": return ImageFile(fileExtension: "png")
            case "gif": return ImageFile(fileExtension: "gif")
            default: return nil
            }
        }
    }
}
