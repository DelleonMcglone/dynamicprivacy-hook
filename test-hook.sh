#!/bin/bash

# Replace with your actual deployed hook address
HOOK_ADDRESS="YOUR_HOOK_ADDRESS_HERE"
RPC_URL="https://sepolia.unichain.org"

echo "=================================="
echo "Testing Privacy Dynamic Fee Hook"
echo "=================================="
echo "Hook Address: $HOOK_ADDRESS"
echo "Network: Unichain Sepolia"
echo "=================================="
echo ""

echo "TEST 1: Verify contract exists"
echo "Command: cast code"
CODE=$(cast code $HOOK_ADDRESS --rpc-url $RPC_URL 2>&1)
if [ ${#CODE} -gt 10 ]; then
    echo "✅ PASS - Contract has bytecode"
    echo "Bytecode length: ${#CODE} characters"
else
    echo "❌ FAIL - No contract at this address"
    echo "Error: $CODE"
fi
echo ""

echo "TEST 2: Check BASE_FEE (expect 3000)"
BASE_FEE=$(cast call $HOOK_ADDRESS "BASE_FEE()(uint24)" --rpc-url $RPC_URL 2>&1)
echo "Result: $BASE_FEE"
if [ "$BASE_FEE" = "3000" ]; then
    echo "✅ PASS - BASE_FEE is correct (0.3%)"
else
    echo "⚠️  Got: $BASE_FEE (expected: 3000)"
fi
echo ""

echo "TEST 3: Check MIN_DELAY_BLOCKS (expect 2)"
MIN_DELAY=$(cast call $HOOK_ADDRESS "MIN_DELAY_BLOCKS()(uint256)" --rpc-url $RPC_URL 2>&1)
echo "Result: $MIN_DELAY"
if [ "$MIN_DELAY" = "2" ]; then
    echo "✅ PASS - MIN_DELAY_BLOCKS is correct"
else
    echo "⚠️  Got: $MIN_DELAY (expected: 2)"
fi
echo ""

echo "TEST 4: Check MAX_DELAY_BLOCKS (expect 50)"
MAX_DELAY=$(cast call $HOOK_ADDRESS "MAX_DELAY_BLOCKS()(uint256)" --rpc-url $RPC_URL 2>&1)
echo "Result: $MAX_DELAY"
if [ "$MAX_DELAY" = "50" ]; then
    echo "✅ PASS - MAX_DELAY_BLOCKS is correct"
else
    echo "⚠️  Got: $MAX_DELAY (expected: 50)"
fi
echo ""

echo "TEST 5: Check PRIVACY_PREMIUM (expect 2000)"
PREMIUM=$(cast call $HOOK_ADDRESS "PRIVACY_PREMIUM()(uint24)" --rpc-url $RPC_URL 2>&1)
echo "Result: $PREMIUM"
if [ "$PREMIUM" = "2000" ]; then
    echo "✅ PASS - PRIVACY_PREMIUM is correct (0.2%)"
else
    echo "⚠️  Got: $PREMIUM (expected: 2000)"
fi
echo ""

echo "TEST 6: Check MAX_DYNAMIC_FEE (expect 10000)"
MAX_FEE=$(cast call $HOOK_ADDRESS "MAX_DYNAMIC_FEE()(uint24)" --rpc-url $RPC_URL 2>&1)
echo "Result: $MAX_FEE"
if [ "$MAX_FEE" = "10000" ]; then
    echo "✅ PASS - MAX_DYNAMIC_FEE is correct (1%)"
else
    echo "⚠️  Got: $MAX_FEE (expected: 10000)"
fi
echo ""

echo "TEST 7: Check moving average initialized"
AVG_COUNT=$(cast call $HOOK_ADDRESS "movingAverageGasPriceCount()(uint104)" --rpc-url $RPC_URL 2>&1)
echo "Moving average count: $AVG_COUNT"
if [ "$AVG_COUNT" -ge "1" ] 2>/dev/null; then
    echo "✅ PASS - Moving average initialized"
else
    echo "⚠️  Got: $AVG_COUNT (expected: >= 1)"
fi
echo ""

echo "TEST 8: Check moving average gas price value"
AVG_GAS=$(cast call $HOOK_ADDRESS "movingAverageGasPrice()(uint128)" --rpc-url $RPC_URL 2>&1)
echo "Moving average gas price: $AVG_GAS"
if [ ! -z "$AVG_GAS" ]; then
    echo "✅ PASS - Gas price value retrieved"
else
    echo "⚠️  Could not retrieve gas price"
fi
echo ""

echo "TEST 9: Test generateCommitmentHash function"
HASH=$(cast call $HOOK_ADDRESS \
  "generateCommitmentHash(address,bool,int256,uint160,uint256)(bytes32)" \
  "0x0000000000000000000000000000000000000001" \
  true \
  "1000000000000000000" \
  0 \
  12345 \
  --rpc-url $RPC_URL 2>&1)
echo "Generated hash: $HASH"
if [[ $HASH == 0x* ]] && [ ${#HASH} -eq 66 ]; then
    echo "✅ PASS - generateCommitmentHash works (32-byte hash)"
else
    echo "⚠️  Got: $HASH"
fi
echo ""

echo "=================================="
echo "TEST SUMMARY"
echo "=================================="
echo "Check results above for any failures"
echo ""
echo "Next step: Visit explorer to verify visually"
echo "https://sepolia.uniscan.xyz/address/$HOOK_ADDRESS"
echo "=================================="
