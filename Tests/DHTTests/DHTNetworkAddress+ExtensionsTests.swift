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

import BTMetainfo

import DHT

public final class DHTNetworkAddressExtensionsTests: XCTestCase {
    func testDHTIPv4AddressValidNodeID_0() {
        let ipv4Octets: [UInt8] = [124, 31, 75, 21]
        guard let ipv4Address = DHTIPv4Address(Data(ipv4Octets)) else {
            XCTFail("Could not generate IPv4Address with \(ipv4Octets)")
            return
        }

        guard let nodeID = NodeID(value: "5fbfbff10c5d6a4ec8a88e4c6ab4c28b95eee401") else {
            XCTFail("Could not create nodeID")
            return
        }
        XCTAssertTrue(ipv4Address.isValidNodeID(nodeID), "\(ipv4Address) did not validate \(nodeID)")
    }

    func testDHTIPv4AddressValidNodeID_1() {
        let ipv4Octets: [UInt8] = [21, 75, 31, 124]
        guard let ipv4Address = DHTIPv4Address(Data(ipv4Octets)) else {
            XCTFail("Could not generate IPv4Address with \(ipv4Octets)")
            return
        }

        guard let nodeID = NodeID(value: "5a3ce9c14e7a08645677bbd1cfe7d8f956d53256") else {
            XCTFail("Could not create nodeID")
            return
        }
        XCTAssertTrue(ipv4Address.isValidNodeID(nodeID), "\(ipv4Address) did not validate \(nodeID)")
    }

    func testDHTIPv4AddressValidNodeID_2() {
        let ipv4Octets: [UInt8] = [65, 23, 51, 170]
        guard let ipv4Address = DHTIPv4Address(Data(ipv4Octets)) else {
            XCTFail("Could not generate IPv4Address with \(ipv4Octets)")
            return
        }

        guard let nodeID = NodeID(value: "a5d43220bc8f112a3d426c84764f8c2a1150e616") else {
            XCTFail("Could not create nodeID")
            return
        }
        XCTAssertTrue(ipv4Address.isValidNodeID(nodeID), "\(ipv4Address) did not validate \(nodeID)")
    }

    func testDHTIPv4AddressValidNodeID_3() {
        let ipv4Octets: [UInt8] = [84, 124, 73, 14]
        guard let ipv4Address = DHTIPv4Address(Data(ipv4Octets)) else {
            XCTFail("Could not generate IPv4Address with \(ipv4Octets)")
            return
        }

        guard let nodeID = NodeID(value: "1b0321dd1bb1fe518101ceef99462b947a01ff41") else {
            XCTFail("Could not create nodeID")
            return
        }
        XCTAssertTrue(ipv4Address.isValidNodeID(nodeID), "\(ipv4Address) did not validate \(nodeID)")
    }

    func testDHTIPv4AddressValidNodeID_4() {
        let ipv4Octets: [UInt8] = [43, 213, 53, 83]
        guard let ipv4Address = DHTIPv4Address(Data(ipv4Octets)) else {
            XCTFail("Could not generate IPv4Address with \(ipv4Octets)")
            return
        }

        guard let nodeID = NodeID(value: "e56f6cbf5b7c4be0237986d5243b87aa6d51305a") else {
            XCTFail("Could not create nodeID")
            return
        }
        XCTAssertTrue(ipv4Address.isValidNodeID(nodeID), "\(ipv4Address) did not validate \(nodeID)")
    }

    func testDHTIPv4AddressValidRandomNodeID() {
        var ipv4Octets: [UInt8] = []
        for _ in 0..<4 {
            ipv4Octets.append(UInt8.random(in: UInt8.min...UInt8.max))
        }
        guard let ipv4Address = DHTIPv4Address(Data(ipv4Octets)) else {
            XCTFail("Could not generate IPv4Address with \(ipv4Octets)")
            return
        }

        let generatedNodeID = ipv4Address.makeNodeID()
        XCTAssertTrue(ipv4Address.isValidNodeID(generatedNodeID), "\(ipv4Address) did not validate \(generatedNodeID)")
    }

    func testDHTIPv6AddressMakeValidRandomNodeID() {
        var ipv6Octets: [UInt8] = []
        for _ in 0..<16 {
            ipv6Octets.append(UInt8.random(in: UInt8.min...UInt8.max))
        }
        guard let ipv6Address = DHTIPv6Address(Data(ipv6Octets)) else {
            XCTFail("Could not generate IPv6Address with \(ipv6Octets)")
            return
        }

        let generatedNodeID = ipv6Address.makeNodeID()
        XCTAssertTrue(ipv6Address.isValidNodeID(generatedNodeID), "\(ipv6Address) did not validate \(generatedNodeID)")
    }
}
