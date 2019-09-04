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

import BTMetainfo

#if canImport(CommonCrypto)

import CommonCrypto

extension DHT {
    public func rotateSecretTokens() {
        let newSecretToken = InfoHash.random(in: InfoHash.min..<InfoHash.max)
        self.secretTokens = (newSecretToken, secretTokens.0)
    }

    public func isValid(token: Data, from networkAddress: DHTNetworkAddress) -> Bool {
        guard let contactData = networkAddress.makeContactData(addressResolver: self.addressResolver) else {
            return false
        }

        for secretToken in [secretTokens.0, secretTokens.1] {
            var validToken = Data(contactData)
            validToken.append(secretToken.value)
            let hashedValue = withUnsafePointer(to: validToken) { dataPtr -> Data in
                var hash = Data(count: Int(CC_SHA256_DIGEST_LENGTH))
                hash.withUnsafeMutableBytes { hashPtr -> Void in
                    guard let baseAddress = hashPtr.baseAddress else {
                        fatalError("Could not get base memory address")
                    }
                    CC_SHA256(dataPtr, UInt32(validToken.count), baseAddress.assumingMemoryBound(to: UInt8.self))
                }
                return hash
            }

            if hashedValue == token {
                return true
            }
        }

        return false
    }

    public func generateToken(for networkAddress: DHTNetworkAddress) -> Data {
        guard let contactData = networkAddress.makeContactData(addressResolver: self.addressResolver) else {
            fatalError("Could not get contact info.")
        }

        var validToken = Data(contactData)
        validToken.append(secretTokens.0.value)
        let hashedValue = withUnsafePointer(to: validToken) { dataPtr -> Data in
            var hash = Data(count: Int(CC_SHA256_DIGEST_LENGTH))
            hash.withUnsafeMutableBytes { hashPtr -> Void in
                guard let baseAddress = hashPtr.baseAddress else {
                    fatalError("Could not get base memory address")
                }
                CC_SHA256(dataPtr, UInt32(validToken.count), baseAddress.assumingMemoryBound(to: UInt8.self))
            }
            return hash
        }

        return hashedValue
    }
}

#endif
