// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/KipuBankV3.sol";

/**
 * @title DeployKipuBankV3
 * @notice Deployment script for KipuBankV3 contract on Sepolia testnet
 */
contract DeployKipuBankV3 is Script {
    function run() external returns (KipuBankV3 deployed) {
        // ✅ Sepolia USDC y Router (parseAddress evita checksum errors)
        address usdc = vm.parseAddress("0x1c7d4b196cb0c7b01d743fbc6116a902379c7ae0");
        address router = vm.parseAddress("0xc532a74256d3b4200bf7a0400f4ad07516c2148d");

        uint256 bankCap = 100_000 * 10**6;
        uint256 withdrawLimit = 5_000 * 10**6;

        vm.startBroadcast();
        deployed = new KipuBankV3(bankCap, withdrawLimit, usdc, router);
        vm.stopBroadcast();
    }
}



