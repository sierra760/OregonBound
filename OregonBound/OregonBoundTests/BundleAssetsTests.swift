import XCTest
@testable import OregonBound

final class BundleAssetsTests: XCTestCase {
    override func setUpWithError() throws { try GameDataTestSupport.requireGameData() }

    func testManifestDecodes243Images() {
        let count = BundleAssets.validateManifest()
        XCTAssertEqual(count, 243)
    }

    func testManifestImageHasResourceMetadata() throws {
        let manifest = try XCTUnwrap(BundleAssets.loadManifest())
        let first = try XCTUnwrap(manifest.images.first)
        XCTAssertEqual(first.resource.type, "Imag")
        XCTAssertEqual(first.resource.id, 19000)
        XCTAssertEqual(first.frame_count, 47)
    }

    func testLookupByResourceId() throws {
        let manifest = try XCTUnwrap(BundleAssets.loadManifest())
        let frames = manifest.images(forResourceId: 19000)
        XCTAssertEqual(frames.count, 47)
    }

    func testLookupByType() throws {
        let manifest = try XCTUnwrap(BundleAssets.loadManifest())
        let cicnImages = manifest.images(ofType: "cicn")
        XCTAssertEqual(cicnImages.count, 24)
    }

    func testManifestEntryDecodesKnownJSON() throws {
        let json = """
        {
          "source_file": "test",
          "images": [{
            "resource": {"source_file": "test", "type": "Imag", "id": 100, "name": "", "raw_length": 1024},
            "status": "ok",
            "image_path": "images/test_00.png",
            "width": 100,
            "height": 50,
            "mode": "P",
            "frame_index": 0,
            "frame_count": 1,
            "palette": null
          }]
        }
        """
        let data = Data(json.utf8)
        let manifest = try JSONDecoder().decode(GraphicsManifest.self, from: data)
        XCTAssertEqual(manifest.images.count, 1)
        XCTAssertEqual(manifest.images[0].image_path, "images/test_00.png")
        XCTAssertEqual(manifest.images[0].resource.type, "Imag")
        XCTAssertNil(manifest.images[0].palette)
    }
}
