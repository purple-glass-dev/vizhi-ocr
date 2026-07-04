import Carbon.HIToolbox
import CoreGraphics
import Foundation
import Testing
@testable import VizhiCapture

@Suite("Region geometry")
struct RegionGeometryTests {
    @Test("Drag normalizes to a positive rect regardless of direction")
    func normalize() {
        let rect = RegionGeometry.rect(from: CGPoint(x: 100, y: 80), to: CGPoint(x: 40, y: 120))
        #expect(rect == CGRect(x: 40, y: 80, width: 60, height: 40))
    }

    @Test("Crop converts bottom-left global selection to top-left display-local")
    func cropConversion() {
        // 1000-tall display at origin; selection 100 tall whose top is 100px below the display top.
        let display = CGRect(x: 0, y: 0, width: 1920, height: 1000)
        let selection = CGRect(x: 50, y: 800, width: 200, height: 100) // maxY = 900
        let crop = RegionGeometry.cropRect(selectionInGlobal: selection, displayFrame: display)
        // flippedY = 1000 - 900 = 100
        #expect(crop == CGRect(x: 50, y: 100, width: 200, height: 100))
    }

    @Test("Selection is clamped to the display bounds")
    func clamping() {
        let display = CGRect(x: 0, y: 0, width: 800, height: 600)
        let selection = CGRect(x: 700, y: 500, width: 400, height: 400) // spills off the top-right
        let crop = RegionGeometry.cropRect(selectionInGlobal: selection, displayFrame: display)
        #expect(crop == CGRect(x: 700, y: 0, width: 100, height: 100))
    }

    @Test("Non-overlapping selection yields nil")
    func noOverlap() {
        let display = CGRect(x: 0, y: 0, width: 800, height: 600)
        let selection = CGRect(x: 2000, y: 2000, width: 100, height: 100)
        #expect(RegionGeometry.cropRect(selectionInGlobal: selection, displayFrame: display) == nil)
    }

    @Test("Secondary display offset is handled")
    func secondaryDisplay() {
        let display = CGRect(x: 1920, y: 0, width: 1920, height: 1080)
        let selection = CGRect(x: 1970, y: 980, width: 100, height: 100) // maxY = 1080
        let crop = RegionGeometry.cropRect(selectionInGlobal: selection, displayFrame: display)
        #expect(crop == CGRect(x: 50, y: 0, width: 100, height: 100))
    }
}

@Suite("Hotkeys")
struct HotkeyTests {
    @Test("Modifier symbols use conventional order ⌃⌥⇧⌘")
    func symbols() {
        let mods: HotkeyModifiers = [.command, .shift, .control, .option]
        #expect(mods.symbols == "⌃⌥⇧⌘")
    }

    @Test("Display string combines modifiers and key label")
    func display() {
        let hotkey = Hotkey(keyCode: 19, modifiers: [.command, .shift], keyLabel: "2")
        #expect(hotkey.displayString == "⇧⌘2")
    }

    @Test("Defaults cover every capture action and Codable round-trips")
    func defaults() throws {
        let defaults = Hotkey.defaults()
        #expect(Set(defaults.keys) == Set(CaptureAction.allCases))
        let data = try JSONEncoder().encode(defaults[.fastCapture])
        let decoded = try JSONDecoder().decode(Hotkey.self, from: data)
        #expect(decoded == defaults[.fastCapture])
    }

    @Test("Modifiers map to the Carbon mask")
    func carbonMapping() {
        #expect(CarbonHotkeyManager.carbonModifiers([.command]) == UInt32(cmdKey))
        #expect(CarbonHotkeyManager.carbonModifiers([.command, .shift]) == UInt32(cmdKey) | UInt32(shiftKey))
        #expect(CarbonHotkeyManager.carbonModifiers([.control, .option]) == UInt32(controlKey) | UInt32(optionKey))
        #expect(CarbonHotkeyManager.carbonModifiers([]) == 0)
    }
}
