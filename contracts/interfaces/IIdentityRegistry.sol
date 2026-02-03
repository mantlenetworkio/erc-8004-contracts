// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IIdentityRegistry
 * @notice IdentityRegistry 接口定义
 */
interface IIdentityRegistry {
    // ERC721 标准方法
    function ownerOf(uint256 tokenId) external view returns (address);
    function getApproved(uint256 tokenId) external view returns (address);
    function isApprovedForAll(address owner, address operator) external view returns (bool);
    
    // 自定义授权检查
    function isAuthorizedOrOwner(address spender, uint256 agentId) external view returns (bool);
}

