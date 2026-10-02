import Foundation

extension JournalStore {
    /// Visits are approximate historical intervals. They can repair automatic intervals,
    /// but never replace a manual interval or silently invent an unknown arrival.
    func reconcileVisit(_ place: Place, arrival: Date?, departure: Date?, key: String, receivedAt: Date) {
        guard !observations.contains(where: { $0.key == key }) else { return }
        let observation = LocationObservation(key: key, placeID: place.id, arrival: arrival, departure: departure, receivedAt: receivedAt)
        context.insert(observation)
        func finish(_ result: String) {
            observation.result = result
            for old in observations.dropFirst(1999) { context.delete(old) }
            commit()
        }
        guard let start = arrival else {
            if let end = departure, let current = active, current.kind == .stay, current.placeID == place.id, current.source == .automatic, end >= current.start {
                current.lastObserved = end; current.end = end
                let travel = JournalEntry(kind: .travel, placeID: place.id, start: end, source: .automatic)
                travel.lastObserved = end; context.insert(travel); finish("closed-known-arrival")
            } else { finish("missing-arrival") }
            return
        }
        if departure == nil, observations.contains(where: { $0.placeID == place.id && $0.arrival == start && $0.departure != nil }) { finish("arrival-after-departure"); return }
        let end = departure ?? receivedAt
        guard start <= receivedAt, end <= receivedAt, end >= start else { finish("invalid-time"); return }
        let affected = entries.filter { $0.start < (departure ?? .distantFuture) && ($0.end ?? .distantFuture) > start }
        if affected.contains(where: { $0.source == .manual }) { finish("protected-manual-record"); return }
        if departure == nil, affected.contains(where: { $0.start > start && ($0.kind != .stay || $0.placeID != place.id) }) {
            finish("stale-arrival"); return
        }
        var hasFollowing = entries.contains { entry in
            guard let departure else { return false }
            return entry.start >= departure && !affected.contains { $0.id == entry.id }
        }
        for entry in affected {
            let originalEnd = entry.end
            let sameStay = entry.kind == .stay && entry.placeID == place.id
            if let departure, let originalEnd, originalEnd > departure, !sameStay {
                let suffix = JournalEntry(kind: entry.kind, placeID: entry.placeID, destinationID: entry.destinationID,
                                          start: departure, end: originalEnd, source: .automatic, note: entry.note)
                suffix.needsReview = true; suffix.lastObserved = entry.lastObserved; context.insert(suffix); hasFollowing = true
            }
            if entry.start < start, !sameStay {
                entry.end = start
                if entry.kind == .travel { entry.destinationID = place.id }
            } else { context.delete(entry) }
        }
        let stay = JournalEntry(kind: .stay, placeID: place.id, start: start, end: departure, source: .automatic)
        stay.lastObserved = departure ?? receivedAt; context.insert(stay)
        if let departure, !hasFollowing {
            let travel = JournalEntry(kind: .travel, placeID: place.id, start: departure, source: .automatic)
            travel.lastObserved = departure; context.insert(travel)
        }
        finish("applied")
    }
}
