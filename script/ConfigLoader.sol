// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Vm.sol";

/**
 * @title ConfigLoader
 * @notice 从 config.toml 加载配置
 * @dev 使用 vm.parseToml() 读取配置文件
 */
library ConfigLoader {
    struct DeploymentConfig {
        address factoryAddress;
        address ownerAddress;
        bytes32 minimalUupsSalt;
        bytes32 identitySalt;
        bytes32 reputationSalt;
        bytes32 validationSalt;
        bytes32 identityImplSalt;
        bytes32 reputationImplSalt;
        bytes32 validationImplSalt;
    }

    /**
     * @dev 加载配置文件
     */
    function load(Vm vm) internal view returns (DeploymentConfig memory config) {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/script/config.toml");
        string memory toml = vm.readFile(path);

        // 读取 factory 配置
        config.factoryAddress = vm.parseTomlAddress(toml, ".factory.address");
        
        // 读取 owner 配置
        config.ownerAddress = vm.parseTomlAddress(toml, ".owner.address");

        // 读取 salt 配置
        config.minimalUupsSalt = vm.parseTomlBytes32(toml, ".salts.minimal_uups");
        config.identitySalt = vm.parseTomlBytes32(toml, ".salts.identity");
        config.reputationSalt = vm.parseTomlBytes32(toml, ".salts.reputation");
        config.validationSalt = vm.parseTomlBytes32(toml, ".salts.validation");
        config.identityImplSalt = vm.parseTomlBytes32(toml, ".salts.identity_impl");
        config.reputationImplSalt = vm.parseTomlBytes32(toml, ".salts.reputation_impl");
        config.validationImplSalt = vm.parseTomlBytes32(toml, ".salts.validation_impl");
    }
}

