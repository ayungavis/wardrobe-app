import CoreGraphics

/// The story-format frame every edited photo lives in. The editor canvas and
/// the exported file share these numbers, so what the user arranges is
/// exactly what gets saved and shared.
///
/// The camera captures 4:3 (the `.photo` preset), so the photo is
/// aspect-filled into this frame — the same crop the full-screen camera
/// preview already showed.
public enum StoryCanvas {
    public static let aspectRatio: CGFloat = 9.0 / 16.0
    public static let exportSize = CGSize(width: 1080, height: 1920)
}
