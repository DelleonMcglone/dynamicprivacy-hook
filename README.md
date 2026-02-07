# Privacy Dynamic Fee Hook 🔐

A Uniswap v4 hook implementing MEV protection through commit-reveal patterns and dynamic fee calculation based on gas prices and timing.

## Overview

The Privacy Dynamic Fee Hook protects traders from MEV attacks by requiring a two-phase commit-reveal mechanism for swaps. Traders commit to their swap parameters in advance without revealing them, then reveal after a minimum delay. Dynamic fees are calculated based on network gas prices and reveal timing to incentivize optimal privacy practices.

## Features

- **MEV Protection**: Commit-reveal pattern prevents front-running and sandwich attacks
- **Dynamic Fees**: Adjusts fees based on current gas prices (5-50 gwei thresholds)
- **Privacy Incentives**: Lower fees for longer commit delays (2-50 blocks)
- **Gas Price Tracking**: Moving average system tracks network congestion
- **Time-Delayed Execution**: 2 block minimum, 50 block maximum delay window

## Architecture

### Fee Structure

- **Base Fee**: 0.3% (3000 basis points)
- **Privacy Premium**: 0.2% (2000 basis points) for fast reveals
- **Gas Adjustments**: 0.05-0.3% based on gas price tiers
- **Maximum Fee**: 1.0% (10000 basis points)

### Commit-Reveal Flow

1. **Commit Phase**: Trader calls `commitSwap()` with hash of swap parameters
2. **Delay**: Wait minimum 2 blocks (recommended 5-10 for lower fees)
3. **Reveal Phase**: Execute swap with original parameters via Uniswap v4
4. **Validation**: Hook verifies commitment hash and timing requirements
5. **Dynamic Fee**: Fee calculated based on gas price and reveal timing

## Smart Contract

The hook inherits from Uniswap v4's `BaseHook` and implements:

- `beforeInitialize`: Validates dynamic fee flag on pool creation
- `beforeSwap`: Validates commitment and calculates dynamic fee
- `afterSwap`: Marks commitment executed and updates gas price average
- `commitSwap`: Creates commitment with hash
- `calculateDynamicFee`: Computes fee based on gas and timing
- `generateCommitmentHash`: Helper for creating commitment hashes

## Testing

### Local Tests (Foundry)

```bash
forge test -vv
```

**Test Results**: 5/5 passing ✅
- `test_CommitSwap`: Commitment creation and storage
- `test_CanReveal`: Timing window validation
- `test_GenerateCommitmentHash`: Hash generation and uniqueness
- `test_MovingAverageInitialization`: Gas price tracking setup
- `test_CommitSwapGas`: Gas efficiency (~112k gas per commit)

### On-Chain Testing

After deployment, run automated verification:

```bash
./test-hook.sh
```

Tests 9 on-chain properties including constants, moving averages, and function calls.

## Deployment

### Prerequisites

1. Install Foundry:
```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

2. Install dependencies:
```bash
forge install
```

3. Configure environment:
```bash
cp .env.example .env
# Add your PRIVATE_KEY and RPC_URL
```

### Deploy to Unichain Sepolia

```bash
forge script script/Deploy.s.sol:DeployPrivacyDynamicFeeHook \
  --rpc-url $UNICHAIN_SEPOLIA_RPC_URL \
  --broadcast \
  --verify
```

**Network Details**:
- Chain ID: 1301
- RPC: https://sepolia.unichain.org
- PoolManager: 0xC81462Fec8B23319F288047f8A03A57682a35C1A

## Usage

### For Traders

1. Generate commitment hash:
```solidity
bytes32 commitHash = hook.generateCommitmentHash(
    msg.sender,        // trader address
    true,             // zeroForOne direction
    1 ether,          // amount
    0,                // sqrtPriceLimitX96
    12345             // unique nonce
);
```

2. Commit to swap:
```solidity
bytes32 commitmentId = hook.commitSwap(poolKey, commitHash);
```

3. Wait minimum 2 blocks (5-10 recommended for lower fees)

4. Execute swap via Uniswap v4 with commitment ID in hookData

### For Developers

Integration with Uniswap v4 swap router:

```solidity
bytes memory hookData = abi.encode(commitmentId, nonce);

router.swap(
    poolKey,
    swapParams,
    hookData  // Pass commitment data
);
```

## Configuration

Key constants (defined in contract):

```solidity
MIN_DELAY_BLOCKS = 2      // Minimum commit delay
MAX_DELAY_BLOCKS = 50     // Maximum reveal window
BASE_FEE = 3000          // 0.3% base fee
PRIVACY_PREMIUM = 2000   // 0.2% fast reveal penalty
MAX_DYNAMIC_FEE = 10000  // 1.0% maximum fee
```

Gas price thresholds:
- < 5 gwei: No adjustment
- 5-20 gwei: +0.05% (500 bps)
- 20-50 gwei: +0.15% (1500 bps)
- > 50 gwei: +0.3% (3000 bps)

## Security Considerations

⚠️ **Important Security Notes**:

1. **Never commit private keys to git** - Use `.env` file (already in .gitignore)
2. **Use unique nonces** - Prevents commitment hash collisions
3. **Test on testnet first** - Verify all functionality before mainnet
4. **Monitor gas prices** - Higher gas = higher fees
5. **Optimal delay**: 5-10 blocks balances privacy and cost

## Project Structure

```
dynamicprivacy-hook/
├── src/
│   └── PrivacyDynamicFeeHook.sol    # Main hook contract
├── test/
│   └── PrivacyDynamicFeeHook.t.sol  # Test suite
├── script/
│   └── Deploy.s.sol                  # Deployment script
├── lib/                              # Dependencies
├── foundry.toml                      # Foundry config
├── remappings.txt                    # Import mappings
└── test-hook.sh                      # On-chain testing script
```

## Technology Stack

- **Solidity**: 0.8.26
- **Foundry**: Build and test framework
- **Uniswap v4**: Hook architecture
- **OpenZeppelin**: Standard libraries
- **EVM**: Cancun version

## Gas Optimization

The contract is optimized for gas efficiency:
- 1,000,000 optimizer runs configured
- Efficient storage packing in `SwapCommitment` struct
- Minimal external calls
- ~112k gas per commitment operation

---

**⚠️ Disclaimer**: This is experimental software. Use at your own risk. Always test thoroughly on testnets before deploying to mainnet.
