// SPDX-License-Identifier: AGPL-3.0-only
pragma experimental ABIEncoderV2;
pragma solidity ^0.7.6;

import {GovActions} from "dss-deploy/govActions.sol";
import {DSPause} from "ds-pause/pause.sol";

contract TestUtils {
    function uint2str(uint _i) internal pure returns (string memory _uintAsString) {
        if (_i == 0) {
            return "0";
        }
        uint j = _i;
        uint len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint k = len;
        while (_i != 0) {
            k = k-1;
            uint8 temp = (48 + uint8(_i - _i / 10 * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        return string(bstr);
    }
    function bytesToBytes32(bytes memory b, uint offset) private pure returns (bytes32) {
        bytes32 out;

        for (uint i = 0; i < 32; i++) {
            out |= bytes32(b[offset + i] & 0xFF) >> (i * 8);
        }
        return out;
    }

    function min(uint x, uint y) internal returns (uint) {
        if (x < y) return x;
        return y;
    }
}

interface Hevm {
    function warp(uint256) external;
    function roll(uint256) external;
    function store(address,bytes32,bytes32) external;
    function sign(uint,bytes32) external returns (uint8,bytes32,bytes32);
    function addr(uint) external returns (address);
    function ffi(string[] calldata) external returns (bytes memory);
}

// helpers to deal with ds-pause related beaurocracy
contract ProxyActions {
    DSPause pause;
    GovActions govActions;

    function rely(address from, address to) external {
        address      usr = address(govActions);
        bytes32      tag;  assembly { tag := extcodehash(usr) }
        bytes memory fax = abi.encodeWithSignature("rely(address,address)", from, to);
        uint         eta = block.timestamp;

        pause.plot(usr, tag, fax, eta);
        pause.exec(usr, tag, fax, eta);
    }

    function file(address who, bytes32 ilk, bytes32 what, uint256 data) external {
        address      usr = address(govActions);
        bytes32      tag;  assembly { tag := extcodehash(usr) }
        bytes memory fax = abi.encodeWithSignature("file(address,bytes32,bytes32,uint256)", who, ilk, what, data);
        uint         eta = block.timestamp;

        pause.plot(usr, tag, fax, eta);
        pause.exec(usr, tag, fax, eta);
    }

    function file(address who, bytes32 ilk, bytes32 what, address data) external {
        address      usr = address(govActions);
        bytes32      tag;  assembly { tag := extcodehash(usr) }
        bytes memory fax = abi.encodeWithSignature("file(address,bytes32,bytes32,address)", who, ilk, what, data);
        uint         eta = block.timestamp;

        pause.plot(usr, tag, fax, eta);
        pause.exec(usr, tag, fax, eta);
    }
}
