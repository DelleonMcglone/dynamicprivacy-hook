// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {PrivacyDynamicFeeHook} from "../src/PrivacyDynamicFeeHook.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";

contract PrivacyDynamicFeeHookTest is Test {
    using PoolIdLibrary for PoolKey;

    PrivacyDynamicFeeHook hook;
    IPoolManager poolManager;

    address alice = address(0x1);
    address bob = address(0x2);

    PoolKey testPoolKey;
    bytes32 testCommitHash;
    uint256 testNonce = 12345;

    function setUp() public {
        poolManager = IPoolManager(address(0x1111));
        vm.etch(address(poolManager), "mock");
        hook = new PrivacyDynamicFeeHook(poolManager);

        testPoolKey = PoolKey({
            currency0: Currency.wrap(address(0xA)),
            currency1: Currency.wrap(address(0xB)),
            fee: 0x800000,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });

        testCommitHash = hook.generateCommitmentHash(
            alice,
            true,
            1 ether,
            0,
            testNonce
        );
    }

    function test_CommitSwap() public {
        vm.startPrank(alice);

        bytes32 commitmentId = hook.commitSwap(testPoolKey, testCommitHash);

        assertNotEq(commitmentId, bytes32(0));

        PrivacyDynamicFeeHook.SwapCommitment memory commitment = hook.getCommitment(commitmentId);
        assertEq(commitment.trader, alice);
        assertEq(commitment.commitHash, testCommitHash);
        assertEq(commitment.commitBlock, block.number);
        assertEq(commitment.executed, false);

        vm.stopPrank();
    }

    function test_CanReveal() public {
        vm.startPrank(alice);

        bytes32 commitmentId = hook.commitSwap(testPoolKey, testCommitHash);

        assertFalse(hook.canReveal(commitmentId));

        vm.roll(block.number + hook.MIN_DELAY_BLOCKS());
        assertTrue(hook.canReveal(commitmentId));

        vm.roll(block.number + hook.MAX_DELAY_BLOCKS());
        assertFalse(hook.canReveal(commitmentId));

        vm.stopPrank();
    }

    function test_GenerateCommitmentHash() public {
        bytes32 hash1 = hook.generateCommitmentHash(alice, true, 1 ether, 0, testNonce);
        bytes32 hash2 = hook.generateCommitmentHash(alice, true, 1 ether, 0, testNonce);

        assertEq(hash1, hash2);

        bytes32 hash3 = hook.generateCommitmentHash(alice, false, 1 ether, 0, testNonce);
        assertTrue(hash1 != hash3);
    }

    function test_MovingAverageInitialization() public view {
        // tx.gasprice is 0 in tests, so we just check the counter
        assertEq(hook.movingAverageGasPriceCount(), 1);
    }

    function test_CommitSwapGas() public {
        vm.startPrank(alice);

        uint256 gasBefore = gasleft();
        hook.commitSwap(testPoolKey, testCommitHash);
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("Gas used for commitSwap:", gasUsed);
        assertLt(gasUsed, 150000);

        vm.stopPrank();
    }
}
