// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MockUSDC
 * @dev Mock USDC token for testing (6 decimals like real USDC)
 */
contract MockUSDC is ERC20, Ownable {
    
    constructor() ERC20("Mock USDC", "USDC") {
        // Mint initial supply
        _mint(msg.sender, 1000000 * 10 ** 6); // 1 million USDC
    }
    
    /**
     * @dev Decimals override - USDC uses 6 decimals
     */
    function decimals() public pure override returns (uint8) {
        return 6;
    }
    
    /**
     * @dev Mint tokens (only owner)
     */
    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }
    
    /**
     * @dev Burn tokens
     */
    function burn(uint256 amount) public {
        _burn(msg.sender, amount);
    }
    
    /**
     * @dev Burn from address (only owner)
     */
    function burnFrom(address account, uint256 amount) public onlyOwner {
        _burn(account, amount);
    }
}
