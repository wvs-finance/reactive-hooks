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

/// @dev Insert `id` between `prevNode` and `nextNode`. Internal — no validation.
function _insert(DLL storage self, bytes32 prevNode, bytes32 id, bytes32 nextNode) {
    self.nodes[id][PREV] = prevNode;
    self.nodes[id][NEXT] = nextNode;
    self.nodes[prevNode][NEXT] = id;
    self.nodes[nextNode][PREV] = id;
    self.size++;
}

/// @dev Validates `id` is not sentinel and does not already exist. Used by all insert functions.
function _validateInsert(DLL storage self, bytes32 id) view {
    if (id == SENTINEL) revert InvalidNode();
    if (contains(self, id)) revert NodeAlreadyExists(id);
}

/// @dev Returns the successor of `id`, or SENTINEL if `id` is the tail. Reverts if `id` is not in the list.
function next(DLL storage self, bytes32 id) view returns (bytes32) {
    if (!contains(self, id)) revert NodeDoesNotExist(id);
    return self.nodes[id][NEXT];
}

/// @dev Returns the predecessor of `id`, or SENTINEL if `id` is the head. Reverts if `id` is not in the list.
function prev(DLL storage self, bytes32 id) view returns (bytes32) {
    if (!contains(self, id)) revert NodeDoesNotExist(id);
    return self.nodes[id][PREV];
}

/// @dev Remove `id` from the list. Reverts if `id` is sentinel or not in the list.
function remove(DLL storage self, bytes32 id) {
    if (id == SENTINEL) revert InvalidNode();
    if (!contains(self, id)) revert NodeDoesNotExist(id);
    bytes32 prevNode = self.nodes[id][PREV];
    bytes32 nextNode = self.nodes[id][NEXT];
    self.nodes[prevNode][NEXT] = nextNode;
    self.nodes[nextNode][PREV] = prevNode;
    self.nodes[id][PREV] = SENTINEL;
    self.nodes[id][NEXT] = SENTINEL;
    self.size--;
}

/// @dev Append `id` to the end of the list.
function pushBack(DLL storage self, bytes32 id) {
    _validateInsert(self, id);
    _insert(self, self.nodes[SENTINEL][PREV], id, SENTINEL);
}

/// @dev Prepend `id` to the front of the list.
function pushFront(DLL storage self, bytes32 id) {
    _validateInsert(self, id);
    _insert(self, SENTINEL, id, self.nodes[SENTINEL][NEXT]);
}
