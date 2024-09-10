# Op Farms

## Overview

This repository implements a mechanism to distribute rewards vested in a [DssVest](https://github.com/makerdao/dss-vest) contract on L1 to users staking tokens in a [StakingRewards](https://github.com/makerdao/endgame-toolkit/blob/master/src/synthetix/StakingRewards.sol) farm on an OP stack L2. It uses the [Op Token Bridge](https://github.com/makerdao/op-token-bridge) to transfer the rewards from L1 to L2.

## Contracts

- `L1FarmProxy.sol` - Proxy to the farm on the L1 side. Receives the token reward (expected to come from a [`VestedRewardDistribution`](https://github.com/makerdao/endgame-toolkit/blob/master/src/VestedRewardsDistribution.sol) contract) and transfers it cross-chain to the `L2FarmProxy`. An instance of `L1FarmProxy` must be deployed for each supported pair of staking and rewards token.
- `L2FarmProxy.sol` - Proxy to the farm on the L2 side. Receives the token reward (expected to be bridged from the `L1FarmProxy`) and forwards it to the [StakingRewards](https://github.com/makerdao/endgame-toolkit/blob/master/src/synthetix/StakingRewards.sol) farm where it gets distributed to stakers. An instance of `L2FarmProxy` must be deployed for each supported pair of staking and rewards token.

### External dependencies

- The L2 staking tokens and the L1 and L2 rewards tokens are not provided as part of this repository. It is assumed that only simple, regular ERC20 tokens will be used. In particular, the supported tokens are assumed to revert on failure (instead of returning false) and do not execute any hook on transfer.
- [`DssVest`](https://github.com/makerdao/dss-vest) is used to vest the rewards token on L1.
- [`VestedRewardDistribution`](https://github.com/makerdao/endgame-toolkit/blob/master/src/VestedRewardsDistribution.sol) is used to vest the rewards tokens from `DssVest`, transfer them to the `L1FarmProxy` and trigger the bridging of the tokens.
- The [Op Token Bridge](https://github.com/makerdao/op-token-bridge) is used to bridge the tokens from L1 to L2. 
- The [escrow contract](https://github.com/makerdao/op-token-bridge/blob/dev/src/Escrow.sol) is used by the Op Token Bridge to hold the bridged tokens on L1.
- [`StakingRewards`](https://github.com/makerdao/endgame-toolkit/blob/master/src/synthetix/StakingRewards.sol) is used to distribute the bridged rewards to stakers on L2.
- The [`L1GovernanceRelay`](https://github.com/makerdao/op-token-bridge/blob/dev/src/L1GovernanceRelay.sol) & [`L2GovernanceRelay`](https://github.com/makerdao/op-token-bridge/blob/dev/src/L2GovernanceRelay.sol) allow governance to exert admin control over the deployed L2 contracts.

## Expected flow
- Once the vested amount of rewards tokens exceeds `L1FarmProxy.rewardThreshold`, a keeper calls `VestedRewardDistribution.distribute()` to vest the rewards and have them bridged to L2.
- Once the bridged amount of rewards tokens exceeds `L2FarmProxy.rewardThreshold`, anyone (e.g. a keeper or an L2 staker) can call `L2FarmProxy.forwardReward()` to distribute the rewards to the L2 farm.

Note that `L1FarmProxy.rewardThreshold` should be sufficiently large to reduce the frequency of cross-chain transfers (thereby saving keepers gas). `L2FarmProxy.rewardThreshold` must also be sufficiently large to limit the reduction of the farm's rate of rewards distribution. Consider also choosing `L2FarmProxy.rewardThreshold <= L1FarmProxy.rewardThreshold` so that the bridged rewards can be promptly distributed to the farm. In the initialization library, these two variables are assigned the same value.

Note that the L2 Farm's reward rate might not be perfectly constant, even if the `L1FarmProxy` and `L2FarmProxy` reward thresholds are set to the same value. With the cross-chain setup there are several ways that can lead to non-constant reward rates. Therefor the following should be taken into consideration:
* The L2 StakingReward's reward rate (essentially `L2Proxy.rewardThreshold / StakingRewards.rewardsDuration`) should be close to the DssVest's minting rate. The `rewardThreshold` and `rewardsDuration` conﬁgurations should be chosen to satisfy that.
* Keepers should monitor and call `VestedRewardsDistribution.distribute` on L1 and `L2FarmProxy.forwardReward` whenever their reward thresholds are reached.
* L2 sequencer downtimes or other bridging delays can lead to delayed L2 distribution.
* Failed L2ProxyFarm reward token bridging transactions should be monitored and retried.

## Deployment

### Declare env variables

Add the required env variables listed in `.env.example` to your `.env` file, and run `source .env`.

Make sure to set the `L1` and `L2` env variables according to your desired deployment environment.

Mainnet deployment:

```
L1=mainnet
L2=base # in case of using Base as the L2
```

Testnet deployment:

```
L1=sepolia
L2=base_sepolia # in case of using Base as the L2
```

### Deploy the farm L1 & L2 proxies

The deployment assumes that the [op-token-bridge](https://github.com/makerdao/op-token-bridge) has already been deployed and was properly initialized.

Fill in the addresses of the L2 staking token and L1 and L2 rewards tokens in `script/input/{chainId}/config.json` under the `"stakingToken"` and `"rewardsToken"` keys.

Fill in the address of the mainnet DssVest contract in `script/input/1/config.json` under the `vest` key. It is assumed that the vesting contract was properly initialized. On testnet, a mock DssVest contract will automatically be deployed.

Start by deploying the `L2FarmProxySpell` singleton.

```
forge script script/DeploySingletons.s.sol:DeploySingletons --slow --multi --broadcast --verify
```

Next, run the following command to deploy the L1 vested rewards distribution contract, the L2 farm and the L1 and L2 proxies:

```
forge script script/DeployProxy.s.sol:DeployProxy --slow --multi --broadcast --verify
```

### Initialize the farm L1 & L2 proxies

On mainnet, the farm proxies should be initialized via the spell process.
On testnet, the proxies initialization can be performed via the following command:

```
forge script script/Init.s.sol:Init --slow --multi --broadcast
```

### Run a test distribution

Run the following command to distribute the vested funds to the L1 proxy.  
We add a buffer to the gas estimation per Optimism's [recommendation](https://docs.optimism.io/builders/app-developers/bridging/messaging#for-l1-to-l2-transactions-1) for L1 => L2 transactions.

```
forge script script/Distribute.s.sol:Distribute --slow --multi --broadcast --gas-estimate-multiplier 120
```

Wait for the transaction to be relayed to L2, then run the following command to forward the bridged funds from the L2 proxy to the farm:

```
forge script script/Forward.s.sol:Forward --slow --multi --broadcast
```
