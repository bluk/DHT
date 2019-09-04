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

import Dispatch

extension DHT {
    public struct Transaction {
        public let id: Int
        public let remoteID: DHTRemoteNode.Identifier
        public let queryMessage: KRPCMessage
        public let sent: DispatchTime
        let completionHandler: (Result<KRPCMessage, Error>) -> Void
        let timeoutWorkItem: DispatchWorkItem
    }
}

extension DHT.Transaction: Hashable {
    public static func == (lhs: DHT.Transaction, rhs: DHT.Transaction) -> Bool {
        return lhs.id == rhs.id
            && lhs.remoteID == rhs.remoteID
            && lhs.sent == rhs.sent
            && lhs.queryMessage == rhs.queryMessage
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.id)
        hasher.combine(self.remoteID)
    }
}

extension DHT.Transaction: CustomDebugStringConvertible {
    public var debugDescription: String {
        return "DHT.Transaction(id: \(id), remoteID: \(remoteID), queryMessage: \(queryMessage), sent: \(sent))"
    }
}
