#if DEBUG
import UIKit
import Vision
import XCTest

/// The existing Signal render strategy, applied repeatedly to the same mounted
/// view so a remount or extra fetch cannot conceal a stale/privacy response.
@MainActor func captureMountedSignal(_ window: UIWindow, controller: UIViewController,
                                     name: String, test: XCTestCase) async throws -> String {
    func scrollView(in view: UIView) -> UIScrollView? {
        guard !view.isHidden, view.alpha > 0 else { return nil }
        if let scroll = view as? UIScrollView, scroll.isScrollEnabled,
           scroll.contentSize.height > scroll.bounds.height { return scroll }
        return view.subviews.lazy.compactMap { scrollView(in: $0) }.first
    }
    controller.view.setNeedsLayout(); controller.view.layoutIfNeeded()
    let scroll = scrollView(in: controller.view)
    let originalOffset = scroll?.contentOffset
    defer { if let originalOffset { scroll?.setContentOffset(originalOffset, animated: false) } }
    if let scroll { scroll.setContentOffset(CGPoint(x: 0, y: -scroll.adjustedContentInset.top), animated: false) }
    var lines: [(text: String, y: CGFloat)] = []
    for page in 0..<40 {
        try await Task.sleep(for: .milliseconds(120))
        controller.view.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat.default(); format.scale = 1; format.opaque = true
        let image = UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { _ in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
        let cg = try XCTUnwrap(image.cgImage)
        // Recognize the whole viewport. Cropping mixed-size metric baselines
        // makes Vision drop separators or misread "of" even in sharp captures.
        let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]; request.minimumTextHeight = 0.005
        try VNImageRequestHandler(cgImage: cg).perform([request])
        for observation in request.results ?? [] {
            guard let text = observation.topCandidates(1).first?.string.lowercased() else { continue }
            let position = (1 - observation.boundingBox.midY) * window.bounds.height + (scroll?.contentOffset.y ?? 0)
            // Keep distinct identical cards; remove only repeated capture of
            // the same text at the same content position across pages.
            if !lines.contains(where: { $0.text == text && abs($0.y - position) < 12 }) { lines.append((text, position)) }
        }
        let attachment = XCTAttachment(image: image); attachment.name = name + "-page-\(page)"
        attachment.lifetime = .keepAlways; test.add(attachment)
        guard let scroll else { break }
        let bottom = max(-scroll.adjustedContentInset.top, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
        let next = min(bottom, scroll.contentOffset.y + scroll.bounds.height * 0.7)
        guard next > scroll.contentOffset.y + 1 else { break }
        scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: next), animated: false)
        XCTAssertLessThan(page, 39, "The full mounted route must fit the bounded capture")
    }
    let text = lines.map(\.text).joined(separator: " ")
    let transcript = XCTAttachment(string: text); transcript.name = name + "-recognized-text"
    transcript.lifetime = .keepAlways; test.add(transcript)
    return text
}
#endif
