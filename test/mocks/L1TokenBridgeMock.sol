// SPDX-License-Identifier: AGPL-3.0-or-later

// Copyright (C) 2024 Dai Foundation
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity ^0.8.21;

interface TokenLike {
    function transferFrom(address, address, uint256) external;
}

contract L1TokenBridgeMock {
    address public immutable escrow;

    address public lastLocalToken;
    address public lastRemoteToken;
    address public lastTo;
    uint256 public lastAmount;
    uint32  public lastMinGasLimit;
    bytes32 public lastExtraDataHash;

    constructor(address _escrow) {
        escrow = _escrow;
    }

    function getEmptyDataHash() public view returns (bytes32) {
        return this.getDataHash("");
    }

    function getDataHash(bytes calldata data) public pure returns (bytes32) {
        return keccak256(data);
    }

    function bridgeERC20To(
        address        _localToken,
        address        _remoteToken,
        address        _to,
        uint256        _amount,
        uint32         _minGasLimit,
        bytes calldata _extraData
    ) public {
        lastLocalToken = _localToken;
        lastRemoteToken = _remoteToken;
        lastTo = _to;
        lastAmount = _amount;
        lastMinGasLimit = _minGasLimit;
        lastExtraDataHash = keccak256(_extraData);

        TokenLike(_localToken).transferFrom(msg.sender, escrow, _amount);
    }
}
