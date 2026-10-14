import CoreGraphics
import Testing
@testable import CouleurCore

@Test func retinaScreenUsesPhysicalPixelsAndTopLeftImageCoordinates() {
    let grid = ScreenPixelGrid(frame: CGRect(x: 0, y: 0, width: 1440, height: 900), width: 2880, height: 1800)
    let upperLeft = grid.pixel(at: CGPoint(x: 0.25, y: 899.75))
    #expect(upperLeft?.x == 0)
    #expect(upperLeft?.y == 0)
    let lowerRight = grid.pixel(at: CGPoint(x: 1439.75, y: 0.25))
    #expect(lowerRight?.x == 2879)
    #expect(lowerRight?.y == 1799)
    let middle = grid.pixel(at: CGPoint(x: 720.5, y: 450.5))
    #expect(middle?.x == 1441)
    #expect(middle?.y == 899)
}

@Test func screenToTheLeftAndAboveThePrimaryUsesItsOwnOriginAndScale() {
    let grid = ScreenPixelGrid(frame: CGRect(x: -1920, y: 300, width: 1920, height: 1080), width: 1920, height: 1080)
    let pixel = grid.pixel(at: CGPoint(x: -1919.5, y: 1379.5))
    #expect(pixel?.x == 0)
    #expect(pixel?.y == 0)
    #expect(grid.pixel(at: CGPoint(x: 0, y: 400)) == nil)
    #expect(grid.pixel(at: CGPoint(x: -1921, y: 400)) == nil)
    #expect(grid.pixel(at: CGPoint(x: -400, y: 1380)) == nil)
    #expect(grid.pixel(at: CGPoint(x: -400, y: 299)) == nil)
}

@Test func keyboardPixelCentersRoundTripAtFractionalDisplayScaling() {
    let grid = ScreenPixelGrid(frame: CGRect(x: 1440, y: -250, width: 1536, height: 864), width: 2560, height: 1440)
    for (x, y) in [(0, 0), (2559, 1439), (1234, 567), (1, 1)] {
        let pixel = grid.pixel(at: grid.center(x: x, y: y))
        #expect(pixel?.x == x)
        #expect(pixel?.y == y)
    }
}

@Test func bottomEdgeIsClampedToTheLastRowAndInvalidDisplaysCannotBeSampled() {
    let grid = ScreenPixelGrid(frame: CGRect(x: 0, y: 0, width: 100, height: 50), width: 200, height: 100)
    #expect(grid.pixel(at: CGPoint(x: 0, y: 0))?.y == 99)
    #expect(grid.pixel(at: CGPoint(x: 100, y: 0)) == nil)
    #expect(ScreenPixelGrid(frame: .zero, width: 0, height: 0).pixel(at: .zero) == nil)
}
