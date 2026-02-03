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
 * @title DeployVanity
 * @notice Deploy ERC-8004 contracts with vanity addresses using CREATE2
 * 
 * Configuration: Edit script/config.toml to change deployment parameters
 * 
 * Usage:
 *   # With private key
 *   forge script script/DeployVanity.s.sol --rpc-url $RPC_URL --broadcast --verify
 * 
 *   # With Ledger (recommended!)
 *   forge script script/DeployVanity.s.sol --rpc-url $RPC_URL --broadcast --ledger
 */
contract DeployVanity is Script {

    struct DeploymentAddresses {
        address minimalUUPS;
        address identityProxy;
        address reputationProxy;
        address validationProxy;
        address identityImpl;
        address reputationImpl;
        address validationImpl;
    }

    function run() external returns (DeploymentAddresses memory addresses) {
        console.log("========================================");
        console.log("ERC-8004 Vanity Deployment (Forge)");
        console.log("========================================");
        console.log("Deployer:", msg.sender);
        console.log("");

        // Load configuration from config.toml
        ConfigLoader.DeploymentConfig memory config = ConfigLoader.load(vm);
        
        console.log("Configuration loaded:");
        console.log("  Factory:", config.factoryAddress);
        console.log("  Owner:", config.ownerAddress);
        console.log("");

        // Check if CREATE2 factory exists
        uint256 factorySize = config.factoryAddress.code.length;
        require(factorySize > 0, "SAFE Singleton Factory not found!");
        console.log("Factory verified");
        console.log("");

        vm.startBroadcast();

        // ============================================================================
        // PHASE 1: Deploy MinimalUUPS Placeholder
        // ============================================================================
        console.log("PHASE 1: Deploying MinimalUUPS Placeholder");
        console.log("===========================================");
        
        // 计算 MinimalUUPS 地址
        address expectedMinimalUUPS = _calculateCreate2Address(
            config.factoryAddress,
            config.minimalUupsSalt,
            keccak256(type(MinimalUUPS).creationCode)
        );
        
        // 检查是否已经部署
        if (expectedMinimalUUPS.code.length > 0) {
            console.log("MinimalUUPS already deployed at:", expectedMinimalUUPS);
            console.log("Skipping deployment...");
            addresses.minimalUUPS = expectedMinimalUUPS;
        } else {
            addresses.minimalUUPS = _deployCreate2(
                config.factoryAddress,
                config.minimalUupsSalt,
                type(MinimalUUPS).creationCode
            );
            console.log("MinimalUUPS deployed at:", addresses.minimalUUPS);
        }
        console.log("");

        // ============================================================================
        // PHASE 2: Deploy Vanity Proxies
        // ============================================================================
        console.log("PHASE 2: Deploying Vanity Proxies");
        console.log("==================================");

        // IdentityRegistry proxy
        bytes memory identityInitData = abi.encodeWithSelector(
            MinimalUUPS.initialize.selector,
            address(0),
            config.ownerAddress
        );
        addresses.identityProxy = _deployProxyCreate2IfNeeded(
            config.factoryAddress,
            config.identitySalt,
            addresses.minimalUUPS,
            identityInitData,
            "IdentityRegistry"
        );

        // ReputationRegistry proxy
        bytes memory reputationInitData = abi.encodeWithSelector(
            MinimalUUPS.initialize.selector,
            addresses.identityProxy,
            config.ownerAddress
        );
        addresses.reputationProxy = _deployProxyCreate2IfNeeded(
            config.factoryAddress,
            config.reputationSalt,
            addresses.minimalUUPS,
            reputationInitData,
            "ReputationRegistry"
        );

        // ValidationRegistry proxy
        bytes memory validationInitData = abi.encodeWithSelector(
            MinimalUUPS.initialize.selector,
            addresses.identityProxy,
            config.ownerAddress
        );
        addresses.validationProxy = _deployProxyCreate2IfNeeded(
            config.factoryAddress,
            config.validationSalt,
            addresses.minimalUUPS,
            validationInitData,
            "ValidationRegistry"
        );
        console.log("");

        // ============================================================================
        // PHASE 3: Deploy Implementation Contracts
        // ============================================================================
        console.log("PHASE 3: Deploying Implementation Contracts");
        console.log("============================================");

        addresses.identityImpl = _deployCreate2(
            config.factoryAddress,
            config.identityImplSalt,
            type(IdentityRegistryUpgradeable).creationCode
        );
        console.log("IdentityRegistry implementation:", addresses.identityImpl);

        addresses.reputationImpl = _deployCreate2(
            config.factoryAddress,
            config.reputationImplSalt,
            type(ReputationRegistryUpgradeable).creationCode
        );
        console.log("ReputationRegistry implementation:", addresses.reputationImpl);

        addresses.validationImpl = _deployCreate2(
            config.factoryAddress,
            config.validationImplSalt,
            type(ValidationRegistryUpgradeable).creationCode
        );
        console.log("ValidationRegistry implementation:", addresses.validationImpl);
        console.log("");

        vm.stopBroadcast();

        // ============================================================================
        // Summary
        // ============================================================================
        console.log("========================================");
        console.log("DEPLOYMENT COMPLETE");
        console.log("========================================");
        console.log("");
        console.log("Proxy Addresses:");
        console.log("  IdentityRegistry:  ", addresses.identityProxy);
        console.log("  ReputationRegistry:", addresses.reputationProxy);
        console.log("  ValidationRegistry:", addresses.validationProxy);
        console.log("");
        console.log("Implementation Addresses:");
        console.log("  IdentityRegistry:  ", addresses.identityImpl);
        console.log("  ReputationRegistry:", addresses.reputationImpl);
        console.log("  ValidationRegistry:", addresses.validationImpl);
        console.log("");
        console.log("Next Steps:");
        console.log("  1. Upgrade proxies: forge script script/UpgradeVanity.s.sol --rpc-url $RPC_URL --broadcast");
        console.log("  2. Verify contracts: forge verify-contract <address> <contract>");
        console.log("");

        return addresses;
    }

    /**
     * @dev Calculate CREATE2 address
     */
    function _calculateCreate2Address(
        address factory,
        bytes32 salt,
        bytes32 creationCodeHash
    ) internal pure returns (address) {
        return address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            factory,
                            salt,
                            creationCodeHash
                        )
                    )
                )
            )
        );
    }

    /**
     * @dev Deploy contract using CREATE2 via SAFE Singleton Factory
     */
    function _deployCreate2(
        address factory,
        bytes32 salt,
        bytes memory creationCode
    ) internal returns (address deployed) {
        bytes memory deploymentData = abi.encodePacked(salt, creationCode);
        
        (bool success, bytes memory data) = factory.call(deploymentData);
        require(success, "CREATE2 deployment failed");
        
        // Calculate expected address
        deployed = _calculateCreate2Address(factory, salt, keccak256(creationCode));
    }

    /**
     * @dev Deploy ERC1967Proxy using CREATE2
     */
    function _deployProxyCreate2(
        address factory,
        bytes32 salt,
        address implementation,
        bytes memory initData
    ) internal returns (address deployed) {
        bytes memory proxyCreationCode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(implementation, initData)
        );
        
        return _deployCreate2(factory, salt, proxyCreationCode);
    }
    
    /**
     * @dev Deploy ERC1967Proxy using CREATE2, skip if already deployed
     */
    function _deployProxyCreate2IfNeeded(
        address factory,
        bytes32 salt,
        address implementation,
        bytes memory initData,
        string memory name
    ) internal returns (address proxy) {
        bytes memory proxyCreationCode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(implementation, initData)
        );
        
        // 计算预期地址
        address expectedProxy = _calculateCreate2Address(
            factory,
            salt,
            keccak256(proxyCreationCode)
        );
        
        // 检查是否已经部署
        if (expectedProxy.code.length > 0) {
            console.log(string.concat(name, " proxy already deployed at:"), expectedProxy);
            console.log("Skipping deployment...");
            return expectedProxy;
        }
        
        // 部署新的 proxy
        proxy = _deployCreate2(factory, salt, proxyCreationCode);
        console.log(string.concat(name, " proxy:"), proxy);
        return proxy;
    }
}

