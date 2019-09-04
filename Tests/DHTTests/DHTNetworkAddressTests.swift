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

import XCTest

import DHT

public final class DHTNetworkAddressTests: XCTestCase {
    func testDHTIPv4AddressDescription() {
        let ipv4Octets: [UInt8] = [255, 128, 31, 6]
        let ipv4Address = DHTIPv4Address(Data(ipv4Octets))
        XCTAssertEqual(ipv4Address?.description, "255.128.31.6")
    }

    func testDHTIPv6AddressDescription() {
        let ipv6Octets: [UInt8] = [32, 1, 13, 184, 133, 163, 0, 0, 0, 0, 138, 46, 3, 112, 115, 52]
        let ipv6Address = DHTIPv6Address(Data(ipv6Octets))
        XCTAssertEqual(ipv6Address?.description, "2001:0db8:85a3:0000:0000:8a2e:0370:7334")
    }
}
