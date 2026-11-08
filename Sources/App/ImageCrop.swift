import AppKit
import ImageIO
import UniformTypeIdentifiers

enum PresentationMode: String, Codable, CaseIterable, Identifiable {
    case contain, cover, custom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .contain: return "전체 표시"
        case .cover: return "영역 채우기"
        case .custom: return "직접 선택"
        }
    }
}

// Normalized top-left coordinates, independent of the editor's display size.
struct CropSelection: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    static let full = CropSelection(x: 0, y: 0, width: 1, height: 1)

    var isValid: Bool {
        [x, y, width, height].allSatisfy { $0.isFinite } &&
        x >= 0 && y >= 0 && width > 0 && height > 0 &&
        x + width <= 1.000001 && y + height <= 1.000001
    }

    func rect(in bounds: CGRect) -> CGRect {
        CGRect(x: bounds.minX + x * bounds.width, y: bounds.minY + y * bounds.height,
               width: width * bounds.width, height: height * bounds.height)
    }

    static func bannerDefault(imageSize: CGSize, aspect: Double? = nil) -> CropSelection {
        guard let aspect, aspect.isFinite, aspect > 0, imageSize.width > 0, imageSize.height > 0 else { return .full }
        let ratio = imageSize.width / imageSize.height
        if ratio >= aspect {
            let width = aspect / ratio
            return CropSelection(x: (1 - width) / 2, y: 0, width: width, height: 1)
        }
        let height = ratio / aspect
        return CropSelection(x: 0, y: (1 - height) / 2, width: 1, height: height)
    }
}

struct EditorSettings: Codable {
    let sourceBase64: String
    let mode: PresentationMode
    let selection: CropSelection
    var cropFill: Bool? = nil
}

enum ImageCrop {
    static func jpeg(_ data: Data, selection: CropSelection) throws -> Data {
        guard selection.isValid,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let region = selection.rect(in: bounds).integral.intersection(bounds)
        guard !region.isEmpty, let cropped = image.cropping(to: region) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, cropped, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        return output as Data
    }
}
