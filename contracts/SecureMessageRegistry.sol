// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract SecureMessageRegistry {
    mapping(address => bytes32) public keyHash;
    mapping(bytes32 => bytes32) public anchors;

    event KeyRegistered(address indexed user, bytes32 keyHash);
    event MessageAnchored(bytes32 indexed id, address indexed from, address indexed to, bytes32 hash, uint256 ts);

    function registerKey(bytes32 h) external {
        keyHash[msg.sender] = h;
        emit KeyRegistered(msg.sender, h);
    }

    function anchorMessage(bytes32 id, address to, bytes32 h) external {
        require(keyHash[msg.sender] != 0, "not registered");
        require(anchors[id] == 0, "already anchored");
        anchors[id] = h;
        emit MessageAnchored(id, msg.sender, to, h, block.timestamp);
    }

    function verify(bytes32 id, bytes32 h) external view returns (bool) {
        return anchors[id] == h;
    }
}
