import Foundation

enum AssertionCounterDecoder {
    static func decode(from assertion: Data) throws -> UInt32 {
        var reader = CBORReader(data: assertion)
        let count = try reader.readContainerCount(expectedMajorType: 5, name: "top-level map")

        var authenticatorData: Data?
        for _ in 0..<count {
            let key = try reader.readTextString()
            if key == "authenticatorData" {
                guard authenticatorData == nil else {
                    throw CounterDecodingError.duplicateAuthenticatorData
                }
                authenticatorData = try reader.readByteString()
            } else {
                try reader.skipValue()
            }
        }
        guard reader.isAtEnd else {
            throw CounterDecodingError.trailingBytes
        }
        guard let authenticatorData else {
            throw CounterDecodingError.missingAuthenticatorData
        }
        guard authenticatorData.count >= 37 else {
            throw CounterDecodingError.shortAuthenticatorData(authenticatorData.count)
        }

        let bytes = [UInt8](authenticatorData)
        return bytes[33...36].reduce(UInt32.zero) {
            ($0 << 8) | UInt32($1)
        }
    }
}

private enum CounterDecodingError: LocalizedError {
    case truncated
    case unsupportedIndefiniteLength
    case unexpectedMajorType(expected: Int, actual: Int)
    case invalidUTF8
    case excessiveNesting
    case excessiveLength
    case duplicateAuthenticatorData
    case missingAuthenticatorData
    case shortAuthenticatorData(Int)
    case trailingBytes

    var errorDescription: String? {
        switch self {
        case .truncated:
            "the CBOR assertion ended early"
        case .unsupportedIndefiniteLength:
            "indefinite-length CBOR is not supported by App Attest assertions"
        case .unexpectedMajorType(let expected, let actual):
            "expected CBOR major type \(expected), found \(actual)"
        case .invalidUTF8:
            "a CBOR map key was not valid UTF-8"
        case .excessiveNesting:
            "the CBOR assertion was nested too deeply"
        case .excessiveLength:
            "a CBOR length cannot be represented locally"
        case .duplicateAuthenticatorData:
            "the assertion contained authenticatorData more than once"
        case .missingAuthenticatorData:
            "the assertion did not contain authenticatorData"
        case .shortAuthenticatorData(let count):
            "authenticatorData had \(count) bytes; at least 37 are required"
        case .trailingBytes:
            "the assertion had bytes after its top-level CBOR value"
        }
    }
}

private struct CBORReader {
    private let bytes: [UInt8]
    private var offset = 0

    init(data: Data) {
        self.bytes = [UInt8](data)
    }

    var isAtEnd: Bool {
        offset == bytes.count
    }

    mutating func readContainerCount(
        expectedMajorType: Int,
        name _: String
    ) throws -> Int {
        let head = try readHead()
        guard head.majorType == expectedMajorType else {
            throw CounterDecodingError.unexpectedMajorType(
                expected: expectedMajorType,
                actual: head.majorType
            )
        }
        guard let count = Int(exactly: head.argument) else {
            throw CounterDecodingError.excessiveLength
        }
        return count
    }

    mutating func readTextString() throws -> String {
        let data = try readData(majorType: 3)
        guard let value = String(data: data, encoding: .utf8) else {
            throw CounterDecodingError.invalidUTF8
        }
        return value
    }

    mutating func readByteString() throws -> Data {
        try readData(majorType: 2)
    }

    mutating func skipValue(depth: Int = 0) throws {
        guard depth <= 16 else {
            throw CounterDecodingError.excessiveNesting
        }
        let head = try readHead()
        guard let count = Int(exactly: head.argument) else {
            throw CounterDecodingError.excessiveLength
        }

        switch head.majorType {
        case 0, 1, 7:
            return
        case 2, 3:
            try advance(by: count)
        case 4:
            for _ in 0..<count {
                try skipValue(depth: depth + 1)
            }
        case 5:
            for _ in 0..<count {
                try skipValue(depth: depth + 1)
                try skipValue(depth: depth + 1)
            }
        case 6:
            try skipValue(depth: depth + 1)
        default:
            throw CounterDecodingError.unexpectedMajorType(expected: 0, actual: head.majorType)
        }
    }

    private mutating func readData(majorType: Int) throws -> Data {
        let head = try readHead()
        guard head.majorType == majorType else {
            throw CounterDecodingError.unexpectedMajorType(
                expected: majorType,
                actual: head.majorType
            )
        }
        guard let count = Int(exactly: head.argument) else {
            throw CounterDecodingError.excessiveLength
        }
        guard count <= bytes.count - offset else {
            throw CounterDecodingError.truncated
        }
        let value = Data(bytes[offset..<(offset + count)])
        offset += count
        return value
    }

    private mutating func readHead() throws -> (majorType: Int, argument: UInt64) {
        let initial = try readByte()
        let majorType = Int(initial >> 5)
        let additional = initial & 0x1f

        let argument: UInt64
        switch additional {
        case 0...23:
            argument = UInt64(additional)
        case 24:
            argument = UInt64(try readByte())
        case 25:
            argument = try readUnsigned(byteCount: 2)
        case 26:
            argument = try readUnsigned(byteCount: 4)
        case 27:
            argument = try readUnsigned(byteCount: 8)
        case 31:
            throw CounterDecodingError.unsupportedIndefiniteLength
        default:
            throw CounterDecodingError.truncated
        }
        return (majorType, argument)
    }

    private mutating func readUnsigned(byteCount: Int) throws -> UInt64 {
        var value = UInt64.zero
        for _ in 0..<byteCount {
            value = (value << 8) | UInt64(try readByte())
        }
        return value
    }

    private mutating func readByte() throws -> UInt8 {
        guard offset < bytes.count else {
            throw CounterDecodingError.truncated
        }
        defer { offset += 1 }
        return bytes[offset]
    }

    private mutating func advance(by count: Int) throws {
        guard count >= 0, count <= bytes.count - offset else {
            throw CounterDecodingError.truncated
        }
        offset += count
    }
}
