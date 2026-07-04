import SwiftUI
import VizhiModels
import VizhiUI

/// Hosts the model manager, building presentations from the catalog, detected RAM, and on-disk
/// install state, and driving downloads through the shared `ModelDownloadManager`.
struct ModelManagerWindowView: View {
    let settings: SettingsStore
    let downloads: ModelDownloadManager

    private let catalog = ModelCatalog.bundled()
    private let store = ModelStore()
    private let installedRAMGB = ModelTiering.installedRAMGB

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(installedRAMGB) GB RAM detected")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal)
            ModelManagerView(
                presentations: presentations,
                downloads: downloads,
                activeModelID: settings.selectedModelID,
                onDownload: { downloads.download($0) },
                onCancel: { downloads.cancel($0) },
                onDelete: {
                    try? downloads.delete($0)
                    if settings.selectedModelID == $0.id { settings.selectedModelID = nil }
                },
                onUse: { settings.selectedModelID = $0.id }
            )
        }
        .padding(.top)
        .frame(minWidth: 480, minHeight: 360)
    }

    private var presentations: [ModelPresentation] {
        let tiering = ModelTiering()
        // Badge the model AI capture actually defaults to (the catalog's `defaultModelID`,
        // GLM-OCR 4-bit), not just the highest-tier model the RAM allows. Keeps the "Recommended"
        // badge consistent with what a fresh AI capture really loads.
        let recommended = catalog.defaultOCRModel(installedRAMGB: installedRAMGB)?.id
        return catalog.models.map { model in
            ModelPresentation(
                model: model,
                installedRAMGB: installedRAMGB,
                installState: store.installState(for: model),
                recommendedID: recommended,
                tiering: tiering
            )
        }
    }
}
