//  Copyright 2019 Bryant Luk
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.

import struct Foundation.Data

internal enum DataError: Error, CustomStringConvertible, CustomDebugStringConvertible {
    case cannotConvertByteToHexadecimalValue

    public var description: String {
        switch self {
        case .cannotConvertByteToHexadecimalValue:
            return "Cannot convert byte to hexadecimal value"
        }
    }

    public var debugDescription: String {
        switch self {
        case .cannotConvertByteToHexadecimalValue:
            return "DataError Cannot convert byte to hexadecimal value"
        }
    }
}

internal extension Data {
    init?(fromHexEncodedString string: String) {
        var strBuffer = ""
        var isEven = false
        var bytes: [UInt8] = []
        do {
            try string.forEach { char in
                strBuffer.append(char)
                if isEven {
                    guard let convertedByte = UInt8(strBuffer, radix: 16) else {
                        throw DataError.cannotConvertByteToHexadecimalValue
                    }
                    bytes.append(convertedByte)
                    isEven = false
                    strBuffer = ""
                } else {
                    isEven = true
                }
            }
        } catch {
            return nil
        }
        self.init(bytes: bytes, count: bytes.count)
    }
}

internal extension Data {
    var hexadecimalString: String {
        return self
            .compactMap { byte in
                if byte <= 15 {
                    return "0" + String(byte, radix: 16)
                }
                return String(byte, radix: 16)
            }
            .joined()
    }
}

internal extension Data {
    static func randomizeUpTo(_ data: Data, isClosedRange: Bool) -> Data {
        var randomData = Data(count: data.count)
        var lowerThanMax = false
        for index in 0..<data.count {
            let indexedValue: UInt8 = data[index]
            let randomValue: UInt8
            if lowerThanMax {
                randomValue = UInt8.random(in: 0...UInt8.max)
            } else {
                randomValue = UInt8.random(in: 0...indexedValue)
            }
            randomData[index] = randomValue
            if randomValue < indexedValue {
                lowerThanMax = true
            }
        }
        if !lowerThanMax, !isClosedRange {
            return randomizeUpTo(data, isClosedRange: isClosedRange)
        }
        return randomData
    }

    func twosComplement() -> Data {
        let bytes = compactMap { byte in ~byte }
        var oneBit = Data(count: count)
        oneBit[count - 1] = 0x01
        let (data, _) = Data(bytes: bytes, count: bytes.count).addBits(oneBit)
        return data
    }

    func shiftBits(by shiftAmount: Int) -> Data {
        var addHighBit = false
        var data = Data(count: count)
        for index in 0..<count {
            let isLowerBitSet = (self[index] & 0x01) == 1
            data[index] = self[index] >> shiftAmount
            if addHighBit {
                data[index] |= 0x80
            }
            addHighBit = isLowerBitSet
        }
        return data
    }

    func addBits(_ other: Data) -> (Data, Bool) {
        let bigger: Data
        let smaller: Data
        if self.count < other.count {
            bigger = other
            smaller = self
        } else {
            bigger = self
            smaller = other
        }

        var data = Data(count: bigger.count)
        var carryOver: UInt8 = 0
        let offsetIndex = bigger.count - smaller.count
        for index in (0..<smaller.count).reversed() {
            let (partialValue, overflow) = smaller[index].addingReportingOverflow(bigger[index + offsetIndex])
            let (finalValue, carryOverOverflow) = partialValue.addingReportingOverflow(carryOver)
            data[index + offsetIndex] = finalValue
            if carryOverOverflow || overflow {
                carryOver = 1
            } else {
                carryOver = 0
            }
        }

        for index in (smaller.count..<bigger.count).reversed() {
            let (finalValue, carryOverOverflow) = bigger[index].addingReportingOverflow(carryOver)
            data[index + offsetIndex] = finalValue
            if carryOverOverflow {
                carryOver = 1
            } else {
                carryOver = 0
            }
        }

        return (data, carryOver == 1)
    }
}
