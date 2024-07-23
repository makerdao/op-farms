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

interface GemLike {
    function approve(address, uint256) external;
    function transfer(address, uint256) external;
}

interface L1TokenGatewayLike {
    function bridgeERC20To(
        address _localToken,
        address _remoteToken,
        address _to,
        uint256 _amount,
        uint32 _minGasLimit,
        bytes calldata _extraData
    ) external;
}

contract L1FarmProxy {
    mapping (address => uint256) public wards;
    uint32  public minGasLimit;
    uint224 public rewardThreshold;

    address public immutable localToken;
    address public immutable remoteToken;
    address public immutable l2Proxy;
    L1TokenGatewayLike public immutable l1Gateway;

    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event File(bytes32 indexed what, uint256 data);
    event RewardAdded(uint256 reward);

    constructor(address _localToken, address _remoteToken, address _l2Proxy, address _l1Gateway) {
        localToken   = _localToken;
        remoteToken  = _remoteToken;
        l2Proxy      = _l2Proxy;
        l1Gateway    = L1TokenGatewayLike(_l1Gateway);

        GemLike(_localToken).approve(_l1Gateway, type(uint256).max);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    modifier auth {
        require(wards[msg.sender] == 1, "L1FarmProxy/not-authorized");
        _;
    }

    function rely(address usr) external auth { wards[usr] = 1; emit Rely(usr); }
    function deny(address usr) external auth { wards[usr] = 0; emit Deny(usr); }

    // @notice Validation of the `data` boundaries is outside the scope of this 
    // contract and is assumed to be carried out in the corresponding spell process
    function file(bytes32 what, uint256 data) external auth {
        if      (what == "minGasLimit")     minGasLimit     = uint32(data);
        else if (what == "rewardThreshold") rewardThreshold = uint224(data);
        else revert("L1FarmProxy/file-unrecognized-param");
        emit File(what, data);
    }

    // @notice Allow governance to recover potentially stuck tokens
    function recover(address token, address receiver, uint256 amount) external auth {
        GemLike(token).transfer(receiver, amount);
    }

    // @notice Send reward to L2 farm proxy
    function notifyRewardAmount(uint256 reward) external {
        (uint32 minGasLimit_, uint256 rewardThreshold_) = (minGasLimit, rewardThreshold);
        require(reward > rewardThreshold_, "L1FarmProxy/reward-too-small");

        l1Gateway.bridgeERC20To({
            _localToken:   localToken,
            _remoteToken:  remoteToken,
            _to :          l2Proxy,
            _amount :      reward,
            _minGasLimit:  minGasLimit_,
            _extraData :   bytes("")
        });

        emit RewardAdded(reward);
    }
}
