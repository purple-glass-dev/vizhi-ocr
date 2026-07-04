import VizhiModels

/// Builds the instruction prompt handed to a VLM/OCR model. Pure and testable so prompt changes
/// can be locked down without running inference.
public struct OCRPromptBuilder: Sendable {
    public init() {}

    /// The instruction handed to the model. OCR fine-tunes trained on a specific prompt carry it in
    /// the catalog (`model.prompt`); when present we use it verbatim, since fighting a model's
    /// trained prompt degrades output. Otherwise we build a generic, capability-aware instruction
    /// (which GLM-OCR handles well).
    ///
    /// An optional `userHint` (a per-document note the user typed) is appended last, after the
    /// model's base/trained instruction, so it nudges without replacing trained behavior.
    public func instruction(for model: ModelDescriptor, userHint: String? = nil) -> String {
        appendingHint(userHint, to: baseInstruction(for: model))
    }

    private func baseInstruction(for model: ModelDescriptor) -> String {
        if !model.prompt.isEmpty { return model.prompt }

        var rules = ["Transcribe all text from the image exactly, preserving reading order."]

        if model.capabilities.contains(.multicolumn) {
            rules.append("Respect multi-column layouts, reading each column top-to-bottom.")
        }
        if model.capabilities.contains(.tables) {
            rules.append("Render tables as GitHub-flavored Markdown tables.")
        }
        if model.capabilities.contains(.math) {
            rules.append("Write mathematics as LaTeX: inline as $...$ and display equations as $$...$$.")
        }
        if model.capabilities.contains(.handwriting) {
            rules.append("Transcribe handwriting as plain text.")
        }
        rules.append("Output GitHub-flavored Markdown only, with no commentary or code fences around the whole result.")

        return rules.joined(separator: " ")
    }

    /// Appends a trimmed, non-empty user hint as an extra guidance sentence.
    private func appendingHint(_ hint: String?, to instruction: String) -> String {
        let trimmed = hint?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return instruction }
        return instruction + " Additional guidance for this document: \(trimmed)"
    }
}
