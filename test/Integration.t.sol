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

import { Domain } from "dss-test/domains/Domain.sol";
import { OptimismDomain } from "dss-test/domains/OptimismDomain.sol";

import { TokenBridgeDeploy } from "lib/op-token-bridge/deploy/TokenBridgeDeploy.sol";
import { L2TokenBridgeSpell } from "lib/op-token-bridge/deploy/L2TokenBridgeSpell.sol";
import { L1TokenBridgeInstance } from "lib/op-token-bridge/deploy/L1TokenBridgeInstance.sol";
import { L2TokenBridgeInstance } from "lib/op-token-bridge/deploy/L2TokenBridgeInstance.sol";
import { TokenBridgeInit, BridgesConfig } from "lib/op-token-bridge/deploy/TokenBridgeInit.sol";
import { StakingRewards, StakingRewardsDeploy, StakingRewardsDeployParams } from "lib/endgame-toolkit/script/dependencies/StakingRewardsDeploy.sol";
import { VestedRewardsDistributionDeploy, VestedRewardsDistributionDeployParams } from "lib/endgame-toolkit/script/dependencies/VestedRewardsDistributionDeploy.sol";
import { VestedRewardsDistribution } from "lib/endgame-toolkit/src/VestedRewardsDistribution.sol";
import { GemMock } from "test/mocks/GemMock.sol";
import { DssVestMintableMock } from "test/mocks/DssVestMock.sol";
import { FarmProxyDeploy } from "deploy/FarmProxyDeploy.sol";
import { L2FarmProxySpell } from "deploy/L2FarmProxySpell.sol";
import { FarmProxyInit, ProxiesConfig } from "deploy/FarmProxyInit.sol";
import { L1FarmProxy } from "src/L1FarmProxy.sol";
import { L2FarmProxy } from "src/L2FarmProxy.sol";

interface L1RelayLike {
    function l2GovernanceRelay() external view returns (address);
}

contract IntegrationTest is DssTest {
    string config;
    Domain l1Domain;
    OptimismDomain l2Domain;

    // L1-side
    DssInstance dss;
    address PAUSE_PROXY;
    address escrow;
    address l1GovRelay;
    address l1Messenger;
    GemMock l1Token;
    address l1Bridge;
    L1FarmProxy l1Proxy;
    DssVestMintableMock vest;
    uint256 vestId;
    VestedRewardsDistribution vestedRewardsDistribution;

    // L2-side
    address l2GovRelay;
    address l2Messenger;
    GemMock l2Token;
    address l2Bridge;
    L2FarmProxy l2Proxy;
    StakingRewards farm;

    constructor() {
        vm.setEnv("FOUNDRY_ROOT_CHAINID", "1"); // used by ScriptTools to determine config path
        // Note: need to set the domains here instead of in setUp() to make sure their storages are actually persistent
        config = ScriptTools.loadConfig("config");

        l1Domain = new Domain(config, getChain("mainnet"));
        l2Domain = new OptimismDomain(config, getChain("base"), l1Domain);
    }

    function setupGateways() internal {
        l1Messenger = address(l2Domain.l1Messenger());
        l2Messenger = address(l2Domain.l2Messenger());

        l1GovRelay = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 3); // foundry increments a global nonce across domains
        l1Bridge = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 5);

        l2Domain.selectFork();
        L2TokenBridgeInstance memory l2BridgeInstance = TokenBridgeDeploy.deployL2Bridge({
            deployer:    address(this),
            l1GovRelay:  l1GovRelay,
            l1Bridge:    l1Bridge,
            l2Messenger: l2Messenger
        });
        l2Bridge = l2BridgeInstance.bridge;
        l2GovRelay = l2BridgeInstance.govRelay;

        assertEq(address(L2TokenBridgeSpell(l2BridgeInstance.spell).l2Bridge()), address(l2Bridge));

        l1Domain.selectFork();
        L1TokenBridgeInstance memory l1BridgeInstance = TokenBridgeDeploy.deployL1Bridge({
            deployer:    address(this),
            owner:       PAUSE_PROXY,
            l2GovRelay:  l2GovRelay,
            l2Bridge:    address(l2Bridge),
            l1Messenger: l1Messenger
        });
        assertEq(l1BridgeInstance.bridge, l1Bridge);
        assertEq(l1BridgeInstance.govRelay, l1GovRelay);
        escrow = l1BridgeInstance.escrow;

        l2Domain.selectFork();
        l2Token = new GemMock(0);
        l2Token.rely(l2GovRelay);
        l2Token.deny(address(this));

        address[] memory l1Tokens = new address[](1);
        l1Tokens[0] = address(l1Token);
        address[] memory l2Tokens = new address[](1);
        l2Tokens[0] = address(l2Token);

        BridgesConfig memory cfg = BridgesConfig({
            l1Messenger:   l1Messenger,
            l2Messenger:   l2Messenger,
            l1Tokens:      l1Tokens,
            l2Tokens:      l2Tokens,
            minGasLimit:   1_000_000,
            govRelayCLKey: "BASE_GOV_RELAY",
            escrowCLKey:   "BASE_ESCROW",
            l1BridgeCLKey: "BASE_TOKEN_BRIDGE"
        });

        l1Domain.selectFork();
        vm.startPrank(PAUSE_PROXY);
        TokenBridgeInit.initBridges(dss, l1BridgeInstance, l2BridgeInstance, cfg);
        vm.stopPrank();

    }

    function setUp() public {
        l1Domain.selectFork();
        l1Domain.loadDssFromChainlog();
        dss = l1Domain.dss();
        PAUSE_PROXY = dss.chainlog.getAddress("MCD_PAUSE_PROXY");

        vm.startPrank(PAUSE_PROXY);
        l1Token = new GemMock(100 ether);
        vest = new DssVestMintableMock(address(l1Token));
        l1Token.rely(address(vest));
        vest.file("cap", type(uint256).max);
        vm.stopPrank();

        setupGateways();

        l2Domain.selectFork();

        address stakingToken = address(new GemMock(100 ether));
        StakingRewardsDeployParams memory farmParams = StakingRewardsDeployParams({
            owner: l2GovRelay,
            stakingToken: stakingToken,
            rewardsToken: address(l2Token)
        });
        farm = StakingRewards(StakingRewardsDeploy.deploy(farmParams));

        l2Proxy = L2FarmProxy(FarmProxyDeploy.deployL2Proxy({
            deployer: address(this),
            owner:    l2GovRelay,
            farm:     address(farm)
        }));
        address l2Spell = FarmProxyDeploy.deployL2ProxySpell();

        l1Domain.selectFork();
        l1Proxy = L1FarmProxy(FarmProxyDeploy.deployL1Proxy({
            deployer:     address(this),
            owner:        PAUSE_PROXY,
            rewardsToken: address(l1Token),
            remoteToken:  address(l2Token),
            l2Proxy:      address(l2Proxy),
            l1Bridge:     l1Bridge
        }));

        VestedRewardsDistributionDeployParams memory distributionParams = VestedRewardsDistributionDeployParams({
            deployer:  address(this),
            owner:     PAUSE_PROXY,
            vest:      address(vest),
            rewards:   address(l1Proxy)
        });
        vestedRewardsDistribution = VestedRewardsDistribution(VestedRewardsDistributionDeploy.deploy(distributionParams));

        ProxiesConfig memory cfg = ProxiesConfig({
            vest:                      address(vest),
            vestTot:                   100 * 1e18,
            vestBgn:                   block.timestamp,
            vestTau:                   100 days,
            vestedRewardsDistribution: address(vestedRewardsDistribution),
            l1RewardsToken:            address(l1Token),
            l2RewardsToken:            address(l2Token),
            stakingToken:              stakingToken,
            l1Bridge:                  l1Bridge,
            minGasLimit:               1_000_000, // determined by running deploy/Estimate.s.sol and adding some margin // TODO: leave this comment?
            rewardThreshold:           1 ether,
            farm:                      address(farm),
            rewardsDuration:           1 days,
            relayMinGasLimit:          1_000_000,
            proxyChainlogKey:          "FARM_PROXY_TKA_TKB_ARB",
            distrChainlogKey:          "REWARDS_DISTRIBUTION_TKA_TKB_ARB"
        });

        vm.startPrank(PAUSE_PROXY);
        FarmProxyInit.initProxies(dss, l1GovRelay, address(l1Proxy), address(l2Proxy), l2Spell, cfg);
        vm.stopPrank();

        // test L1 side of initProxies
        vestId = vestedRewardsDistribution.vestId();
        assertEq(vest.usr(vestId),                                            cfg.vestedRewardsDistribution);
        assertEq(vest.bgn(vestId),                                            cfg.vestBgn);
        assertEq(vest.clf(vestId),                                            cfg.vestBgn);
        assertEq(vest.fin(vestId),                                            cfg.vestBgn + cfg.vestTau);
        assertEq(vest.tot(vestId),                                            cfg.vestTot);
        assertEq(vest.mgr(vestId),                                            address(0));
        assertEq(vest.res(vestId),                                            1);
        assertEq(l1Proxy.minGasLimit(),                                       cfg.minGasLimit);
        assertEq(l1Proxy.rewardThreshold(),                                   cfg.rewardThreshold);
        assertEq(dss.chainlog.getAddress("FARM_PROXY_TKA_TKB_ARB"),           address(l1Proxy));
        assertEq(dss.chainlog.getAddress("REWARDS_DISTRIBUTION_TKA_TKB_ARB"), cfg.vestedRewardsDistribution);

        l2Domain.relayFromHost(true);

        // test L2 side of initProxies
        assertEq(l2Proxy.rewardThreshold(),  cfg.rewardThreshold);
        assertEq(farm.rewardsDistribution(), address(l2Proxy));
        assertEq(farm.rewardsDuration(),     cfg.rewardsDuration);
    }

    function testDistribution() public {
        l1Domain.selectFork();
        uint256 rewardThreshold = l1Proxy.rewardThreshold();
        vm.warp(vest.bgn(vestId) + rewardThreshold * (vest.fin(vestId) - vest.bgn(vestId)) / vest.tot(vestId) + 1);
        uint256 amount = vest.unpaid(vestId);
        assertGt(amount, rewardThreshold);
        assertEq(l1Token.balanceOf(escrow), 0);

        vestedRewardsDistribution.distribute();

        assertEq(l1Token.balanceOf(escrow), amount);

        l2Domain.relayFromHost(true);

        assertEq(l2Token.balanceOf(address(l2Proxy)), amount);
    
        l2Proxy.forwardReward();

        assertEq(l2Token.balanceOf(address(l2Proxy)), 0);
        assertEq(l2Token.balanceOf(address(farm)), amount);
        assertEq(farm.rewardRate(), amount / farm.rewardsDuration());
    }
}
