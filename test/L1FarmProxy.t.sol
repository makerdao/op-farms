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

import { L1FarmProxy } from "src/L1FarmProxy.sol";
import { GemMock } from "test/mocks/GemMock.sol";
import { L1TokenBridgeMock } from "test/mocks/L1TokenBridgeMock.sol";

contract L1FarmProxyTest is DssTest {

    GemMock localToken;
    L1FarmProxy l1Proxy;
    address bridge;
    address escrow = address(0xeee);
    address l2Proxy = address(0x222);
    address remoteToken = address(0x333);

    event RewardAdded(uint256 rewards);

    function setUp() public {
        bridge = address(new L1TokenBridgeMock(escrow));
        localToken = new GemMock(1_000_000 ether);
        l1Proxy = new L1FarmProxy(address(localToken), remoteToken, l2Proxy, bridge);
    }

    function testConstructor() public {
        vm.expectEmit(true, true, true, true);
        emit Rely(address(this));
        L1FarmProxy p = new L1FarmProxy(address(localToken), remoteToken, l2Proxy, bridge);
        
        assertEq(p.localToken(), address(localToken));
        assertEq(p.remoteToken(), remoteToken);
        assertEq(p.l2Proxy(), l2Proxy);
        assertEq(address(p.l1Bridge()), bridge);
        assertEq(localToken.allowance(address(p), bridge), type(uint256).max);
        assertEq(p.wards(address(this)), 1);
    }

    function testAuth() public {
        checkAuth(address(l1Proxy), "L1FarmProxy");
    }

    function testFile() public {
        checkFileUint(address(l1Proxy), "L1FarmProxy", ["minGasLimit", "rewardThreshold"]);
    }

    function testAuthModifiers() public virtual {
        l1Proxy.deny(address(this));

        checkModifier(address(l1Proxy), string(abi.encodePacked("L1FarmProxy", "/not-authorized")), [
            l1Proxy.recover.selector
        ]);
    }

    function testRecover() public {
        address receiver = address(0x123);
        localToken.transfer(address(l1Proxy), 1 ether);

        assertEq(localToken.balanceOf(receiver), 0);
        assertEq(localToken.balanceOf(address(l1Proxy)), 1 ether);

        l1Proxy.recover(address(localToken), receiver, 1 ether);

        assertEq(localToken.balanceOf(receiver), 1 ether);
        assertEq(localToken.balanceOf(address(l1Proxy)), 0);
    }

    function testNotifyRewardAmount() public {
        l1Proxy.file("rewardThreshold", 100 ether);

        vm.expectRevert("L1FarmProxy/reward-too-small");
        l1Proxy.notifyRewardAmount(100 ether);

        localToken.transfer(address(l1Proxy), 101 ether);
        assertEq(localToken.balanceOf(escrow), 0);
        assertEq(localToken.balanceOf(address(l1Proxy)), 101 ether);

        vm.expectEmit(true, true, true, true);
        emit RewardAdded(101 ether);
        l1Proxy.notifyRewardAmount(101 ether);

        assertEq(localToken.balanceOf(escrow), 101 ether);
        assertEq(localToken.balanceOf(address(l1Proxy)), 0);
    }
}
