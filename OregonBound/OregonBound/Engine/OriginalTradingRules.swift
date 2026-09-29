import Foundation

/// Single-wagon CODE3:3e0a/4360/4b64. See ORIGINAL_TRADING.md and Python oracle.
enum OriginalTradingRules {
    typealias Draw = (_ bound: Int, _ codeOffset: Int) -> Int
    static let unitCents = [2000, 1000, 10, 1000, 1000, 1000, 20, 100]
    static let capacities = [40, 50, 1980, 3, 3, 3, 2000]
    private static let savedCashLimit = 1_000_000

    struct Request: Codable, Equatable {
        var item: Int
        var quantity: Int // Whole displayed oxen, ordinary supplies, or cents.
        var isValid: Bool {
            guard (0..<8).contains(item), quantity > 0, item != 7 || quantity.isMultiple(of: 100) else { return false }
            return quantity <= (item == 7 ? savedCashLimit : item == 0 ? capacities[0] / 2 : capacities[item])
        }
    }
    struct Offer: Codable, Equatable {
        var item: Int
        var quantity: Int // Whole displayed oxen, ordinary supplies, or cents.
        var isValid: Bool {
            guard (0..<8).contains(item), quantity > 0, item != 7 || quantity.isMultiple(of: 100) else { return false }
            // Legacy saves may contain80 raw oxen. Generated offers still retain
            // one whole ox; incoming purchases keep the original40 raw capacity.
            return quantity <= (item == 7 ? savedCashLimit : item == 0 ? 40 : capacities[item])
        }
    }
    struct Session: Codable, Equatable {
        var request: Request
        var offer: Offer?
        var portrait: Int
        var isValid: Bool {
            request.isValid && (0..<9).contains(portrait) && portrait != 6 &&
            (offer.map { $0.isValid && $0.item != request.item } ?? true)
        }
    }
    enum Resolution: Equatable { case accepted, refused, noOffer, noSpace, cannotPay }

    static func request(item: Int, displayedQuantity: Int, in trip: Journey) throws -> Request {
        guard (0..<8).contains(item), displayedQuantity > 0,
              displayedQuantity <= (item == 7 ? savedCashLimit / 100 : item == 0 ? 20 : capacities[item]) else {
            throw GameRuleError("You must enter a quantity for that item.")
        }
        let request = Request(item: item, quantity: displayedQuantity * (item == 7 ? 100 : 1))
        guard hasSpace(request, in: trip) else {
            throw GameRuleError(item == 0 ? "There won't be enough grass for all the oxen." : "You don't have enough space in the wagon.")
        }
        return request
    }

    private static func hasSpace(_ request: Request, in trip: Journey) -> Bool {
        guard request.isValid else { return false }
        if request.item == 7 { return trip.cash <= savedCashLimit - request.quantity }
        let raw = request.quantity * (request.item == 0 ? 2 : 1)
        return trip.inventory[Supply.allCases[request.item]] <= capacities[request.item] - raw
    }

    /// The original uses Float32 temporary storage, then SANE FTINT selector16.
    /// Do not perform the last multiply in Float: 50 × Float(.9) must truncate44.
    static func paymentQuantity(request: Request, paymentItem: Int, percent: Int) -> Int {
        guard request.isValid, (0..<8).contains(paymentItem), (80...120).contains(percent) else { return 0 }
        var base = Float(Double(unitCents[request.item]) / Double(unitCents[paymentItem]) * Double(request.quantity))
        if request.item == 7 { base = Float(Double(base) / 100) }
        let factor = Float(Double(percent) / 100)
        return max(1, Int(Double(base) * Double(factor)))
    }

    static func presentation(request: Request, trip: Journey, draw: Draw) throws -> Session {
        guard request.isValid, hasSpace(request, in: trip) else { throw GameRuleError("That trade request is not valid.") }
        var offer: Offer?
        if draw(1000, 0x43d2) > 333 {
            var available = Supply.allCases.map { trip.inventory[$0] }
            available[0] /= 2 // Original affordability floors odd raw oxen.
            available.append(max(0, trip.cash) / 100)
            var untried = Set(0..<8); untried.remove(request.item)
            while !untried.isEmpty {
                let item = draw(8, 0x3f7c)
                if item == request.item { continue }
                let amount = paymentQuantity(request: request, paymentItem: item, percent: 80 + draw(41, 0x4096))
                if amount < available[item] || (item != 0 && amount == available[item]) {
                    offer = Offer(item: item, quantity: amount * (item == 7 ? 100 : 1))
                    break
                }
                untried.remove(item) // Failed types remain drawable with new prices.
            }
        }
        var portrait = draw(9, 0x4712)
        while portrait == 6 { portrait = draw(9, 0x4712) }
        return Session(request: request, offer: offer, portrait: portrait)
    }

    /// Atomically generate and save the complete pending presentation, including
    /// portrait RNG. Loading or drawing the pane never samples randomness.
    static func begin(item: Int, displayedQuantity: Int, in trip: inout Journey) throws {
        guard trip.canCamp, trip.originalTradeSession == nil else { throw GameRuleError("You cannot start another trade now.") }
        var next = trip
        next.ensureOriginalState()
        let request = try request(item: item, displayedQuantity: displayedQuantity, in: next)
        var random = OriginalRandom(seed: next.randomState)
        let session = try presentation(request: request, trip: next) { bound, _ in random.bounded(bound) }
        next.randomState = random.seed
        next.originalTradeSession = session
        trip = next
    }

    /// No time, food, damage, or RNG changes. Continue installs acquired spares.
    /// Consume the saved session once; fresh validation precedes all resource writes.
    @discardableResult static func finish(accept: Bool, in trip: inout Journey) throws -> Resolution? {
        guard let session = trip.originalTradeSession else { return nil }
        guard session.isValid else { throw GameRuleError("The saved trade offer is invalid.") }
        trip.originalTradeSession = nil
        guard let offer = session.offer else { return .noOffer }
        guard accept else { return .refused }
        let requested = description(item: session.request.item, quantity: session.request.quantity)
        let payment = description(item: offer.item, quantity: offer.quantity)
        guard hasSpace(session.request, in: trip) else {
            trip.record("You don’t have space in your wagon to carry the \(requested) that you agreed to trade for")
            return .noSpace
        }
        let rawPayment = offer.quantity * (offer.item == 0 ? 2 : 1)
        let available = offer.item == 7 ? trip.cash : trip.inventory[Supply.allCases[offer.item]]
        guard rawPayment <= available else {
            trip.record("You no longer have the \(payment) to trade")
            return .cannotPay
        }
        if offer.item == 7 { trip.cash -= rawPayment }
        else { trip.inventory[Supply.allCases[offer.item]] -= rawPayment }
        if session.request.item == 7 { trip.cash += session.request.quantity }
        else { trip.inventory[Supply.allCases[session.request.item]] += session.request.quantity * (session.request.item == 0 ? 2 : 1) }
        trip.record("You traded \(payment) for \(requested).")
        return .accepted
    }

    static func description(item: Int, quantity: Int) -> String {
        guard (0..<8).contains(item), quantity >= 0 else { return "" }
        if item == 7 { return "$\(quantity / 100)" }
        let plural = ["oxen", "sets of clothing", "bullets", "wagon wheels", "wagon axles", "wagon tongues", "pounds of food"]
        let singular = ["ox", "set of clothing", "bullet", "wagon wheel", "wagon axle", "wagon tongue", "pound of food"]
        return "\(quantity) \(quantity == 1 ? singular[item] : plural[item])"
    }
}
