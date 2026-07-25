import Foundation
import XCTest
@testable import GameTimeConformance

final class AssertionCounterDecoderTests: XCTestCase {
    func testDecodesBigEndianCounterAndAllowsExtensionBytes() throws {
        let assertion = makeAssertion(counter: 66_051, extensionBytes: [0xaa, 0xbb])

        XCTAssertEqual(try AssertionCounterDecoder.decode(from: assertion), 66_051)
    }

    func testRejectsShortAuthenticatorData() {
        let assertion = makeAssertion(authenticatorData: Data(repeating: 0, count: 36))

        XCTAssertThrowsError(try AssertionCounterDecoder.decode(from: assertion))
    }

    func testRejectsTrailingCBORBytes() {
        var assertion = makeAssertion(counter: 1)
        assertion.append(0)

        XCTAssertThrowsError(try AssertionCounterDecoder.decode(from: assertion))
    }
}

func makeAssertion(
    counter: UInt32,
    extensionBytes: [UInt8] = []
) -> Data {
    var authenticatorData = Data(repeating: 0, count: 37)
    authenticatorData[32] = 0x01
    authenticatorData[33] = UInt8((counter >> 24) & 0xff)
    authenticatorData[34] = UInt8((counter >> 16) & 0xff)
    authenticatorData[35] = UInt8((counter >> 8) & 0xff)
    authenticatorData[36] = UInt8(counter & 0xff)
    authenticatorData.append(contentsOf: extensionBytes)
    return makeAssertion(authenticatorData: authenticatorData)
}

private func makeAssertion(authenticatorData: Data) -> Data {
    var bytes = Data([0xa2])
    appendCBORText("signature", to: &bytes)
    appendCBORBytes(Data([0x30, 0x01, 0x00]), to: &bytes)
    appendCBORText("authenticatorData", to: &bytes)
    appendCBORBytes(authenticatorData, to: &bytes)
    return bytes
}

private func appendCBORText(_ value: String, to data: inout Data) {
    let bytes = Data(value.utf8)
    appendCBORHeader(majorType: 3, count: bytes.count, to: &data)
    data.append(bytes)
}

private func appendCBORBytes(_ value: Data, to data: inout Data) {
    appendCBORHeader(majorType: 2, count: value.count, to: &data)
    data.append(value)
}

private func appendCBORHeader(majorType: UInt8, count: Int, to data: inout Data) {
    precondition(count < 256)
    if count < 24 {
        data.append((majorType << 5) | UInt8(count))
    } else {
        data.append((majorType << 5) | 24)
        data.append(UInt8(count))
    }
}
