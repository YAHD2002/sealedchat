// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract SealedChatRegistry {
    address public immutable relayer;
    mapping(bytes32 => bytes32) public keyOf;   // sha256(username) => key fingerprint
    mapping(uint256 => bytes32) public anchors; // message id => ciphertext hash

    event KeyRegistered(bytes32 indexed userId, bytes32 keyHash);
    event MessageAnchored(uint256 indexed id, bytes32 indexed fromId, bytes32 indexed toId, bytes32 hash, uint256 ts);

    constructor(address _relayer) {
        relayer = _relayer;
    }

    modifier onlyRelayer() {
        require(msg.sender == relayer, "not relayer");
        _;
    }

    function registerKey(bytes32 userId, bytes32 h) external onlyRelayer {
        require(keyOf[userId] == 0, "already registered");
        keyOf[userId] = h;
        emit KeyRegistered(userId, h);
    }

    function anchorMessage(uint256 id, bytes32 fromId, bytes32 toId, bytes32 h) external onlyRelayer {
        require(keyOf[fromId] != 0 && keyOf[toId] != 0, "unknown user");
        require(anchors[id] == 0, "already anchored");
        anchors[id] = h;
        emit MessageAnchored(id, fromId, toId, h, block.timestamp);
    }
}
