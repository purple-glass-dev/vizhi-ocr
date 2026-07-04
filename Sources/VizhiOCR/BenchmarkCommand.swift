import Foundation
import VizhiBench
import VizhiCore
import VizhiMLX
import VizhiModels
import VizhiVision

/// The `--benchmark` entry point. Runs inside the app binary (not a standalone `swift run` tool) so
/// the MLX engine finds the Metal library that only the Xcode build bundles.
///
/// Usage:
///   VizhiOCR --benchmark <corpus-dir> [--out <report.md>] [--models <id,id,…>] [--no-vision]
///
/// By default it evaluates Apple Vision plus every *installed* catalog model. `--models` restricts
/// to specific catalog ids (installed or not — not-installed ones download on first use).
enum BenchmarkCommand {
    /// True when the process was launched to run the benchmark rather than the GUI.
    static var isRequested: Bool { CommandLine.arguments.contains("--benchmark") }

    /// Runs the benchmark synchronously and terminates the process — never returns to the GUI.
    static func run() -> Never {
        let args = CommandLine.arguments
        guard let corpusPath = value(after: "--benchmark", in: args) else {
            fail("usage: VizhiOCR --benchmark <corpus-dir> [--out <report.md>] [--models id,id] [--no-vision]")
        }
        let corpusURL = URL(fileURLWithPath: corpusPath, isDirectory: true)
        let outURL = URL(fileURLWithPath: value(after: "--out", in: args)
            ?? corpusURL.appendingPathComponent("report.md").path)
        let onlyModels = value(after: "--models", in: args)?
            .split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
        let includeVision = !args.contains("--no-vision")

        // Run the async benchmark on the cooperative pool and keep the main *queue* serviced with
        // dispatchMain() rather than parking the main thread on a semaphore: Vision/Metal init can
        // hop onto the main queue, which would deadlock against a blocked main thread. The Task
        // terminates the process when it's done.
        Task {
            await execute(
                corpusURL: corpusURL, outURL: outURL,
                onlyModels: onlyModels, includeVision: includeVision
            )
            exit(0)
        }
        dispatchMain()
    }

    private static func execute(
        corpusURL: URL, outURL: URL, onlyModels: [String]?, includeVision: Bool
    ) async {
        let corpus: BenchmarkCorpus
        do {
            corpus = try BenchmarkCorpus.load(from: corpusURL)
        } catch {
            fail("could not read corpus at \(corpusURL.path): \(error)")
        }
        guard !corpus.items.isEmpty else {
            fail("no benchmark items found under \(corpusURL.path) (need <name>.<img> + <name>.expected.md pairs)")
        }
        print("Corpus: \(corpus.items.count) item(s) across \(Set(corpus.items.map(\.category)).count) categor(ies).")

        let subjects = buildSubjects(onlyModels: onlyModels, includeVision: includeVision)
        guard !subjects.isEmpty else {
            fail("no engines to run (no installed models and --no-vision?). Install a model or drop --no-vision.")
        }
        print("Engines: \(subjects.map(\.label).joined(separator: ", "))\n")

        let renderer = MarkdownRenderer()
        let runner = BenchmarkRunner { renderer.render($0) }
        let results = await runner.run(corpus: corpus, subjects: subjects) { r in
            let score = r.rates.map { String(format: "CER %.1f%%", $0.cer * 100) } ?? "FAILED"
            print(String(format: "  %-22@ %-28@ %@  (%.2fs)",
                         r.engineID as NSString, r.itemID as NSString, score as NSString, r.durationSeconds))
        }

        let report = ReportGenerator().generate(results: results)
        do {
            try report.write(to: outURL, atomically: true, encoding: .utf8)
            print("\nReport written to \(outURL.path)")
        } catch {
            fail("could not write report to \(outURL.path): \(error)")
        }

        // Raw hypotheses next to the report, for eyeballing where the score comes from.
        let dumpURL = outURL.deletingPathExtension().appendingPathExtension("hypotheses.md")
        var dump = "# Raw hypotheses\n\n"
        for r in results.sorted(by: { ($0.itemID, $0.engineID) < ($1.itemID, $1.engineID) }) {
            dump += "## \(r.itemID) — \(r.engineID)\n\n```\n\(r.error ?? r.hypothesis)\n```\n\n"
        }
        try? dump.write(to: dumpURL, atomically: true, encoding: .utf8)
        print("Hypotheses written to \(dumpURL.path)")
    }

    /// Builds the engines to evaluate: optionally Vision, then the requested (or all installed)
    /// catalog models, each pointed at its on-disk directory so it loads offline.
    private static func buildSubjects(onlyModels: [String]?, includeVision: Bool) -> [BenchmarkRunner.Subject] {
        var subjects: [BenchmarkRunner.Subject] = []
        if includeVision {
            subjects.append(.init(label: "Apple Vision", engine: VisionOCREngine()))
        }

        let catalog = ModelCatalog.bundled()
        let store = ModelStore()
        let candidates = onlyModels.map { ids in ids.compactMap { catalog.model(id: $0) } } ?? catalog.models

        for model in candidates {
            let dir: URL?
            switch store.installState(for: model) {
            case .installed(let url): dir = url
            case .notInstalled:
                if onlyModels == nil {
                    print("  (skipping \(model.displayName) — not installed)")
                    continue   // only auto-include installed models; explicit --models may download
                }
                dir = store.directory(for: model)
            }
            let engine = MLXOCREngine(model: model, modelDirectory: dir)
            subjects.append(.init(label: model.displayName, engine: engine))
        }
        return subjects
    }

    // MARK: - Arg helpers

    private static func value(after flag: String, in args: [String]) -> String? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data(("error: " + message + "\n").utf8))
        exit(2)
    }
}
