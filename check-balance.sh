#!/bin/bash
source .env
echo "Checking balance for: 0x3AFE5151AD7950219030D6AC7eBD90F620D987D8"
BALANCE=$(cast balance 0x3AFE5151AD7950219030D6AC7eBD90F620D987D8 --rpc-url $UNICHAIN_SEPOLIA_RPC_URL)
echo "Balance: $BALANCE wei"
echo "Balance: $(cast to-unit $BALANCE ether) ETH"

if [ "$BALANCE" -gt "0" ]; then
    echo "✅ Ready to deploy!"
else
    echo "⏳ Still waiting for faucet... (refresh page and try again)"
fi
