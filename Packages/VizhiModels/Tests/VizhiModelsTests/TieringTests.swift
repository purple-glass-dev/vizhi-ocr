import Foundation
import Testing
@testable import VizhiModels

@Suite("RAM tiering")
struct TieringTests {
    // A fixed fixture so these assertions don't depend on the shipping catalog's contents.
    let catalog = ModelCatalog(version: 1, models: [
        ModelDescriptor(id: "glm-ocr-lite", displayName: "Lite", tier: .lite, capabilities: [.text],
                        minRAMGB: 8, recommendedRAMGB: 8, quantization: "q4",
                        source: ModelSource(huggingFaceRepo: "x/lite")),
        ModelDescriptor(id: "glm-ocr-standard", displayName: "Standard", tier: .standard, capabilities: [.text],
                        minRAMGB: 16, recommendedRAMGB: 24, quantization: "q4",
                        source: ModelSource(huggingFaceRepo: "x/standard")),
        ModelDescriptor(id: "glm-ocr-ultra", displayName: "Ultra", tier: .ultra, capabilities: [.text],
                        minRAMGB: 32, recommendedRAMGB: 32, quantization: "q4",
                        source: ModelSource(huggingFaceRepo: "x/ultra")),
    ])
    let tiering = ModelTiering()

    @Test("8 GB machine gets only Lite, recommended Lite")
    func eightGB() {
        let eligible = tiering.eligibleModels(in: catalog, installedRAMGB: 8)
        #expect(eligible.map(\.id) == ["glm-ocr-lite"])
        #expect(tiering.recommendedModel(in: catalog, installedRAMGB: 8)?.id == "glm-ocr-lite")
    }

    @Test("16 GB fits Lite+Standard and recommends the most capable (Standard)")
    func sixteenGB() {
        let eligible = tiering.eligibleModels(in: catalog, installedRAMGB: 16)
        #expect(Set(eligible.map(\.id)) == ["glm-ocr-lite", "glm-ocr-standard"])
        #expect(tiering.recommendedModel(in: catalog, installedRAMGB: 16)?.id == "glm-ocr-standard")
        // Standard meets minRAM (16) but not recommendedRAM (24): runs, but tight.
        let standard = catalog.model(id: "glm-ocr-standard")!
        #expect(tiering.isComfortable(standard, installedRAMGB: 16) == false)
        #expect(tiering.isComfortable(standard, installedRAMGB: 24) == true)
    }

    @Test("Eligible list is ordered highest tier first")
    func ordering() {
        let eligible = tiering.eligibleModels(in: catalog, installedRAMGB: 64)
        #expect(eligible.map(\.tier) == [.ultra, .standard, .lite])
    }

    @Test("36 GB recommends comfortable Ultra")
    func thirtySixGB() {
        #expect(tiering.recommendedModel(in: catalog, installedRAMGB: 36)?.id == "glm-ocr-ultra")
    }

    @Test("Tiny machine fits nothing")
    func tooSmall() {
        #expect(tiering.eligibleModels(in: catalog, installedRAMGB: 4).isEmpty)
        #expect(tiering.recommendedModel(in: catalog, installedRAMGB: 4) == nil)
    }
}

@Suite("Catalog loading")
struct CatalogTests {
    @Test("Bundled catalog decodes and matches the default model set")
    func bundledLoads() {
        let bundled = ModelCatalog.bundled()
        #expect(bundled.version == ModelCatalog.defaultCatalog.version)
        #expect(bundled.models.map(\.id) == ModelCatalog.defaultCatalog.models.map(\.id))
    }

    @Test("Round-trips through Codable")
    func codableRoundTrip() throws {
        let data = try JSONEncoder().encode(ModelCatalog.defaultCatalog)
        let decoded = try JSONDecoder().decode(ModelCatalog.self, from: data)
        #expect(decoded == ModelCatalog.defaultCatalog)
    }

    @Test("The catalog default is GLM-OCR 4-bit, used whenever it fits")
    func defaultModelPreference() {
        let catalog = ModelCatalog.defaultCatalog
        #expect(catalog.defaultModelID == "glm-ocr-4bit")
        #expect(catalog.defaultOCRModel(installedRAMGB: 8)?.id == "glm-ocr-4bit")
        #expect(catalog.defaultOCRModel(installedRAMGB: 32)?.id == "glm-ocr-4bit")

        // When the preferred default can't fit, fall back to RAM tiering (most capable that fits).
        let tiny = ModelCatalog(version: 1, defaultModelID: "big", models: [
            ModelDescriptor(id: "big", displayName: "Big", tier: .ultra, capabilities: [.text],
                            minRAMGB: 64, recommendedRAMGB: 64, quantization: "q4",
                            source: ModelSource(huggingFaceRepo: "x/big")),
            ModelDescriptor(id: "small", displayName: "Small", tier: .lite, capabilities: [.text],
                            minRAMGB: 8, recommendedRAMGB: 8, quantization: "q4",
                            source: ModelSource(huggingFaceRepo: "x/small")),
        ])
        #expect(tiny.defaultOCRModel(installedRAMGB: 16)?.id == "small")
    }

    @Test("activeModel uses the selection when it resolves, else the RAM default")
    func activeModelResolution() {
        let catalog = ModelCatalog.defaultCatalog
        // An explicit, valid selection wins regardless of RAM.
        #expect(catalog.activeModel(selectedID: "glm-ocr-8bit", installedRAMGB: 8)?.id == "glm-ocr-8bit")
        // An unknown selection falls back to the RAM-appropriate default.
        let fallback = catalog.defaultOCRModel(installedRAMGB: 8)?.id
        #expect(catalog.activeModel(selectedID: "does-not-exist", installedRAMGB: 8)?.id == fallback)
        // No selection → the default.
        #expect(catalog.activeModel(selectedID: nil, installedRAMGB: 8)?.id == fallback)
    }
}
