// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PrivacyDynamicFeeHook} from "../src/PrivacyDynamicFeeHook.sol";

contract DeployPrivacyHook is Script {
    address constant POOL_MANAGER = 0xC81462Fec8B23319F288047f8A03A57682a35C1A;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console2.log("Deployer:", deployer);
        console2.log("Balance:", deployer.balance);

        vm.startBroadcast(deployerPrivateKey);

        PrivacyDynamicFeeHook hook = new PrivacyDynamicFeeHook(IPoolManager(POOL_MANAGER));

        console2.log("Hook deployed at:", address(hook));

        vm.stopBroadcast();
    }
}
