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

public struct DHTPingQueryMessageHandler: DHTRemoteQueryMessageHandler {
    public static let queryMethodName = KRPCMessage.MethodName.ping

    public init() {}

    /// Notify a ping query was received
    public func handle(
        _ message: KRPCMessage,
        from remoteAddress: DHTNetworkAddress,
        node: DHTLocalNode,
        completionHandler: @escaping (Result<Void, Error>) -> Void
    ) {
        assert(message.y == .query)
        assert(message.q == DHTPingQueryMessageHandler.queryMethodName)

        let args: KRPCArguments
        switch remoteAddress {
        case let .hostPort(host: host, port: _):
            switch host {
            case .ipv4, .name:
                args = KRPCArguments(nodeID: node.ipv4RoutingTable.nodeIDPivot)
            case .ipv6:
                args = KRPCArguments(nodeID: node.ipv6RoutingTable.nodeIDPivot)
            }
        }

        let pingResponse = KRPCMessage(
            transactionID: message.t,
            responseArguments: args,
            clientVersion: node.config.clientVersion
        )
        let remoteID = DHTRemoteNode.Identifier(address: remoteAddress, nodeID: message.queryingNodeID)
        node.send(
            message: pingResponse,
            to: remoteID,
            queryTimeout: nil,
            queryCompletionHandler: nil,
            completionHandler: completionHandler
        )
    }
}
