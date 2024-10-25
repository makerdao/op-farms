// L2FarmProxy.spec

using GemMock as gem;
using FarmMock as farm;

methods {
    // storage variables
    function wards(address) external returns (uint256) envfree;
    function rewardThreshold() external returns (uint256) envfree;
    // immutables
    function rewardsToken() external returns (address) envfree;
    function farm() external returns (address) envfree;
    //
    function gem.totalSupply() external returns (uint256) envfree;
    function gem.balanceOf(address) external returns (uint256) envfree;
    function farm.lastReward() external returns (uint256) envfree;
    //
    function _.balanceOf(address) external => DISPATCHER(true);
    function _.transfer(address,uint256) external => DISPATCHER(true);
}

// Verify that each storage layout is only modified in the corresponding functions
rule storageAffected(method f) {
    env e;

    address anyAddr;

    mathint wardsBefore = wards(anyAddr);
    mathint rewardThresholdBefore = rewardThreshold();

    calldataarg args;
    f(e, args);

    mathint wardsAfter = wards(anyAddr);
    mathint rewardThresholdAfter = rewardThreshold();

    assert wardsAfter != wardsBefore => f.selector == sig:rely(address).selector || f.selector == sig:deny(address).selector, "Assert 1";
    assert rewardThresholdAfter != rewardThresholdBefore => f.selector == sig:file(bytes32,uint256).selector, "Assert 2";
}

// Verify correct storage changes for non reverting rely
rule rely(address usr) {
    env e;

    address other;
    require other != usr;

    mathint wardsOtherBefore = wards(other);

    rely(e, usr);

    mathint wardsUsrAfter = wards(usr);
    mathint wardsOtherAfter = wards(other);

    assert wardsUsrAfter == 1, "Assert 1";
    assert wardsOtherAfter == wardsOtherBefore, "Assert 2";
}

// Verify revert rules on rely
rule rely_revert(address usr) {
    env e;

    mathint wardsSender = wards(e.msg.sender);

    rely@withrevert(e, usr);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;

    assert lastReverted <=> revert1 || revert2, "Revert rules failed";
}

// Verify correct storage changes for non reverting deny
rule deny(address usr) {
    env e;

    address other;
    require other != usr;

    mathint wardsOtherBefore = wards(other);

    deny(e, usr);

    mathint wardsUsrAfter = wards(usr);
    mathint wardsOtherAfter = wards(other);

    assert wardsUsrAfter == 0, "Assert 1";
    assert wardsOtherAfter == wardsOtherBefore, "Assert 2";
}

// Verify revert rules on deny
rule deny_revert(address usr) {
    env e;

    mathint wardsSender = wards(e.msg.sender);

    deny@withrevert(e, usr);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;

    assert lastReverted <=> revert1 || revert2, "Revert rules failed";
}

// Verify correct storage changes for non reverting file
rule file(bytes32 what, uint256 data) {
    env e;

    file(e, what, data);

    mathint rewardThresholdAfter = rewardThreshold();

    assert rewardThresholdAfter == data, "Assert 1";
}

// Verify revert rules on file
rule file_revert(bytes32 what, uint256 data) {
    env e;

    mathint wardsSender = wards(e.msg.sender);

    file@withrevert(e, what, data);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;
    bool revert3 = what != to_bytes32(0x7265776172645468726573686f6c640000000000000000000000000000000000);

    assert lastReverted <=> revert1 || revert2 || revert3, "Revert rules failed";
}

// Verify correct storage changes for non reverting recover
rule recover(address token, address receiver, uint256 amount) {
    env e;

    require token == gem;

    mathint tokenBalanceOfProxyBefore = gem.balanceOf(currentContract);
    mathint tokenBalanceOfReceiverBefore = gem.balanceOf(receiver);
    // ERC20 assumption
    require gem.totalSupply() >= tokenBalanceOfProxyBefore + tokenBalanceOfReceiverBefore;

    recover(e, token, receiver, amount);

    mathint tokenBalanceOfProxyAfter = gem.balanceOf(currentContract);
    mathint tokenBalanceOfReceiverAfter = gem.balanceOf(receiver);

    assert currentContract != receiver => tokenBalanceOfProxyAfter == tokenBalanceOfProxyBefore - amount, "Assert 1";
    assert currentContract != receiver => tokenBalanceOfReceiverAfter == tokenBalanceOfReceiverBefore + amount, "Assert 2";
    assert currentContract == receiver => tokenBalanceOfProxyAfter == tokenBalanceOfProxyBefore, "Assert 3";
}

// Verify revert rules on recover
rule recover_revert(address token, address receiver, uint256 amount) {
    env e;

    mathint tokenBalanceOfProxy = gem.balanceOf(currentContract);
    // ERC20 assumption
    require gem.totalSupply() >= tokenBalanceOfProxy + gem.balanceOf(receiver);

    mathint wardsSender = wards(e.msg.sender);

    recover@withrevert(e, token, receiver, amount);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;
    bool revert3 = tokenBalanceOfProxy < amount;

    assert lastReverted <=> revert1 || revert2 || revert3, "Revert rules failed";
}

// Verify correct storage changes for non reverting forwardReward
rule forwardReward() {
    env e;

    require rewardsToken() == gem;

    mathint rewardsTokenBalanceOfProxyBefore = gem.balanceOf(currentContract);
    mathint rewardsTokenBalanceOfFarmBefore = gem.balanceOf(farm);
    // ERC20 assumption
    require gem.totalSupply() >= rewardsTokenBalanceOfProxyBefore + rewardsTokenBalanceOfFarmBefore;

    forwardReward(e);

    mathint rewardsTokenBalanceOfProxyAfter = gem.balanceOf(currentContract);
    mathint rewardsTokenBalanceOfFarmAfter = gem.balanceOf(farm);
    mathint farmLastRewardAfter = farm.lastReward();

    assert rewardsTokenBalanceOfProxyAfter == 0, "Assert 1";
    assert rewardsTokenBalanceOfFarmAfter == rewardsTokenBalanceOfFarmBefore + rewardsTokenBalanceOfProxyBefore, "Assert 2";
    assert farmLastRewardAfter == rewardsTokenBalanceOfProxyBefore, "Assert 3";
}

// Verify revert rules on forwardReward
rule forwardReward_revert() {
    env e;

    mathint rewardThreshold = rewardThreshold();
    mathint rewardsTokenBalanceOfProxy = gem.balanceOf(currentContract);
    // ERC20 assumption
    require gem.totalSupply() >= gem.balanceOf(currentContract) + gem.balanceOf(farm);

    forwardReward@withrevert(e);

    bool revert1 = e.msg.value > 0;
    bool revert2 = rewardsTokenBalanceOfProxy <= rewardThreshold;

    assert lastReverted <=> revert1 || revert2, "Revert rules failed";
}
