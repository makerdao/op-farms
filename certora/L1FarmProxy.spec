// L1FarmProxy.spec

using GemMock as gem;
using Auxiliar as aux;
using L1TokenBridgeMock as l1Bridge;

methods {
    // storage variables
    function wards(address) external returns (uint256) envfree;
    function minGasLimit() external returns (uint32) envfree;
    function rewardThreshold() external returns (uint224) envfree;
    // immutables
    function rewardsToken() external returns (address) envfree;
    function remoteToken() external returns (address) envfree;
    function l2Proxy() external returns (address) envfree;
    function l1Bridge() external returns (address) envfree;
    //
    function aux.getEmptyDataHash() external returns (bytes32) envfree;
    function gem.allowance(address,address) external returns (uint256) envfree;
    function gem.totalSupply() external returns (uint256) envfree;
    function gem.balanceOf(address) external returns (uint256) envfree;
    function l1Bridge.escrow() external returns (address) envfree;
    function l1Bridge.lastLocalToken() external returns (address) envfree;
    function l1Bridge.lastRemoteToken() external returns (address) envfree;
    function l1Bridge.lastTo() external returns (address) envfree;
    function l1Bridge.lastAmount() external returns (uint256) envfree;
    function l1Bridge.lastMinGasLimit() external returns (uint32) envfree;
    function l1Bridge.lastExtraDataHash() external returns (bytes32) envfree;
    //
    function _.transfer(address,uint256) external => DISPATCHER(true);
    function _.transferFrom(address,address,uint256) external => DISPATCHER(true);
}

// Verify that each storage layout is only modified in the corresponding functions
rule storageAffected(method f) {
    env e;

    address anyAddr;

    mathint wardsBefore = wards(anyAddr);
    mathint minGasLimitBefore = minGasLimit();
    mathint rewardThresholdBefore = rewardThreshold();

    calldataarg args;
    f(e, args);

    mathint wardsAfter = wards(anyAddr);
    mathint minGasLimitAfter = minGasLimit();
    mathint rewardThresholdAfter = rewardThreshold();

    assert wardsAfter != wardsBefore => f.selector == sig:rely(address).selector || f.selector == sig:deny(address).selector, "Assert 1";
    assert minGasLimitAfter != minGasLimitBefore => f.selector == sig:file(bytes32,uint256).selector, "Assert 2";
    assert rewardThresholdAfter != rewardThresholdBefore => f.selector == sig:file(bytes32,uint256).selector, "Assert 3";
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

    mathint minGasLimitBefore = minGasLimit();
    mathint rewardThresholdBefore = rewardThreshold();

    file(e, what, data);

    mathint minGasLimitAfter = minGasLimit();
    mathint rewardThresholdAfter = rewardThreshold();

    assert what == to_bytes32(0x6d696e4761734c696d6974000000000000000000000000000000000000000000) => minGasLimitAfter == data % (max_uint32 + 1), "Assert 1";
    assert what != to_bytes32(0x6d696e4761734c696d6974000000000000000000000000000000000000000000) => minGasLimitAfter == minGasLimitBefore, "Assert 2";
    assert what == to_bytes32(0x7265776172645468726573686f6c640000000000000000000000000000000000) => rewardThresholdAfter == data % (max_uint224 + 1), "Assert 3";
    assert what != to_bytes32(0x7265776172645468726573686f6c640000000000000000000000000000000000) => rewardThresholdAfter == rewardThresholdBefore, "Assert 4";
}

// Verify revert rules on file
rule file_revert(bytes32 what, uint256 data) {
    env e;

    mathint wardsSender = wards(e.msg.sender);

    file@withrevert(e, what, data);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;
    bool revert3 = what != to_bytes32(0x6d696e4761734c696d6974000000000000000000000000000000000000000000) &&
                   what != to_bytes32(0x7265776172645468726573686f6c640000000000000000000000000000000000);

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

// Verify correct storage changes for non reverting notifyRewardAmount
rule notifyRewardAmount(uint256 reward) {
    env e;

    bytes32 emptyDataHash = aux.getEmptyDataHash();

    notifyRewardAmount(e, reward);

    address lastLocalTokenAfter = l1Bridge.lastLocalToken();
    address lastRemoteTokenAfter = l1Bridge.lastRemoteToken();
    address lastToAfter = l1Bridge.lastTo();
    mathint lastAmountAfter = l1Bridge.lastAmount();
    mathint lastMinGasLimitAfter = l1Bridge.lastMinGasLimit();
    bytes32 lastExtraDataHashAfter = l1Bridge.lastExtraDataHash();

    assert lastLocalTokenAfter == rewardsToken(), "Assert 1";
    assert lastRemoteTokenAfter == remoteToken(), "Assert 2";
    assert lastToAfter == l2Proxy(), "Assert 3";
    assert lastAmountAfter == reward, "Assert 4";
    assert lastMinGasLimitAfter == minGasLimit(), "Assert 5";
    assert lastExtraDataHashAfter == emptyDataHash, "Assert 6";
}

// Verify revert rules on notifyRewardAmount
rule notifyRewardAmount_revert(uint256 reward) {
    env e;

    require rewardsToken() == gem;

    mathint rewardThreshold = rewardThreshold();
    mathint rewardsTokenBalanceOfProxy = gem.balanceOf(currentContract);
    address escrow = l1Bridge.escrow();
    mathint rewardsTokenBalanceOfEscrow = gem.balanceOf(escrow);
    // ERC20 assumption
    require gem.totalSupply() >= rewardsTokenBalanceOfProxy + rewardsTokenBalanceOfEscrow;
    // Happening in constructor
    require gem.allowance(currentContract, l1Bridge) == max_uint256;

    notifyRewardAmount@withrevert(e, reward);

    bool revert1 = e.msg.value > 0;
    bool revert2 = reward <= rewardThreshold;
    bool revert3 = rewardsTokenBalanceOfProxy < reward;

    assert lastReverted <=> revert1 || revert2 || revert3, "Revert rules failed";
}
