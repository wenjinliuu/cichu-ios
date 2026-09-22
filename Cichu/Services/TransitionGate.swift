import Foundation

/// Requires two consistent observations separated in time; silence is never evidence.
struct TransitionGate: Codable {
    struct Candidate: Codable, Equatable {
        let placeID: UUID? // nil = outside all saved places
        let firstSeen: Date
    }
    private(set) var candidate: Candidate?
    var dwell: TimeInterval = 90
    mutating func reset() { candidate = nil }
    mutating func observe(placeID: UUID?, currentID: UUID?, at date: Date) -> Bool {
        guard placeID != currentID else { reset(); return false }
        if let candidate, candidate.placeID == placeID,
           date.timeIntervalSince(candidate.firstSeen) >= dwell,
           date.timeIntervalSince(candidate.firstSeen) <= 600 {
            reset(); return true
        }
        if candidate?.placeID != placeID || candidate == nil || date.timeIntervalSince(candidate!.firstSeen) > 600 {
            candidate = Candidate(placeID: placeID, firstSeen: date)
        }
        return false
    }
}
