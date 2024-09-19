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

import "dss-test/DssTest.sol";

import { L2FarmProxy } from "src/L2FarmProxy.sol";
import { L2FarmProxySpell } from "deploy/L2FarmProxySpell.sol";
import { FarmMock } from "test/mocks/FarmMock.sol";
import { GemMock } from "test/mocks/GemMock.sol";

contract L2FarmProxySpellTest is DssTest {

    GemMock rewardsToken;
    address stakingToken = address(444);
    address l2Proxy;
    L2FarmProxySpell l2Spell;
    address farm;

    event OwnerNominated(address newOwner);
    event PauseChanged(bool isPaused);
    event RewardsDurationUpdated(uint256 newDuration);
    event RewardsDistributionUpdated(address newRewardsDistribution);
    event Recovered(address token, uint256 amount);

    function setUp() public {
        rewardsToken = new GemMock(1_000_000 ether);
        farm = address(new FarmMock(address(rewardsToken), stakingToken));
        l2Proxy = address(new L2FarmProxy(farm));
        l2Spell = new L2FarmProxySpell();
    }

    function testL2ProxyFunctions() public {
        bool success;
        address usr = address(123);

        vm.expectEmit(true, true, true, true);
        emit Rely(usr);
        (success,) = address(l2Spell).delegatecall(abi.encodeCall(L2FarmProxySpell.rely, (l2Proxy, usr)));
        assertTrue(success);
        
        vm.expectEmit(true, true, true, true);
        emit Deny(usr);
        (success,) = address(l2Spell).delegatecall(abi.encodeCall(L2FarmProxySpell.deny, (l2Proxy, usr)));
        assertTrue(success);

        bytes32 what = "rewardThreshold";
        uint256 data = 456;
        vm.expectEmit(true, true, true, true);
        emit File(what, data);
        (success,) = address(l2Spell).delegatecall(abi.encodeCall(L2FarmProxySpell.file, (l2Proxy, what, data)));
        assertTrue(success);

        uint256 amount = 789 ether;
        rewardsToken.transfer(l2Proxy, amount);
        (success,) = address(l2Spell).delegatecall(abi.encodeCall(L2FarmProxySpell.recover, (l2Proxy, address(rewardsToken), usr, amount)));
        assertTrue(success);
        assertEq(rewardsToken.balanceOf(usr), amount);
    }

    function testFarmFunctions() public {
        bool success;
        address usr = address(123);

        vm.expectEmit(true, true, true, true);
        emit OwnerNominated(usr);
        (success,) = address(l2Spell).delegatecall(abi.encodeCall(L2FarmProxySpell.nominateNewOwner, (farm, usr)));
        assertTrue(success);

        vm.expectEmit(true, true, true, true);
        emit PauseChanged(true);
        (success,) = address(l2Spell).delegatecall(abi.encodeCall(L2FarmProxySpell.setPaused, (farm, true)));
        assertTrue(success);

        uint256 amount = 456 ether;
        vm.expectEmit(true, true, true, true);
        emit Recovered(address(rewardsToken), amount);
        (success,) = address(l2Spell).delegatecall(abi.encodeCall(L2FarmProxySpell.recoverERC20, (farm, address(rewardsToken), amount)));
        assertTrue(success);
    
        vm.expectEmit(true, true, true, true);
        emit RewardsDurationUpdated(amount);
        (success,) = address(l2Spell).delegatecall(abi.encodeCall(L2FarmProxySpell.setRewardsDuration, (farm, amount)));
        assertTrue(success);
    
        vm.expectEmit(true, true, true, true);
        emit RewardsDistributionUpdated(usr);
        (success,) = address(l2Spell).delegatecall(abi.encodeCall(L2FarmProxySpell.setRewardsDistribution, (farm, usr)));
        assertTrue(success);
    }

    // from https://ethereum.stackexchange.com/a/83577
    function _getRevertMsg(bytes memory _returnData) internal pure returns (string memory) {
        if (_returnData.length < 68) return 'Transaction reverted silently';
        assembly { _returnData := add(_returnData, 0x04) }
        return abi.decode(_returnData, (string));
    }

    function testInit() public {
        bool success;
        bytes memory response;

        (success, response) = address(l2Spell).delegatecall(abi.encodeCall(L2FarmProxySpell.init, (
            l2Proxy,
            address(0xb4d),
            stakingToken,
            farm,
            0,
            7 days
        )));
        assertFalse(success);
        assertEq(_getRevertMsg(response), "L2FarmProxySpell/rewards-token-mismatch");

        (success, response) = address(l2Spell).delegatecall(abi.encodeCall(L2FarmProxySpell.init, (
            l2Proxy,
            address(rewardsToken),
            stakingToken,
            address(0xb4d),
            0,
            7 days
        )));
        assertFalse(success);
        assertEq(_getRevertMsg(response), "L2FarmProxySpell/farm-mismatch");

        (success, response) = address(l2Spell).delegatecall(abi.encodeCall(L2FarmProxySpell.init, (
            l2Proxy,
            address(rewardsToken),
            address(0xb4d),
            farm,
            0,
            7 days
        )));
        assertFalse(success);
        assertEq(_getRevertMsg(response), "L2FarmProxySpell/farm-staking-token-mismatch");

        address badFarm = address(new FarmMock(address(rewardsToken), address(rewardsToken)));
        address badL2Proxy = address(new L2FarmProxy(badFarm));
        (success, response) = address(l2Spell).delegatecall(abi.encodeCall(L2FarmProxySpell.init, (
            badL2Proxy,
            address(rewardsToken),
            address(rewardsToken),
            badFarm,
            0,
            7 days
        )));
        assertFalse(success);
        assertEq(_getRevertMsg(response), "L2FarmProxySpell/rewards-token-same-as-staking-token");
        
        vm.expectEmit(true, true, true, true);
        emit File("rewardThreshold", 888);
        vm.expectEmit(true, true, true, true);
        emit RewardsDistributionUpdated(l2Proxy);
        vm.expectEmit(true, true, true, true);
        emit RewardsDurationUpdated(7 days);
        (success, response) = address(l2Spell).delegatecall(abi.encodeCall(L2FarmProxySpell.init, (
            l2Proxy,
            address(rewardsToken),
            stakingToken,
            farm,
            888,
            7 days
        )));
        assertTrue(success);
    }
}
