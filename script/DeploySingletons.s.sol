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
import { FarmProxyDeploy } from "deploy/FarmProxyDeploy.sol";

interface ChainLogLike {
    function getAddress(bytes32) external view returns (address);
}

interface L1GovernanceRelayLike {
    function l2GovernanceRelay() external view returns (address);
}

contract DeploySingletons is Script {

    uint256 l2PrivKey = vm.envUint("L2_PRIVATE_KEY");

    StdChains.Chain l1Chain;
    StdChains.Chain l2Chain;
    string config;
    Domain l1Domain;
    Domain l2Domain;
    address deployer;
    ChainLogLike chainlog;
    address l1GovRelay;
    address l2GovRelay;
    address l2Spell;

    function run() external {
        l1Chain = getChain(string(vm.envOr("L1", string("mainnet"))));
        l2Chain = getChain(string(vm.envOr("L2", string("base"))));
        vm.setEnv("FOUNDRY_ROOT_CHAINID", vm.toString(l1Chain.chainId)); // used by ScriptTools to determine config path
        config = ScriptTools.loadConfig("config");
        l1Domain = new Domain(config, l1Chain);
        l2Domain = new Domain(config, l2Chain);

        l1Domain.selectFork();

        chainlog = ChainLogLike(l1Domain.readConfigAddress("chainlog"));
        l1GovRelay = chainlog.getAddress(l2Domain.readConfigBytes32FromString("govRelayCLKey"));
        l2GovRelay = L1GovernanceRelayLike(payable(l1GovRelay)).l2GovernanceRelay();

        l2Domain.selectFork();

        vm.startBroadcast(l2PrivKey);
        l2Spell = FarmProxyDeploy.deployL2ProxySpell();
        vm.stopBroadcast();

        // Export contract addresses

        ScriptTools.exportContract("deployed", "chainlog", address(chainlog));
        ScriptTools.exportContract("deployed", "l2ProxySpell", l2Spell);
        ScriptTools.exportContract("deployed", "l1GovRelay", l1GovRelay);
        ScriptTools.exportContract("deployed", "l2GovRelay", l2GovRelay);
    }
}
