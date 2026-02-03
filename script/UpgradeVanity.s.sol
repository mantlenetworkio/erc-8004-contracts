// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../contracts/MinimalUUPS.sol";
import "../contracts/IdentityRegistryUpgradeable.sol";
import "../contracts/ReputationRegistryUpgradeable.sol";
import "../contracts/ValidationRegistryUpgradeable.sol";
import "../contracts/ERC1967Proxy.sol";
import "./ConfigLoader.sol";

/**
 * @title UpgradeVanity
 * @notice Upgrade proxies from MinimalUUPS to real implementations
 * 
 * Configuration: Edit script/config.toml to match deployment parameters
 * 
 * Usage:
 *   # With private key (owner must be the signer)
 *   forge script script/UpgradeVanity.s.sol --rpc-url $RPC_URL --broadcast
 * 
 *   # With Ledger (owner address must match Ledger)
 *   forge script script/UpgradeVanity.s.sol --rpc-url $RPC_URL --broadcast --ledger
 */
contract UpgradeVanity is Script {

    function run() external {
        console.log("========================================");
        console.log("ERC-8004 Vanity Upgrade (Forge)");
        console.log("========================================");
        console.log("Owner/Signer:", msg.sender);
        console.log("");

        // Load configuration
        ConfigLoader.DeploymentConfig memory config = ConfigLoader.load(vm);

        // Calculate proxy addresses
        address identityProxy = _calculateProxyAddress(config, config.identitySalt, address(0));
        address reputationProxy = _calculateProxyAddress(config, config.reputationSalt, identityProxy);
        address validationProxy = _calculateProxyAddress(config, config.validationSalt, identityProxy);

        // Calculate implementation addresses
        address identityImpl = _calculateCreate2Address(
            config.factoryAddress,
            config.identityImplSalt,
            type(IdentityRegistryUpgradeable).creationCode
        );
        address reputationImpl = _calculateCreate2Address(
            config.factoryAddress,
            config.reputationImplSalt,
            type(ReputationRegistryUpgradeable).creationCode
        );
        address validationImpl = _calculateCreate2Address(
            config.factoryAddress,
            config.validationImplSalt,
            type(ValidationRegistryUpgradeable).creationCode
        );

        console.log("Proxy Addresses:");
        console.log("  IdentityRegistry:  ", identityProxy);
        console.log("  ReputationRegistry:", reputationProxy);
        console.log("  ValidationRegistry:", validationProxy);
        console.log("");
        console.log("Implementation Addresses:");
        console.log("  IdentityRegistry:  ", identityImpl);
        console.log("  ReputationRegistry:", reputationImpl);
        console.log("  ValidationRegistry:", validationImpl);
        console.log("");

        vm.startBroadcast();

        // Upgrade IdentityRegistry
        console.log("Upgrading IdentityRegistry...");
        bytes memory identityInitData = abi.encodeWithSelector(
            IdentityRegistryUpgradeable.initialize.selector
        );
        MinimalUUPS(identityProxy).upgradeToAndCall(identityImpl, identityInitData);
        console.log("  Done");

        // Upgrade ReputationRegistry
        console.log("Upgrading ReputationRegistry...");
        bytes memory reputationInitData = abi.encodeWithSelector(
            ReputationRegistryUpgradeable.initialize.selector,
            identityProxy
        );
        MinimalUUPS(reputationProxy).upgradeToAndCall(reputationImpl, reputationInitData);
        console.log("  Done");

        // Upgrade ValidationRegistry
        console.log("Upgrading ValidationRegistry...");
        bytes memory validationInitData = abi.encodeWithSelector(
            ValidationRegistryUpgradeable.initialize.selector,
            identityProxy
        );
        MinimalUUPS(validationProxy).upgradeToAndCall(validationImpl, validationInitData);
        console.log("  Done");

        vm.stopBroadcast();

        console.log("");
        console.log("========================================");
        console.log("UPGRADE COMPLETE");
        console.log("========================================");
        console.log("");
        console.log("Verify deployment:");
        console.log("  forge script script/VerifyVanity.s.sol --rpc-url $RPC_URL");
        console.log("");
    }

    /**
     * @dev Calculate CREATE2 address
     */
    function _calculateCreate2Address(
        address factory,
        bytes32 salt,
        bytes memory creationCode
    ) internal pure returns (address) {
        return address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            factory,
                            salt,
                            keccak256(creationCode)
                        )
                    )
                )
            )
        );
    }

    /**
     * @dev Calculate proxy address (needs MinimalUUPS address)
     */
    function _calculateProxyAddress(
        ConfigLoader.DeploymentConfig memory config,
        bytes32 salt,
        address identityRegistry
    ) internal view returns (address) {
        // Calculate MinimalUUPS address
        address minimalUUPS = _calculateCreate2Address(
            config.factoryAddress,
            config.minimalUupsSalt,
            type(MinimalUUPS).creationCode
        );

        // Calculate proxy creation code
        bytes memory initData = abi.encodeWithSelector(
            MinimalUUPS.initialize.selector,
            identityRegistry,
            config.ownerAddress
        );
        bytes memory proxyCreationCode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(minimalUUPS, initData)
        );

        return _calculateCreate2Address(config.factoryAddress, salt, proxyCreationCode);
    }
}

