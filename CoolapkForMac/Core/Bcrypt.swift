import Foundation

/// A dependency free implementation of the bcrypt password hashing function
/// (EksBlowfish, Provos & Mazieres) used by the Coolapk `X-App-Token` v2 scheme.
enum BCrypt {
    private static let alphabet: [UInt8] =
        Array("./ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789".utf8)

    private static let reverseTable: [Int] = {
        var table = [Int](repeating: -1, count: 256)
        for (index, byte) in alphabet.enumerated() { table[Int(byte)] = index }
        return table
    }()

    // MARK: - Base64 (bcrypt alphabet)

    static func base64Decode(_ input: [UInt8]) -> [UInt8] {
        var output: [UInt8] = []
        output.reserveCapacity(input.count * 3 / 4)
        var bits = 0
        var bitCount = 0
        for byte in input {
            let value = reverseTable[Int(byte)]
            if value < 0 { continue }
            bits = (bits << 6) | value
            bitCount += 6
            if bitCount >= 8 {
                bitCount -= 8
                output.append(UInt8((bits >> bitCount) & 0xFF))
            }
        }
        return output
    }

    static func base64Encode(_ input: [UInt8]) -> String {
        var output: [UInt8] = []
        output.reserveCapacity((input.count * 4 + 2) / 3 + 1)
        var bits = 0
        var bitCount = 0
        for byte in input {
            bits = (bits << 8) | Int(byte)
            bitCount += 8
            while bitCount >= 6 {
                bitCount -= 6
                output.append(alphabet[(bits >> bitCount) & 0x3F])
            }
        }
        if bitCount > 0 {
            output.append(alphabet[(bits << (6 - bitCount)) & 0x3F])
        }
        return String(decoding: output, as: UTF8.self)
    }

    // MARK: - Blowfish state

    struct State {
        var p = BlowfishTables.p
        var s = BlowfishTables.s0 + BlowfishTables.s1 + BlowfishTables.s2 + BlowfishTables.s3

        @inline(__always)
        func f(_ x: UInt32) -> UInt32 {
            let a = Int((x >> 24) & 0xFF)
            let b = Int((x >> 16) & 0xFF)
            let c = Int((x >> 8) & 0xFF)
            let d = Int(x & 0xFF)
            return ((s[a] &+ s[256 + b]) ^ s[512 + c]) &+ s[768 + d]
        }

        @inline(__always)
        mutating func encipher(_ xl: inout UInt32, _ xr: inout UInt32) {
            var l = xl
            var r = xr
            var i = 0
            while i < 16 {
                l ^= p[i]
                r ^= f(l)
                swap(&l, &r)
                i += 1
            }
            swap(&l, &r)
            r ^= p[16]
            l ^= p[17]
            xl = l
            xr = r
        }
    }

    @inline(__always)
    private static func stream2word(_ data: [UInt8], _ offset: inout Int) -> UInt32 {
        var temp: UInt32 = 0
        let count = data.count
        var index = offset
        for _ in 0..<4 {
            temp = (temp << 8) | UInt32(data[index])
            index += 1
            if index == count { index = 0 }
        }
        offset = index
        return temp
    }

    /// One `ExpandKey` pass. A `nil` salt skips the salt XOR stage (the `ExpandKey(state, 0, key)`
    /// step of the EksBlowfish schedule) while keeping the chaining values alive.
    private static func expandKey(_ state: inout State, salt: [UInt8]?, key: [UInt8]) {
        var keyOffset = 0
        var i = 0
        while i < 18 {
            state.p[i] ^= stream2word(key, &keyOffset)
            i += 1
        }

        var l: UInt32 = 0
        var r: UInt32 = 0
        var saltOffset = 0
        i = 0
        while i < 18 {
            if let salt {
                l ^= stream2word(salt, &saltOffset)
                r ^= stream2word(salt, &saltOffset)
            }
            state.encipher(&l, &r)
            state.p[i] = l
            state.p[i + 1] = r
            i += 2
        }

        var box = 0
        while box < 4 {
            var k = 0
            while k < 256 {
                if let salt {
                    l ^= stream2word(salt, &saltOffset)
                    r ^= stream2word(salt, &saltOffset)
                }
                state.encipher(&l, &r)
                state.s[box * 256 + k] = l
                state.s[box * 256 + k + 1] = r
                k += 2
            }
            box += 1
        }
    }

    private static func expensiveBlowfishSetup(cost: Int, salt: [UInt8], key: [UInt8]) -> State {
        var state = State()
        expandKey(&state, salt: salt, key: key)
        let rounds = 1 << cost
        var i = 0
        while i < rounds {
            expandKey(&state, salt: nil, key: key)
            expandKey(&state, salt: nil, key: salt)
            i += 1
        }
        return state
    }

    // MARK: - Public API

    /// Exposed for self tests: standard Blowfish key schedule followed by one encryption.
    static func blowfishEncrypt(block: (UInt32, UInt32), key: [UInt8]) -> (UInt32, UInt32) {
        var state = State()
        expandKey(&state, salt: nil, key: key)
        var left = block.0
        var right = block.1
        state.encipher(&left, &right)
        return (left, right)
    }

    /// Hashes `password` using an explicit 29 character bcrypt salt such as `$2y$10$abcdefghijklmnopqrstuv`.
    /// Returns a 60 character hash string.
    static func hash(password: [UInt8], salt saltString: String) -> String? {
        let saltBytes = Array(saltString.utf8)
        guard saltBytes.count == 29,
              saltBytes[0] == UInt8(ascii: "$"),
              saltBytes[1] == UInt8(ascii: "2"),
              saltBytes[3] == UInt8(ascii: "$") else { return nil }
        guard let cost = Int(String(decoding: saltBytes[4..<6], as: UTF8.self)), cost >= 4, cost <= 31 else { return nil }
        let salt = Array(base64Decode(Array(saltBytes[7..<29])).prefix(16))
        guard salt.count == 16 else { return nil }

        var result = "$2y$"
        result += String(format: "%02d", cost)
        result += "$"
        result += base64Encode(salt)
        result += base64Encode(Array(rawHash(password: password, salt: salt, cost: cost).prefix(23)))
        return result
    }

    /// The raw 24 byte bcrypt ciphertext, exposed for self tests.
    static func rawHash(password: [UInt8], salt: [UInt8], cost: Int) -> [UInt8] {
        var key = password
        key.append(0)

        var state = expensiveBlowfishSetup(cost: cost, salt: salt, key: key)

        let magic = Array("OrpheanBeholderScryDoubt".utf8) + [0]
        var words = [UInt32](repeating: 0, count: 6)
        var offset = 0
        for i in 0..<6 { words[i] = stream2word(magic, &offset) }

        var round = 0
        while round < 64 {
            var left: UInt32 = 0
            var right: UInt32 = 0
            var pair = 0
            while pair < 6 {
                left = words[pair]
                right = words[pair + 1]
                state.encipher(&left, &right)
                words[pair] = left
                words[pair + 1] = right
                pair += 2
            }
            round += 1
        }

        var output = [UInt8]()
        output.reserveCapacity(24)
        for word in words {
            output.append(UInt8((word >> 24) & 0xFF))
            output.append(UInt8((word >> 16) & 0xFF))
            output.append(UInt8((word >> 8) & 0xFF))
            output.append(UInt8(word & 0xFF))
        }
        return output
    }
}
