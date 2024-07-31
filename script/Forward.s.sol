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

import "forge-std/Script.sol";

import { ScriptTools } from "dss-test/ScriptTools.sol";
import { Domain } from "dss-test/domains/Domain.sol";

interface L2ProxyLike {
    function forwardReward() external;
}

// Run l2Proxy.forwardReward() to test deployement
contract Forward is Script {
    using stdJson for string;

    uint256 l2PrivKey = vm.envUint("L2_PRIVATE_KEY");

    function run() external {
        StdChains.Chain memory l1Chain = getChain(string(vm.envOr("L1", string("mainnet"))));
        StdChains.Chain memory l2Chain = getChain(string(vm.envOr("L2", string("base"))));
        vm.setEnv("FOUNDRY_ROOT_CHAINID", vm.toString(l1Chain.chainId)); // used by ScriptTools to determine config path
        string memory config = ScriptTools.loadConfig("config");
        string memory deps   = ScriptTools.loadDependencies();
        Domain l2Domain = new Domain(config, l2Chain);
        l2Domain.selectFork();
       
        address l2Proxy = deps.readAddress(".l2Proxy");

        vm.startBroadcast(l2PrivKey);
        L2ProxyLike(l2Proxy).forwardReward();
        vm.stopBroadcast();
    }
}
