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

import Foundation

public struct CRC32C: Hashable, Codable {
    public static let table: [UInt32] = {
        let polynomial: UInt32 = 0x82F6_3B78
        return (0..<256).map { index -> UInt32 in
            (0..<8).reduce(UInt32(index)) { remainder, _ -> UInt32 in
                if remainder % 2 == 0 {
                    return remainder >> 1
                } else {
                    return (remainder >> 1) ^ polynomial
                }
            }
        }
    }()

    public let value: UInt32

    public init(_ bytes: [UInt8]) {
        self.init(bytes: bytes)
    }

    public init(_ data: Data) {
        self.init(bytes: data)
    }

    public init<C: Collection>(bytes: C) where C.Element == UInt8 {
        self.value = CRC32C.checksum(bytes)
    }

    private static func checksum<C: Collection>(_ bytes: C) -> UInt32 where C.Element == UInt8 {
        return bytes.reduce(0xFFFF_FFFF) { crc, byte -> UInt32 in
            let nLookupIndex: Int = Int(UInt8(crc & 0xFF) ^ byte)
            return (crc >> 8) ^ CRC32C.table[nLookupIndex]
        } ^ 0xFFFF_FFFF
    }
}
