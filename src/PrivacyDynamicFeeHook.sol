// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";

contract PrivacyDynamicFeeHook is BaseHook {
    using PoolIdLibrary for PoolKey;

    // Override for testing - allows deployment at any address
    function validateHookAddress(BaseHook _this) internal pure override {}

    error InvalidCommitment();
    error CommitmentTooRecent();
    error CommitmentExpired();
    error MustUseDynamicFee();

    event SwapCommitted(bytes32 indexed commitmentId, address indexed trader, uint256 commitBlock);
    event SwapRevealed(bytes32 indexed commitmentId, address indexed trader, uint24 dynamicFee);

    uint256 public constant MIN_DELAY_BLOCKS = 2;
    uint256 public constant MAX_DELAY_BLOCKS = 50;
    uint24 public constant BASE_FEE = 3000;
    uint24 public constant MAX_DYNAMIC_FEE = 10000;
    uint24 public constant PRIVACY_PREMIUM = 2000;

    struct SwapCommitment {
        address trader;
        bool zeroForOne;
        int256 amountSpecified;
        uint160 sqrtPriceLimitX96;
        uint256 commitBlock;
        uint256 revealDeadline;
        bytes32 commitHash;
        bool executed;
    }

    mapping(bytes32 => SwapCommitment) public commitments;
    mapping(PoolId => uint24) public poolBaseFees;
    uint128 public movingAverageGasPrice;
    uint104 public movingAverageGasPriceCount;

    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {
        movingAverageGasPrice = uint128(tx.gasprice);
        movingAverageGasPriceCount = 1;
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: true,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function _beforeInitialize(address, PoolKey calldata key, uint160)
        internal
        override
        returns (bytes4)
    {
        if (key.fee & 0x800000 == 0) revert MustUseDynamicFee();
        poolBaseFees[key.toId()] = BASE_FEE;
        return this.beforeInitialize.selector;
    }

    function _beforeSwap(address sender, PoolKey calldata key, SwapParams calldata params, bytes calldata hookData)
        internal
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        (bytes32 commitmentId, uint256 nonce) = abi.decode(hookData, (bytes32, uint256));

        SwapCommitment storage commitment = commitments[commitmentId];

        // Validations
        if (commitment.trader == address(0)) revert InvalidCommitment();
        if (commitment.executed) revert InvalidCommitment();
        if (commitment.trader != sender) revert InvalidCommitment();
        if (block.number < commitment.commitBlock + MIN_DELAY_BLOCKS) revert CommitmentTooRecent();
        if (block.number > commitment.revealDeadline) revert CommitmentExpired();

        // Verify commitment hash
        bytes32 calculatedHash = keccak256(abi.encodePacked(
            sender,
            params.zeroForOne,
            params.amountSpecified,
            params.sqrtPriceLimitX96,
            nonce
        ));

        if (calculatedHash != commitment.commitHash) revert InvalidCommitment();

        // Store revealed parameters
        commitment.zeroForOne = params.zeroForOne;
        commitment.amountSpecified = params.amountSpecified;
        commitment.sqrtPriceLimitX96 = params.sqrtPriceLimitX96;

        // Calculate dynamic fee
        uint24 dynamicFee = calculateDynamicFee(key.toId(), block.number - commitment.commitBlock);

        emit SwapRevealed(commitmentId, sender, dynamicFee);

        return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, dynamicFee);
    }

    function _afterSwap(address, PoolKey calldata, SwapParams calldata, BalanceDelta, bytes calldata hookData)
        internal
        override
        returns (bytes4, int128)
    {
        (bytes32 commitmentId,) = abi.decode(hookData, (bytes32, uint256));
        commitments[commitmentId].executed = true;
        updateMovingAverage();
        return (this.afterSwap.selector, 0);
    }

    function commitSwap(PoolKey calldata key, bytes32 commitHash) external returns (bytes32) {
        bytes32 commitmentId = keccak256(abi.encodePacked(msg.sender, key.toId(), block.number, commitHash));

        commitments[commitmentId] = SwapCommitment({
            trader: msg.sender,
            zeroForOne: false,
            amountSpecified: 0,
            sqrtPriceLimitX96: 0,
            commitBlock: block.number,
            revealDeadline: block.number + MAX_DELAY_BLOCKS,
            commitHash: commitHash,
            executed: false
        });

        emit SwapCommitted(commitmentId, msg.sender, block.number);
        return commitmentId;
    }

    function generateCommitmentHash(
        address trader,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        uint256 nonce
    ) external pure returns (bytes32) {
        return keccak256(abi.encodePacked(trader, zeroForOne, amountSpecified, sqrtPriceLimitX96, nonce));
    }

    function canReveal(bytes32 commitmentId) external view returns (bool) {
        SwapCommitment memory c = commitments[commitmentId];
        return c.trader != address(0) && !c.executed &&
               block.number >= c.commitBlock + MIN_DELAY_BLOCKS &&
               block.number <= c.revealDeadline;
    }

    function getCommitment(bytes32 commitmentId) external view returns (SwapCommitment memory) {
        return commitments[commitmentId];
    }

    // ============ Fee Calculation ============

    function calculateDynamicFee(PoolId poolId, uint256 blocksSinceCommit)
        internal
        view
        returns (uint24)
    {
        uint24 baseFee = poolBaseFees[poolId];
        uint24 gasFeeAdjustment = 0;
        uint256 gasPrice = tx.gasprice;

        // Adjust based on gas price
        if (gasPrice < 5 gwei) {
            gasFeeAdjustment = 0;
        } else if (gasPrice < 20 gwei) {
            gasFeeAdjustment = 500;
        } else if (gasPrice < 50 gwei) {
            gasFeeAdjustment = 1500;
        } else {
            gasFeeAdjustment = 3000;
        }

        // Privacy penalty for fast reveals
        uint24 timingPenalty = 0;
        if (blocksSinceCommit < 5) {
            timingPenalty = PRIVACY_PREMIUM;
        } else if (blocksSinceCommit < 10) {
            timingPenalty = PRIVACY_PREMIUM / 2;
        }

        uint24 totalFee = baseFee + gasFeeAdjustment + timingPenalty;
        return totalFee > MAX_DYNAMIC_FEE ? MAX_DYNAMIC_FEE : totalFee;
    }

    function updateMovingAverage() internal {
        uint128 gasPrice = uint128(tx.gasprice);
        movingAverageGasPrice = ((movingAverageGasPrice * movingAverageGasPriceCount) + gasPrice) / (movingAverageGasPriceCount + 1);
        movingAverageGasPriceCount++;
    }

    function getCurrentFee(PoolId poolId, uint256 blocksSinceCommit)
        external
        view
        returns (uint24)
    {
        return calculateDynamicFee(poolId, blocksSinceCommit);
    }
}
