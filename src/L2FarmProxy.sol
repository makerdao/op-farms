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

interface FarmLike {
    function rewardsToken() external view returns (address);
    function notifyRewardAmount(uint256 reward) external;
}

interface GemLike {
    function balanceOf(address) external view returns (uint256);
    function transfer(address, uint256) external;
}

contract L2FarmProxy {
    mapping (address => uint256) public wards;
    uint256 public rewardThreshold;

    GemLike  public immutable rewardsToken;
    FarmLike public immutable farm;

    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event File(bytes32 indexed what, uint256 data);

    constructor(address _farm) {
        farm         = FarmLike(_farm);
        rewardsToken = GemLike(farm.rewardsToken());

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    modifier auth {
        require(wards[msg.sender] == 1, "L2FarmProxy/not-authorized");
        _;
    }

    function rely(address usr) external auth { wards[usr] = 1; emit Rely(usr); }
    function deny(address usr) external auth { wards[usr] = 0; emit Deny(usr); }

    function file(bytes32 what, uint256 data) external auth {
        if   (what == "rewardThreshold") rewardThreshold = data;
        else revert("L2FarmProxy/file-unrecognized-param");
        emit File(what, data);
    }

    // @notice Allow governance to recover potentially stuck tokens
    function recover(address token, address receiver, uint256 amount) external auth {
        GemLike(token).transfer(receiver, amount);
    }

    // @notice The transferred reward must exceed a minimum threshold to reduce the impact of 
    // calling this function too frequently in an attempt to reduce the rewardRate of the farm
    function forwardReward() external {
        uint256 reward = rewardsToken.balanceOf(address(this));
        require(reward > rewardThreshold, "L2FarmProxy/reward-too-small");
        rewardsToken.transfer(address(farm), reward);
        farm.notifyRewardAmount(reward);
    }
}
