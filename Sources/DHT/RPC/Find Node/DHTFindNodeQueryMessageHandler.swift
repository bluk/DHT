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

public struct DHTFindNodeQueryMessageHandler: DHTRemoteQueryMessageHandler {
    public static let queryMethodName = KRPCMessage.MethodName.findNode

    public init() {}

    /// Notify a find node query was received
    public func handle(
        _ message: KRPCMessage,
        from remoteAddress: DHTNetworkAddress,
        node: DHTLocalNode,
        completionHandler: @escaping (Result<Void, Error>) -> Void
    ) {
        assert(message.y == .query)
        assert(message.q == DHTFindNodeQueryMessageHandler.queryMethodName)

        guard let targetIDData = message.a?.targetID, let targetNodeID = NodeID(data: targetIDData) else {
            // TODO: Send an error back
            completionHandler(Result.failure(DHTNodeError.receivedMalformedMessage(message)))
            return
        }
        var isIPv4Address = false
        var isIPv6Address = false

        switch remoteAddress {
        case let .hostPort(host: host, port: _):
            switch host {
            case .ipv4:
                isIPv4Address = true
            case .ipv6:
                isIPv6Address = true
            case .name:
                break
            }
        }

        var nodesData = Data()
        let isIPv4Wanted = (message.a?.want?.contains(KRPCArguments.WantValue.n4) ?? false) || (message.a?.want == nil && isIPv4Address)
        if isIPv4Wanted {
            let nearestNeighbors = node.ipv4RoutingTable.findNearestNeighbors(
                nodeID: targetNodeID,
                bootstrapNodes: [],
                includeAllBootstrapNodes: false
            )

            if node.ipv4RoutingTable.nodeIDPivot == targetNodeID {
                // do nothing
            } else {
                nearestNeighbors.forEach { remoteID in
                    guard let nodeID = remoteID.nodeID,
                        let addressData = remoteID.address.makeContactData(addressResolver: node.addressResolver) else {
                        return
                    }
                    var contactData = Data()
                    contactData.append(nodeID.value)
                    contactData.append(addressData)
                    nodesData.append(contactData)
                }
            }
        }

        var nodes6Data = Data()
        let isIPv6Wanted = message.a?.want?.contains(KRPCArguments.WantValue.n6) ?? false || (message.a?.want == nil && isIPv6Address)
        if isIPv6Wanted {
            let nearestNeighbors = node.ipv6RoutingTable.findNearestNeighbors(
                nodeID: targetNodeID,
                bootstrapNodes: [],
                includeAllBootstrapNodes: false
            )

            if node.ipv6RoutingTable.nodeIDPivot == targetNodeID {
                // do nothing
            } else {
                nearestNeighbors.forEach { remoteID in
                    guard let nodeID = remoteID.nodeID,
                        let addressData = remoteID.address.makeContactData(addressResolver: node.addressResolver) else {
                        return
                    }
                    var contactData = Data()
                    contactData.append(nodeID.value)
                    contactData.append(addressData)
                    nodes6Data.append(contactData)
                }
            }
        }

        let args: KRPCArguments
        switch remoteAddress {
        case let .hostPort(host: host, port: _):
            switch host {
            case .ipv4, .name:
                args = KRPCArguments(
                    nodeID: node.ipv4RoutingTable.nodeIDPivot,
                    nodes: isIPv4Wanted ? nodesData : nil,
                    nodes6: isIPv6Wanted ? nodes6Data : nil
                )
            case .ipv6:
                args = KRPCArguments(
                    nodeID: node.ipv6RoutingTable.nodeIDPivot,
                    nodes: isIPv4Wanted ? nodesData : nil,
                    nodes6: isIPv6Wanted ? nodes6Data : nil
                )
            }
        }

        let findNodeResponse = KRPCMessage(
            transactionID: message.t,
            responseArguments: args,
            clientVersion: node.config.clientVersion
        )
        let remoteID = DHTRemoteNode.Identifier(address: remoteAddress, nodeID: message.queryingNodeID)
        node.send(
            message: findNodeResponse,
            to: remoteID,
            queryTimeout: nil,
            queryCompletionHandler: nil,
            completionHandler: completionHandler
        )
    }
}
