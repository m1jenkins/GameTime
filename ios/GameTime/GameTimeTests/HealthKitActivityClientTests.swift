import HealthKit
import XCTest

@testable import GameTime

final class HealthKitActivityClientTests: XCTestCase {
  func testInstantaneousSampleAtStartIsIncludedAndAtEndIsExcluded()
    throws
  {
    let start = Date(timeIntervalSince1970: 1_785_888_000)
    let end = start.addingTimeInterval(3_600)
    let window = DateInterval(start: start, end: end)
    let samples = [
      try makeInstantaneousSample(at: start, value: 101),
      try makeInstantaneousSample(at: end, value: 202),
    ]

    let converted = HealthKitStepSampleAdapter.samples(
      from: samples,
      overlapping: window
    )

    let sample = try XCTUnwrap(converted.first)
    XCTAssertEqual(converted.count, 1)
    XCTAssertEqual(sample.start, start)
    XCTAssertEqual(sample.end, start)
    XCTAssertEqual(sample.value, 101)
  }

  func testStatisticsPlannerGroupsOnlyContiguousEqualIntervals() {
    let start = Date(timeIntervalSince1970: 1_785_888_000)
    let intervals = [
      DateInterval(
        start: start,
        end: start.addingTimeInterval(3_600)
      ),
      DateInterval(
        start: start.addingTimeInterval(3_600),
        end: start.addingTimeInterval(7_200)
      ),
      DateInterval(
        start: start.addingTimeInterval(7_200),
        end: start.addingTimeInterval(9_000)
      ),
      DateInterval(
        start: start.addingTimeInterval(10_800),
        end: start.addingTimeInterval(12_600)
      ),
    ]

    let plans = HealthKitStepStatisticsPlanner.plans(
      for: intervals
    )

    XCTAssertEqual(plans.count, 3)
    XCTAssertEqual(plans.map(\.intervalSeconds), [3_600, 1_800, 1_800])
    XCTAssertEqual(plans.map(\.intervals.count), [2, 1, 1])
  }

  func testBoundaryFilteringKeepsSamplesPairedWithTheirOwnDescriptors()
    throws
  {
    let start = Date(timeIntervalSince1970: 1_785_888_000)
    let end = start.addingTimeInterval(3_600)
    let window = DateInterval(start: start, end: end)
    let excluded = try makeSample(
      start: start.addingTimeInterval(-60),
      end: start,
      value: 999
    )
    let included = try makeSample(
      start: start.addingTimeInterval(60),
      end: start.addingTimeInterval(120),
      value: 123
    )

    let pairs = HealthKitStepSampleAdapter.pairedSamples(
      from: [excluded, included],
      overlapping: window
    )

    let pair = try XCTUnwrap(pairs.first)
    XCTAssertEqual(pairs.count, 1)
    XCTAssertEqual(pair.descriptor.value, 123)
    XCTAssertEqual(
      pair.sample.quantity.doubleValue(for: .count()),
      123
    )
  }

  func testMergedDeviceStatisticAvoidsPhoneAndWatchDoubleCount() throws {
    let start = Date(timeIntervalSince1970: 1_785_888_000)
    let interval = DateInterval(
      start: start,
      end: start.addingTimeInterval(3_600)
    )
    let phone = makeDescriptor(
      start: start.addingTimeInterval(60),
      end: start.addingTimeInterval(1_800),
      value: 1_000,
      source: "com.apple.health.phone",
      model: "iPhone"
    )
    let watch = makeDescriptor(
      start: start.addingTimeInterval(300),
      end: start.addingTimeInterval(2_100),
      value: 900,
      source: "com.apple.health.watch",
      model: "Watch"
    )

    let buckets = HealthKitStepStatisticsAdapter.buckets(
      statistics: [
        ActivityStepStatistic(
          start: interval.start,
          end: interval.end,
          // HealthKit has merged the overlapping device sources.
          value: 1_100
        )
      ],
      expectedIntervals: [interval],
      deviceSamples: [phone, watch]
    )

    let bucket = try XCTUnwrap(buckets.first)
    XCTAssertEqual(buckets.count, 1)
    XCTAssertEqual(bucket.value, 1_100)
    XCTAssertEqual(bucket.provenance, .device)
    XCTAssertEqual(bucket.sampleCount, 2)
    XCTAssertNil(bucket.sourceBundleIdentifier)
    XCTAssertNil(bucket.deviceModel)
  }

  func testNonDeviceSamplesCannotProduceAnAdmissibleDeviceBucket() {
    let start = Date(timeIntervalSince1970: 1_785_888_000)
    let interval = DateInterval(
      start: start,
      end: start.addingTimeInterval(3_600)
    )
    let thirdParty = makeDescriptor(
      start: start.addingTimeInterval(60),
      end: start.addingTimeInterval(120),
      value: 500,
      source: "com.example.steps",
      model: "Watch"
    )

    let buckets = HealthKitStepStatisticsAdapter.buckets(
      statistics: [
        ActivityStepStatistic(
          start: interval.start,
          end: interval.end,
          value: 500
        )
      ],
      expectedIntervals: [interval],
      deviceSamples: [thirdParty]
    )

    XCTAssertTrue(buckets.isEmpty)
  }

  private func makeInstantaneousSample(
    at date: Date,
    value: Double
  ) throws -> HKQuantitySample {
    try makeSample(
      start: date,
      end: date,
      value: value
    )
  }

  private func makeSample(
    start: Date,
    end: Date,
    value: Double
  ) throws -> HKQuantitySample {
    let stepType = try XCTUnwrap(
      HKObjectType.quantityType(forIdentifier: .stepCount)
    )
    return HKQuantitySample(
      type: stepType,
      quantity: HKQuantity(unit: .count(), doubleValue: value),
      start: start,
      end: end
    )
  }

  private func makeDescriptor(
    start: Date,
    end: Date,
    value: Double,
    source: String,
    model: String
  ) -> ActivityStepSample {
    ActivityStepSample(
      start: start,
      end: end,
      value: value,
      wasUserEntered: false,
      sourceBundleIdentifier: source,
      deviceManufacturer: "Apple Inc.",
      deviceModel: model
    )
  }
}
