import Testing
@testable import WardrobeKit

@MainActor
struct PhotoLibraryPagingTests {
    @Test func theGalleryOpensWithTheFirstPageOnly() async {
        let library = FakePhotoLibrary(access: .authorized, assets: Self.pageFixture(200))
        let sut = makeCaptureFlowSUT(library: library)

        sut.prepareLibraryAccess()
        await sut.thumbnailTask?.value

        #expect(sut.recentAssets.count == 60, "the whole library must not be pulled in one go")
    }

    @Test func reachingTheEndLoadsTheNextPage() async {
        let library = FakePhotoLibrary(access: .authorized, assets: Self.pageFixture(200))
        let sut = makeCaptureFlowSUT(library: library)
        sut.prepareLibraryAccess()
        await sut.thumbnailTask?.value

        sut.loadMoreAssets()
        await sut.assetsTask?.value
        #expect(sut.recentAssets.count == 120)

        sut.loadMoreAssets()
        await sut.assetsTask?.value

        #expect(sut.recentAssets.count == 180)
        #expect(
            Set(sut.recentAssets.map(\.id)).count == 180,
            "a page must not repeat what is already on screen"
        )
    }

    @Test func theGalleryStopsAskingOnceTheLibraryIsExhausted() async {
        let library = FakePhotoLibrary(access: .authorized, assets: Self.pageFixture(200))
        let sut = makeCaptureFlowSUT(library: library)
        sut.prepareLibraryAccess()
        await sut.thumbnailTask?.value
        for _ in 0 ..< 4 {
            sut.loadMoreAssets()
            await sut.assetsTask?.value
        }
        #expect(sut.recentAssets.count == 200)
        let asked = await library.fetchCount

        sut.loadMoreAssets()
        await sut.assetsTask?.value

        #expect(sut.recentAssets.count == 200)
        #expect(
            await library.fetchCount == asked,
            "the grid keeps firing onAppear; an exhausted library has to stop being asked"
        )
    }

    @Test func aSecondRequestWhileOneIsInFlightIsIgnored() async {
        let library = FakePhotoLibrary(access: .authorized, assets: Self.pageFixture(200))
        let sut = makeCaptureFlowSUT(library: library)
        sut.prepareLibraryAccess()
        await sut.thumbnailTask?.value

        sut.loadMoreAssets()
        sut.loadMoreAssets()
        await sut.assetsTask?.value

        #expect(sut.recentAssets.count == 120, "onAppear fires repeatedly; only one page may be in flight")
    }

    private static func pageFixture(_ count: Int) -> [PhotoAsset] {
        (0 ..< count).map { PhotoAsset(id: "asset-\($0)") }
    }
}
