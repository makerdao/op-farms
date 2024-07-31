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
import { VestedRewardsDistributionDeploy, VestedRewardsDistributionDeployParams } from "lib/endgame-toolkit/script/dependencies/VestedRewardsDistributionDeploy.sol";
import { StakingRewardsDeploy, StakingRewardsDeployParams } from "lib/endgame-toolkit/script/dependencies/StakingRewardsDeploy.sol";
import { DssVestMintableMock } from "test/mocks/DssVestMock.sol";
import { FarmProxyDeploy } from "deploy/FarmProxyDeploy.sol";

interface L1GovernanceRelayLike {
    function l2GovernanceRelay() external view returns (address);
}

interface ChainLogLike {
    function getAddress(bytes32) external view returns (address);
}

interface AuthLike {
    function rely(address usr) external;
}

contract DeployProxy is Script {
    using stdJson for string;

    uint256 l1PrivKey = vm.envUint("L1_PRIVATE_KEY");
    uint256 l2PrivKey = vm.envUint("L2_PRIVATE_KEY");
    address l1Deployer = vm.addr(l1PrivKey);
    address l2Deployer = vm.addr(l2PrivKey);

    StdChains.Chain l1Chain;
    StdChains.Chain l2Chain;
    string config;
    string deps;
    Domain l1Domain;
    Domain l2Domain;
    ChainLogLike chainlog;
    address l1GovRelay;
    address l2GovRelay;
    address owner;
    address l1Bridge;
    address vest;
    address stakingToken;
    address l1RewardsToken;
    address l2RewardsToken;
    address l1Proxy;
    address vestedRewardsDistribution;
    address farm;
    address l2Proxy;

    function run() external {
        l1Chain = getChain(string(vm.envOr("L1", string("mainnet"))));
        l2Chain = getChain(string(vm.envOr("L2", string("base"))));
        vm.setEnv("FOUNDRY_ROOT_CHAINID", vm.toString(l1Chain.chainId)); // used by ScriptTools to determine config path
        config = ScriptTools.loadConfig("config");
        deps   = ScriptTools.loadDependencies();
        l1Domain = new Domain(config, l1Chain);
        l2Domain = new Domain(config, l2Chain);
        l1Domain.selectFork();

        chainlog = ChainLogLike(l1Domain.readConfigAddress("chainlog"));
        l1GovRelay = chainlog.getAddress("BASE_GOV_RELAY"); // TODO: get as input?
        l2GovRelay = L1GovernanceRelayLike(payable(l1GovRelay)).l2GovernanceRelay(); // TODO: does it need to be payable?
        l1Bridge = chainlog.getAddress("BASE_TOKEN_BRIDGE");
        stakingToken = l2Domain.readConfigAddress("stakingToken");
        l1RewardsToken = l1Domain.readConfigAddress("rewardsToken");
        l2RewardsToken = l2Domain.readConfigAddress("rewardsToken");

        if (keccak256(bytes(l1Chain.chainAlias)) == keccak256("mainnet")) {
            owner = chainlog.getAddress("MCD_PAUSE_PROXY");
            vest = l1Domain.readConfigAddress("vest");
        } else {
            owner = l1Deployer;
            vm.startBroadcast(l1PrivKey);
            vest = address(new DssVestMintableMock(l1RewardsToken));
            DssVestMintableMock(vest).file("cap", type(uint256).max);
            AuthLike(l1RewardsToken).rely(address(vest));
            vm.stopBroadcast();
        }

        // L2 deployment

        StakingRewardsDeployParams memory farmParams = StakingRewardsDeployParams({
            owner: l2GovRelay,
            stakingToken: stakingToken,
            rewardsToken: l2RewardsToken
        });
        l2Domain.selectFork();
        vm.startBroadcast(l2PrivKey);
        farm = StakingRewardsDeploy.deploy(farmParams);
        l2Proxy = FarmProxyDeploy.deployL2Proxy(l2Deployer, l2GovRelay, farm);
        vm.stopBroadcast();

        // L1 deployment

        l1Domain.selectFork();
        vm.startBroadcast(l1PrivKey);
        l1Proxy = FarmProxyDeploy.deployL1Proxy(
            l1Deployer,
            owner,
            l1RewardsToken,
            l2RewardsToken,
            l2Proxy,
            l1Bridge
        );
        VestedRewardsDistributionDeployParams memory distributionParams = VestedRewardsDistributionDeployParams({
            deployer:  l1Deployer,
            owner:     owner,
            vest:      vest,
            rewards:   l1Proxy
        });
        vestedRewardsDistribution = (VestedRewardsDistributionDeploy.deploy(distributionParams));
        vm.stopBroadcast();

        // Export contract addresses

        // TODO: load the existing json so this is not required
        ScriptTools.exportContract("deployed", "chainlog", deps.readAddress(".chainlog"));
        ScriptTools.exportContract("deployed", "l2ProxySpell", deps.readAddress(".l2ProxySpell"));
        ScriptTools.exportContract("deployed", "l1GovRelay", deps.readAddress(".l1GovRelay"));
        ScriptTools.exportContract("deployed", "l2GovRelay", deps.readAddress(".l2GovRelay"));

        ScriptTools.exportContract("deployed", "farm", farm);
        ScriptTools.exportContract("deployed", "l2Proxy", l2Proxy);        
        ScriptTools.exportContract("deployed", "l2RewardsToken", l2RewardsToken);
        ScriptTools.exportContract("deployed", "stakingToken", stakingToken);
        ScriptTools.exportContract("deployed", "l1Proxy", l1Proxy);
        ScriptTools.exportContract("deployed", "vest", vest);
        ScriptTools.exportContract("deployed", "vestedRewardsDistribution", vestedRewardsDistribution);
        ScriptTools.exportContract("deployed", "l1RewardsToken", l1RewardsToken);
        ScriptTools.exportContract("deployed", "l1Bridge", l1Bridge);
    }
}
