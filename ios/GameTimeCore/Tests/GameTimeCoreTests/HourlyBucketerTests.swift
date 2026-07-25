import Foundation
import Testing

@testable import GameTimeCore

@Suite("Hourly bucketing")
struct HourlyBucketerTests {
    /// 2026-08-03T00:00:00Z, a Monday, well clear of any DST transition.
    static let epoch = Date(timeIntervalSince1970: 1_785_888_000)

    static func zone(_ identifier: String) -> TimeZone {
        guard let zone = TimeZone(identifier: identifier) else {
            fatalError("the platform has no tzdata for \(identifier)")
        }
        return zone
    }

    /// A window wide enough that the window rule is not what is being tested.
    static let wideWindow = DateInterval(
        start: epoch.addingTimeInterval(-30 * 86400),
        end: epoch.addingTimeInterval(30 * 86400)
    )

    static let farFuture = epoch.addingTimeInterval(60 * 86400)

    // ---------------------------------------------------------------------
    // Alignment
    // ---------------------------------------------------------------------
    // The reason this whole type exists. Not every zone is a whole number of
    // hours from UTC, so a bucket boundary is a *local* hour boundary and only
    // sometimes a UTC one.
    @Test("a whole-hour-offset zone aligns on the UTC hour")
    func wholeHourOffsetAlignsWithUtc() {
        let bucketer = HourlyBucketer(timeZone: Self.zone("America/New_York"))
        let interval = bucketer.bucket(containing: Self.epoch.addingTimeInterval(90 * 60))

        #expect(interval?.start == Self.epoch.addingTimeInterval(3600))
        #expect(interval?.duration == 3600)
    }

    @Test("a half-hour-offset zone aligns thirty minutes past the UTC hour")
    func halfHourOffsetAlignsOffTheUtcHour() {
        // India is +05:30, so local midnight is 18:30 UTC and every local hour
        // starts at :30. A UTC-aligned bucket would straddle the local day
        // boundary and daily cadence would attribute part of Tuesday to Monday.
        let bucketer = HourlyBucketer(timeZone: Self.zone("Asia/Kolkata"))
        let interval = bucketer.bucket(containing: Self.epoch.addingTimeInterval(3600))

        #expect(interval?.start == Self.epoch.addingTimeInterval(1800))
        #expect(interval?.duration == 3600)
    }

    @Test("a forty-five-minute-offset zone aligns at forty-five past")
    func quarterHourOffsetAligns() {
        // Nepal is +05:45 and Chatham is +12:45. These are the zones that make
        // "just bucket in UTC" wrong rather than merely inelegant.
        for identifier in ["Asia/Kathmandu", "Pacific/Chatham"] {
            let bucketer = HourlyBucketer(timeZone: Self.zone(identifier))
            let interval = bucketer.bucket(containing: Self.epoch.addingTimeInterval(3600))
            let offsetIntoTheUtcHour = interval!.start.timeIntervalSince(Self.epoch)
                .truncatingRemainder(dividingBy: 3600)

            #expect(offsetIntoTheUtcHour == 900 || offsetIntoTheUtcHour == 2700,
                    "\(identifier) buckets at :15 or :45 past, got \(offsetIntoTheUtcHour)")
        }
    }

    @Test("every bucket lies inside one local day")
    func everyBucketIsWithinOneLocalDay() {
        // The property the whole scheme exists for, checked directly rather than
        // inferred: if a bucket ever spanned midnight, a daily-cadence goal would
        // have no single day to credit it to.
        for identifier in [
            "America/New_York", "Asia/Kolkata", "Asia/Kathmandu",
            "Pacific/Chatham", "Europe/Lisbon", "Australia/Lord_Howe",
        ] {
            let zone = Self.zone(identifier)
            let bucketer = HourlyBucketer(timeZone: zone)
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = zone

            for hour in 0..<(24 * 3) {
                let instant = Self.epoch.addingTimeInterval(Double(hour) * 3600 + 137)
                guard let interval = bucketer.bucket(containing: instant) else {
                    Issue.record("\(identifier) could not bucket \(instant)")
                    continue
                }
                // The last instant of the bucket, since the interval is half-open.
                let lastInstant = interval.end.addingTimeInterval(-1)
                #expect(
                    calendar.isDate(interval.start, inSameDayAs: lastInstant),
                    "\(identifier): bucket at \(interval.start) crosses a local midnight"
                )
            }
        }
    }

    // ---------------------------------------------------------------------
    // Grouping
    // ---------------------------------------------------------------------
    @Test("samples in one hour from one source become one bucket")
    func samplesCombine() {
        let bucketer = HourlyBucketer(timeZone: Self.zone("UTC"))
        let samples = [
            StubSample(start: Self.epoch.addingTimeInterval(60), value: 300),
            StubSample(start: Self.epoch.addingTimeInterval(600), value: 500),
            StubSample(start: Self.epoch.addingTimeInterval(1800), value: 12),
        ]

        let buckets = bucketer.buckets(
            from: samples, window: Self.wideWindow, asOf: Self.farFuture
        )

        #expect(buckets.count == 1)
        #expect(buckets[0].value == 812)
        #expect(buckets[0].sampleCount == 3)
        #expect(buckets[0].provenance == .device)
        #expect(buckets[0].bucketStart == Self.epoch)
    }

    // The case the provenance-keyed ledger exists for. Collapsing these into one
    // row would mean choosing one provenance for the hour, and the only safe
    // choice is the least trusted — so one hand-typed step would discard 800
    // genuine ones.
    @Test("one hour with three sources becomes three buckets")
    func sourcesStayApart() {
        let bucketer = HourlyBucketer(timeZone: Self.zone("UTC"))
        let samples = [
            StubSample(start: Self.epoch.addingTimeInterval(60), value: 800),
            StubSample(
                start: Self.epoch.addingTimeInterval(120),
                value: 40,
                sourceBundleIdentifier: "com.example.runner",
                deviceManufacturer: nil,
                deviceModel: nil
            ),
            StubSample(start: Self.epoch.addingTimeInterval(180), value: 9000, wasUserEntered: true),
        ]

        let buckets = bucketer.buckets(
            from: samples, window: Self.wideWindow, asOf: Self.farFuture
        )

        #expect(buckets.count == 3)
        #expect(Set(buckets.map(\.provenance)) == [.device, .thirdParty, .manual])
        #expect(buckets.filter(\.provenance.isAdmissible).map(\.value).reduce(0, +) == 840)
    }

    @Test("different metrics never merge")
    func metricsStayApart() {
        let bucketer = HourlyBucketer(timeZone: Self.zone("UTC"))
        let samples = [
            StubSample(metric: .steps, start: Self.epoch.addingTimeInterval(60), value: 800),
            StubSample(
                metric: .distanceMeters, start: Self.epoch.addingTimeInterval(60), value: 610
            ),
        ]

        let buckets = bucketer.buckets(
            from: samples, window: Self.wideWindow, asOf: Self.farFuture
        )

        #expect(buckets.count == 2)
        #expect(Set(buckets.map(\.metric)) == [.steps, .distanceMeters])
    }

    @Test("two apps in one bucket leave the source unnamed rather than guessed")
    func disagreeingSourcesCollapseToNil() {
        let bucketer = HourlyBucketer(timeZone: Self.zone("UTC"))
        let samples = [
            StubSample(
                start: Self.epoch.addingTimeInterval(60),
                value: 100,
                sourceBundleIdentifier: "com.example.one",
                deviceManufacturer: nil,
                deviceModel: "Alpha"
            ),
            StubSample(
                start: Self.epoch.addingTimeInterval(120),
                value: 200,
                sourceBundleIdentifier: "com.example.two",
                deviceManufacturer: nil,
                deviceModel: "Beta"
            ),
        ]

        let buckets = bucketer.buckets(
            from: samples, window: Self.wideWindow, asOf: Self.farFuture
        )

        #expect(buckets.count == 1)
        #expect(buckets[0].value == 300)
        // Naming one of the two would be a guess presented as a fact, and the
        // ledger does not key on bundle identifier so there is no honest answer.
        #expect(buckets[0].sourceBundleIdentifier == nil)
        #expect(buckets[0].deviceModel == nil)
    }

    @Test("output order is deterministic, because the bytes get signed")
    func orderIsDeterministic() {
        // The assertion signs the serialised batch, so a dictionary's iteration
        // order must not reach the wire — two runs over the same samples have to
        // produce the same bytes.
        let bucketer = HourlyBucketer(timeZone: Self.zone("UTC"))
        let samples = (0..<12).map { index in
            StubSample(
                metric: index.isMultiple(of: 2) ? .steps : .distanceMeters,
                start: Self.epoch.addingTimeInterval(Double(index) * 1800),
                value: Double(index) * 10
            )
        }

        let first = bucketer.buckets(from: samples, window: Self.wideWindow, asOf: Self.farFuture)
        let second = bucketer.buckets(
            from: samples.reversed(), window: Self.wideWindow, asOf: Self.farFuture
        )

        #expect(first == second)
        #expect(first.map(\.bucketStart) == first.map(\.bucketStart).sorted())
    }

    // ---------------------------------------------------------------------
    // Straddling samples
    // ---------------------------------------------------------------------
    @Test("a sample spanning two hours is split by overlap")
    func straddlingSampleProrates() {
        let bucketer = HourlyBucketer(timeZone: Self.zone("UTC"))
        // Starts 45 minutes into the hour and runs for an hour, so three
        // quarters lands in the next bucket.
        let sample = StubSample(
            start: Self.epoch.addingTimeInterval(45 * 60), duration: 3600, value: 400
        )

        let buckets = bucketer.buckets(
            from: [sample], window: Self.wideWindow, asOf: Self.farFuture
        )

        #expect(buckets.count == 2)
        #expect(buckets[0].value == 100)
        #expect(buckets[1].value == 300)
        #expect(buckets.map(\.value).reduce(0, +) == 400, "proration conserves the total")
    }

    @Test("a long sample spans every hour it covers and conserves its total")
    func longSampleSpansManyBuckets() {
        let bucketer = HourlyBucketer(timeZone: Self.zone("UTC"))
        let sample = StubSample(
            start: Self.epoch, duration: 5 * 3600, value: 5000
        )

        let buckets = bucketer.buckets(
            from: [sample], window: Self.wideWindow, asOf: Self.farFuture
        )

        #expect(buckets.count == 5)
        #expect(buckets.allSatisfy { $0.value == 1000 })
    }

    @Test("an instantaneous sample lands whole in the hour it happened")
    func zeroDurationSampleIsNotProrated() {
        // Dividing by a zero duration to prorate would produce a NaN that then
        // poisons the bucket, and HealthKit reports plenty of these.
        let bucketer = HourlyBucketer(timeZone: Self.zone("UTC"))
        let sample = StubSample(
            start: Self.epoch.addingTimeInterval(1800), duration: 0, value: 250
        )

        let buckets = bucketer.buckets(
            from: [sample], window: Self.wideWindow, asOf: Self.farFuture
        )

        #expect(buckets.count == 1)
        #expect(buckets[0].value == 250)
    }

    @Test("a sample straddling a half-hour-offset boundary splits at :30")
    func straddlingInHalfHourZone() {
        let bucketer = HourlyBucketer(timeZone: Self.zone("Asia/Kolkata"))
        // Runs from the UTC hour to the next, which in IST crosses a boundary at
        // :30 — the split a UTC-aligned bucketer would get wrong.
        let sample = StubSample(start: Self.epoch, duration: 3600, value: 600)

        let buckets = bucketer.buckets(
            from: [sample], window: Self.wideWindow, asOf: Self.farFuture
        )

        #expect(buckets.count == 2)
        #expect(buckets[0].value == 300)
        #expect(buckets[1].value == 300)
        #expect(buckets[1].bucketStart == Self.epoch.addingTimeInterval(1800))
    }

    // ---------------------------------------------------------------------
    // The rules that mirror the server
    // ---------------------------------------------------------------------
    @Test("an hour that has not finished is dropped")
    func inProgressHourIsDropped() {
        // The server refuses it outright, because accepting it would let a client
        // bank a winning scoreline for the rest of an open contest in advance.
        // Dropping it here saves a round trip to be told so.
        let bucketer = HourlyBucketer(timeZone: Self.zone("UTC"))
        let asOf = Self.epoch.addingTimeInterval(2 * 3600 + 30 * 60)
        let samples = [
            StubSample(start: Self.epoch.addingTimeInterval(60), value: 100),
            StubSample(start: Self.epoch.addingTimeInterval(3660), value: 200),
            // Inside the hour containing asOf, so its hour has not finished.
            StubSample(start: Self.epoch.addingTimeInterval(7260), value: 300),
        ]

        let buckets = bucketer.buckets(from: samples, window: Self.wideWindow, asOf: asOf)

        #expect(buckets.count == 2)
        #expect(buckets.map(\.value) == [100, 200])
    }

    @Test("a bucket must lie wholly inside the contest window")
    func bucketsOutsideTheWindowAreDropped() {
        let bucketer = HourlyBucketer(timeZone: Self.zone("UTC"))
        let window = DateInterval(
            start: Self.epoch.addingTimeInterval(3600),
            end: Self.epoch.addingTimeInterval(3 * 3600)
        )
        let samples = (0..<5).map { hour in
            StubSample(start: Self.epoch.addingTimeInterval(Double(hour) * 3600 + 60), value: 100)
        }

        let buckets = bucketer.buckets(from: samples, window: window, asOf: Self.farFuture)

        // Hours 1 and 2 are wholly inside; 0 starts before the window and 3
        // would end after it. "Wholly inside" rather than "starts inside" is the
        // conservative direction: a bucket that began before the window's last
        // hour would carry activity from after the contest ended.
        #expect(buckets.count == 2)
        #expect(buckets[0].bucketStart == Self.epoch.addingTimeInterval(3600))
        #expect(buckets[1].bucketStart == Self.epoch.addingTimeInterval(2 * 3600))
    }

    @Test("values are rounded to the two decimals the ledger stores")
    func valuesAreRounded() {
        let bucketer = HourlyBucketer(timeZone: Self.zone("UTC"))
        let sample = StubSample(
            start: Self.epoch.addingTimeInterval(20 * 60), duration: 3600, value: 100
        )

        let buckets = bucketer.buckets(
            from: [sample], window: Self.wideWindow, asOf: Self.farFuture
        )

        // Two thirds and one third of 100. Rounding here rather than letting
        // Postgres do it keeps what the client signed and what lands in the row
        // in agreement about what was claimed.
        #expect(buckets.map(\.value) == [66.67, 33.33])
    }

    @Test("nonsense samples are dropped rather than repaired")
    func nonsenseIsDropped() {
        let bucketer = HourlyBucketer(timeZone: Self.zone("UTC"))
        let samples = [
            StubSample(start: Self.epoch.addingTimeInterval(60), value: -50),
            StubSample(start: Self.epoch.addingTimeInterval(60), value: .nan),
            StubSample(start: Self.epoch.addingTimeInterval(60), value: .infinity),
            StubSample(start: Self.epoch.addingTimeInterval(60), duration: -600, value: 100),
        ]

        let buckets = bucketer.buckets(
            from: samples, window: Self.wideWindow, asOf: Self.farFuture
        )

        // A client that quietly repairs nonsense sends nonsense that looks fine.
        #expect(buckets.isEmpty)
    }

    @Test("an empty set of samples produces nothing")
    func emptyInputProducesNothing() {
        let bucketer = HourlyBucketer(timeZone: Self.zone("UTC"))
        let buckets = bucketer.buckets(
            from: [StubSample](), window: Self.wideWindow, asOf: Self.farFuture
        )
        #expect(buckets.isEmpty)
    }

    // ---------------------------------------------------------------------
    // Daylight saving
    // ---------------------------------------------------------------------
    @Test("a spring-forward day has twenty-three distinct buckets")
    func springForwardDay() {
        // 2027-03-14 in New York: the clock jumps 02:00 to 03:00, so the day is
        // 23 hours long. Local-hour alignment handles it by construction, which
        // is the thing worth pinning — an implementation that added 3600 seconds
        // to a local wall time would produce a duplicate or a gap here.
        let zone = Self.zone("America/New_York")
        let bucketer = HourlyBucketer(timeZone: zone)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone

        let dayStart = calendar.date(
            from: DateComponents(year: 2027, month: 3, day: 14, hour: 0)
        )!
        let dayEnd = calendar.date(
            from: DateComponents(year: 2027, month: 3, day: 15, hour: 0)
        )!

        #expect(dayEnd.timeIntervalSince(dayStart) == 23 * 3600)

        var starts: Set<Date> = []
        var cursor = dayStart
        while cursor < dayEnd {
            guard let interval = bucketer.bucket(containing: cursor) else { break }
            starts.insert(interval.start)
            cursor = interval.end
        }

        #expect(starts.count == 23)
    }

    @Test("a fall-back day has twenty-five distinct buckets")
    func fallBackDay() {
        // 2027-11-07 in New York: 01:00 happens twice, so the day is 25 hours.
        // Both repetitions are distinct instants and therefore distinct buckets,
        // which is what keeps the ledger's unique key from colliding on them.
        let zone = Self.zone("America/New_York")
        let bucketer = HourlyBucketer(timeZone: zone)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone

        let dayStart = calendar.date(
            from: DateComponents(year: 2027, month: 11, day: 7, hour: 0)
        )!
        let dayEnd = calendar.date(
            from: DateComponents(year: 2027, month: 11, day: 8, hour: 0)
        )!

        #expect(dayEnd.timeIntervalSince(dayStart) == 25 * 3600)

        var starts: Set<Date> = []
        var cursor = dayStart
        while cursor < dayEnd {
            guard let interval = bucketer.bucket(containing: cursor) else { break }
            starts.insert(interval.start)
            cursor = interval.end
        }

        #expect(starts.count == 25)
    }
}
