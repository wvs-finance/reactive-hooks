// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @dev Sentinel node — represents "no node" / list boundary. bytes32(0) is never a valid node ID.
bytes32 constant SENTINEL = bytes32(0);

/// @dev Direction constants for the nested mapping.
bool constant PREV = false;
bool constant NEXT = true;

/// @dev A doubly-linked list of bytes32 node IDs using the sentinel-mapping pattern.
/// @dev Design reference: vittominacori/solidity-linked-list (MIT).
struct DLL {
    uint256 size;
    mapping(bytes32 => mapping(bool => bytes32)) nodes;
}

error NodeAlreadyExists(bytes32 id);
error NodeDoesNotExist(bytes32 id);
error InvalidNode();

/// @dev Returns true if `id` is a member of the list.
function contains(DLL storage self, bytes32 id) view returns (bool) {
    if (id == SENTINEL) return false;
    return self.nodes[id][NEXT] != SENTINEL
        || self.nodes[id][PREV] != SENTINEL
        || self.nodes[SENTINEL][NEXT] == id;
}

/// @dev Returns the number of nodes in the list.
function size(DLL storage self) view returns (uint256) {
    return self.size;
}

/// @dev Returns true if the list has no nodes.
function isEmpty(DLL storage self) view returns (bool) {
    return self.size == 0;
}

/// @dev Returns the first node, or SENTINEL if the list is empty.
function head(DLL storage self) view returns (bytes32) {
    return self.nodes[SENTINEL][NEXT];
}

/// @dev Returns the last node, or SENTINEL if the list is empty.
function tail(DLL storage self) view returns (bytes32) {
    return self.nodes[SENTINEL][PREV];
}
