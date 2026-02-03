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
 * @title VerifyVanity
 * @notice Verify that ERC-8004 contracts are properly deployed and configured
 * 
 * Configuration: Edit script/config.toml to match deployment parameters
 * 
 * Usage:
 *   forge script script/VerifyVanity.s.sol --rpc-url $RPC_URL
 */
contract VerifyVanity is Script {

    function run() external view {
        console.log("========================================");
        console.log("ERC-8004 Deployment Verification");
        console.log("========================================");
        console.log("");

        // Load configuration
        ConfigLoader.DeploymentConfig memory config = ConfigLoader.load(vm);

        // Calculate addresses (same logic as upgrade script)
        address identityProxy = _calculateProxyAddress(config, config.identitySalt, address(0));
        address reputationProxy = _calculateProxyAddress(config, config.reputationSalt, identityProxy);
        address validationProxy = _calculateProxyAddress(config, config.validationSalt, identityProxy);

        console.log("Checking proxy addresses:");
        console.log("  IdentityRegistry:  ", identityProxy);
        console.log("  ReputationRegistry:", reputationProxy);
        console.log("  ValidationRegistry:", validationProxy);
        console.log("");

        bool allPassed = true;

        // Check 1: Proxies have code
        console.log("1. Checking proxy code...");
        if (!_hasCode(identityProxy)) {
            console.log("   FAIL: IdentityRegistry proxy has no code");
            allPassed = false;
        }
        if (!_hasCode(reputationProxy)) {
            console.log("   FAIL: ReputationRegistry proxy has no code");
            allPassed = false;
        }
        if (!_hasCode(validationProxy)) {
            console.log("   FAIL: ValidationRegistry proxy has no code");
            allPassed = false;
        }
        if (allPassed) {
            console.log("   PASS: All proxies have code");
        }
        console.log("");

        // Check 2: Contract versions
        console.log("2. Checking contract versions...");
        try IdentityRegistryUpgradeable(identityProxy).getVersion() returns (string memory version) {
            console.log("   IdentityRegistry version:", version);
        } catch {
            console.log("   WARN: IdentityRegistry not upgraded yet");
            allPassed = false;
        }

        try ReputationRegistryUpgradeable(reputationProxy).getVersion() returns (string memory version) {
            console.log("   ReputationRegistry version:", version);
        } catch {
            console.log("   WARN: ReputationRegistry not upgraded yet");
            allPassed = false;
        }

        try ValidationRegistryUpgradeable(validationProxy).getVersion() returns (string memory version) {
            console.log("   ValidationRegistry version:", version);
        } catch {
            console.log("   WARN: ValidationRegistry not upgraded yet");
            allPassed = false;
        }
        console.log("");

        // Check 3: Ownership
        console.log("3. Checking ownership...");
        try IdentityRegistryUpgradeable(identityProxy).owner() returns (address owner) {
            if (owner == config.ownerAddress) {
                console.log("   PASS: IdentityRegistry owner correct:", owner);
            } else {
                console.log("   WARN: IdentityRegistry owner:", owner);
                console.log("         Expected:", config.ownerAddress);
            }
        } catch {
            console.log("   WARN: Cannot read IdentityRegistry owner");
        }

        try ReputationRegistryUpgradeable(reputationProxy).owner() returns (address owner) {
            if (owner == config.ownerAddress) {
                console.log("   PASS: ReputationRegistry owner correct:", owner);
            } else {
                console.log("   WARN: ReputationRegistry owner:", owner);
            }
        } catch {
            console.log("   WARN: Cannot read ReputationRegistry owner");
        }

        try ValidationRegistryUpgradeable(validationProxy).owner() returns (address owner) {
            if (owner == config.ownerAddress) {
                console.log("   PASS: ValidationRegistry owner correct:", owner);
            } else {
                console.log("   WARN: ValidationRegistry owner:", owner);
            }
        } catch {
            console.log("   WARN: Cannot read ValidationRegistry owner");
        }
        console.log("");

        // Check 4: Cross-registry references
        console.log("4. Checking identity registry references...");
        try ReputationRegistryUpgradeable(reputationProxy).getIdentityRegistry() returns (address ref) {
            if (ref == identityProxy) {
                console.log("   PASS: ReputationRegistry -> IdentityRegistry correct");
            } else {
                console.log("   FAIL: ReputationRegistry reference mismatch");
                console.log("         Expected:", identityProxy);
                console.log("         Got:", ref);
                allPassed = false;
            }
        } catch {
            console.log("   WARN: Cannot read ReputationRegistry reference");
        }

        try ValidationRegistryUpgradeable(validationProxy).getIdentityRegistry() returns (address ref) {
            if (ref == identityProxy) {
                console.log("   PASS: ValidationRegistry -> IdentityRegistry correct");
            } else {
                console.log("   FAIL: ValidationRegistry reference mismatch");
                allPassed = false;
            }
        } catch {
            console.log("   WARN: Cannot read ValidationRegistry reference");
        }
        console.log("");

        // Summary
        console.log("========================================");
        if (allPassed) {
            console.log("PASS: All checks passed");
        } else {
            console.log("WARN: Some checks failed or incomplete");
            console.log("      May need to run upgrade script");
        }
        console.log("========================================");
    }

    function _hasCode(address addr) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(addr)
        }
        return size > 0;
    }

    function _calculateProxyAddress(
        ConfigLoader.DeploymentConfig memory config,
        bytes32 salt,
        address identityRegistry
    ) internal pure returns (address) {
        // Calculate MinimalUUPS address
        address minimalUUPS = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            config.factoryAddress,
                            config.minimalUupsSalt,
                            keccak256(type(MinimalUUPS).creationCode)
                        )
                    )
                )
            )
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

        return address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            config.factoryAddress,
                            salt,
                            keccak256(proxyCreationCode)
                        )
                    )
                )
            )
        );
    }
}

