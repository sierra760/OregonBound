/// The classic About pane queried its actual runtime. A native build therefore
/// displays supplied host facts, never a fictional classic Macintosh profile.
extension OriginalAboutRules {
    /// CODE2:0760–0a7e field order. The last four fields describe AppleTalk and
    /// classic application-zone/PurgeSpace state, with no equivalent native heap.
    /// Physical RAM, resident size and CPU core count are not substitutes.
    static func systemInformation(machineType: String, processor: String, systemVersion: String) -> [String] {
        [machineType, processor, systemVersion].map { $0.isEmpty ? "Unavailable" : $0 }
            + ["N/A", "N/A", "N/A", "N/A"]
    }
}
