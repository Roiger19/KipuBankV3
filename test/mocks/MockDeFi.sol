// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockDeFi
 * @notice Integrated mock contract that simulates both USDC token and Uniswap Router functionality
 * @dev This mock combines ERC20 token behavior with DEX router functions for comprehensive testing
 * @author Juan Pablo Soto Roig
 */

contract MockDeFi is ERC20 {

    /// @notice Mock WETH address to simulate Ethereum wrapping
    address public WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    /**
     * @notice Deploys the mock contract with initial token supply
     * @dev Mints 10 million mock USDC tokens to deployer for testing
     */
    constructor() ERC20("Mock USDC", "mUSDC") { _mint(msg.sender, 10000000 * 10 ** 6); }

    /**
     * @notice Mints additional tokens to specified address
     * @dev Used to fund test accounts with mock USDC
     * @param to Address to receive the minted tokens
     * @param amount Amount of tokens to mint (6 decimals)
     */
    function mint(address to, uint256 amount) external { _mint(to, amount); }

    /**
     * @notice Returns the decimal places for the token
     * @dev Mock USDC uses 6 decimals like real USDC
     * @return uint8 Number of decimal places (6)
     */
    function decimals() public pure override returns (uint8) { return 6; }

    /**
     * @notice Simulates Uniswap getAmountsOut function for price estimation
     * @dev Returns fixed 2000x conversion rate for ETH swaps, 1:1 for token swaps
     * @param amountIn Input amount for the swap
     * @return amounts Array containing [inputAmount, outputAmount]
     */
    function getAmountsOut(uint256 amountIn, address[] memory) external pure returns (uint256[] memory amounts) {
        amounts = new uint256[](2); amounts[0] = amountIn; amounts[1] = amountIn * 2000; return amounts;
    }

    /**
     * @notice Simulates swapping exact ETH for tokens
     * @dev Mints mock USDC tokens to simulate successful swap
     * @param to Address to receive the output tokens
     * @return amounts Array containing [inputAmount, outputAmount]
     */
    function swapExactETHForTokens(uint256, address[] calldata, address to, uint256) external payable returns (uint256[] memory amounts) {
        amounts = new uint256[](2); amounts[0] = msg.value; amounts[1] = msg.value * 2000;
        _mint(to, amounts[1]); return amounts;
    }

    /**
     * @notice Simulates swapping exact tokens for tokens
     * @dev Mints output tokens to simulate successful swap
     * @param amountIn Input token amount
     * @param to Address to receive the output tokens
     * @return amounts Array containing [inputAmount, outputAmount]
     */
    function swapExactTokensForTokens(uint256 amountIn, uint256, address[] calldata, address to, uint256) external returns (uint256[] memory amounts) {
        amounts = new uint256[](2); amounts[0] = amountIn; amounts[1] = amountIn;
        _mint(to, amountIn); return amounts;
    }
}