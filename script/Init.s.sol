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
import { MCD, DssInstance } from "dss-test/MCD.sol";
import { FarmProxyInit, ProxiesConfig } from "deploy/FarmProxyInit.sol";
import { L2FarmProxySpell } from "deploy/L2FarmProxySpell.sol";

interface L2GovernanceRelayLike {
    function relay(address, bytes calldata) external;
}

contract Init is Script {
    using stdJson for string;

    uint256 l1PrivKey = vm.envUint("L1_PRIVATE_KEY");

    StdChains.Chain l1Chain;
    StdChains.Chain l2Chain;
    string config;
    string deps;
    Domain l1Domain;
    Domain l2Domain;
    DssInstance dss;
    address l1GovRelay;
    address l2GovRelay;

    function run() external {
        l1Chain = getChain(string(vm.envOr("L1", string("mainnet"))));
        l2Chain = getChain(string(vm.envOr("L2", string("base"))));
        vm.setEnv("FOUNDRY_ROOT_CHAINID", vm.toString(l1Chain.chainId)); // used by ScriptTools to determine config path
        config = ScriptTools.loadConfig("config");
        deps   = ScriptTools.loadDependencies();
        l1Domain = new Domain(config, l1Chain);
        l2Domain = new Domain(config, l2Chain);
        l1Domain.selectFork();

        dss = MCD.loadFromChainlog(deps.readAddress(".chainlog"));

        l1GovRelay = deps.readAddress(".l1GovRelay");
        l2GovRelay = deps.readAddress(".l2GovRelay");

        address l2Proxy = deps.readAddress(".l2Proxy");
        address l2ProxySpell = deps.readAddress(".l2ProxySpell");
        address l2RewardsToken = deps.readAddress(".l2RewardsToken");
        address stakingToken = deps.readAddress(".stakingToken");
        address farm = deps.readAddress(".farm");
        uint224 rewardThreshold = 0;
        uint256 rewardsDuration = 1 days;

        ProxiesConfig memory cfg = ProxiesConfig({
            vest:                      deps.readAddress(".vest"),
            vestTot:                   100 ether,
            vestBgn:                   block.timestamp,
            vestTau:                   100 days,
            vestedRewardsDistribution: deps.readAddress(".vestedRewardsDistribution"),
            l1RewardsToken:            deps.readAddress(".l1RewardsToken"),
            l2RewardsToken:            l2RewardsToken,
            stakingToken:              stakingToken,
            l1Bridge:                  deps.readAddress(".l1Bridge"),
            minGasLimit:               1_000_000,
            rewardThreshold:           rewardThreshold,
            farm:                      farm,
            rewardsDuration:           rewardsDuration,
            initMinGasLimit:           1_000_000,
            proxyChainlogKey:          "FARM_PROXY_TKA_TKB_BASE", // Note: need to change this when non base (relevant for testing only as in production this is run in the spell)
            distrChainlogKey:          "REWARDS_DIST_TKA_TKB_BASE" // Note: need to change this when non base (relevant for testing only as in production this is run in the spell)
        });

        vm.startBroadcast(l1PrivKey);
        FarmProxyInit.initProxies(
            dss,
            l1GovRelay,
            deps.readAddress(".l1Proxy"),
            l2Proxy,
            l2ProxySpell,
            cfg
        );
        vm.stopBroadcast();
    }
}
