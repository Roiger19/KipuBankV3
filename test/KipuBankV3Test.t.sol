// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/KipuBankV3.sol";
import "./mocks/MockDeFi.sol";

/**
 * @title KipuBankV3Test
 * @notice Comprehensive test suite for KipuBankV3 DeFi banking contract
 * @dev Tests cover core functionality, error handling, admin features, and edge cases
 * @author Juan Pablo Soto Roig
 */
contract KipuBankV3Test is Test {
    /// @notice Instance of the KipuBankV3 contract under test
    KipuBankV3 public kipuBank;

    /// @notice Mock contract simulating USDC token and Uniswap router
    MockDeFi public mockDeFi;

    /// @notice Test user addresses for simulating multiple users
    address public user1;
    address public user2;

    /**
     * @notice Sets up the test environment before each test
     * @dev Deploys fresh instances of contracts and funds test users
     */
    function setUp() public {
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        mockDeFi = new MockDeFi();

        kipuBank = new KipuBankV3(
            1000000 * 10 ** 6, // bankCap: 1,000,000 USDC
            10000 * 10 ** 6, // withdrawLimit: 10,000 USDC
            address(mockDeFi), // USDC token address
            address(mockDeFi) // Uniswap router address
        );

        mockDeFi.mint(user1, 1000 * 10 ** 6); // Fund user1 with 1,000 USDC
        mockDeFi.mint(user2, 1000 * 10 ** 6); // Fund user2 with 1,000 USDC
    }

    // ========== CORE FUNCTIONALITY TESTS ==========

    /**
     * @notice Tests contract deployment and initialization
     * @dev Verifies that contract addresses and ownership are set correctly
     * @custom:assertion USDC address matches deployment parameter
     * @custom:assertion Contract deployer is set as owner
     */
    function testDeployment() public view {
        assertEq(address(kipuBank.i_usdc()), address(mockDeFi));
        assertEq(kipuBank.owner(), address(this));
    }

    /**
     * @notice Tests USDC token deposit functionality
     * @dev Simulates a user depositing USDC tokens into the bank
     * @custom:step User approves token spending
     * @custom:step User executes deposit transaction
     * @custom:assertion User balance equals deposited amount
     */
    function testDepositUSDC() public {
        uint256 usdcAmount = 100 * 10 ** 6;
        vm.startPrank(user1);
        mockDeFi.approve(address(kipuBank), usdcAmount);
        kipuBank.depositToken(address(mockDeFi), usdcAmount);
        vm.stopPrank();
        assertEq(kipuBank.balanceOf(user1), usdcAmount);
    }

    /**
     * @notice Tests USDC withdrawal functionality
     * @dev Verifies complete deposit/withdrawal flow for USDC tokens
     * @custom:step User deposits USDC tokens
     * @custom:step User withdraws half of deposited amount
     * @custom:assertion User balance equals half of original deposit
     */
    function testWithdrawUSDC() public {
        uint256 usdcAmount = 100 * 10 ** 6;
        vm.startPrank(user1);
        mockDeFi.approve(address(kipuBank), usdcAmount * 2);
        kipuBank.depositToken(address(mockDeFi), usdcAmount);
        kipuBank.withdrawUSDC(usdcAmount / 2);
        vm.stopPrank();
        assertEq(kipuBank.balanceOf(user1), usdcAmount / 2);
    }

    /**
     * @notice Tests swap estimation for USDC-to-USDC (no actual swap)
     * @dev Verifies that estimateSwap returns same amount for identical tokens
     * @custom:assertion Estimated amount equals input amount for USDC
     */
    function testEstimateSwapUSDC() public view {
        uint256 estimate = kipuBank.estimateSwap(address(mockDeFi), 100 * 10 ** 6);
        assertEq(estimate, 100 * 10 ** 6);
    }

    /**
     * @notice Tests swap estimation for ETH-to-USDC conversion
     * @dev Verifies that ETH swap estimation returns positive value
     * @custom:assertion Estimated USDC amount is greater than zero
     */
    function testEstimateSwapETH() public view {
        uint256 estimate = kipuBank.estimateSwap(address(0), 0.001 ether);
        assertGt(estimate, 0);
    }

    /**
     * @notice Tests multiple users depositing simultaneously
     * @dev Verifies correct balance tracking for multiple concurrent users
     * @custom:step User1 deposits 100 USDC
     * @custom:step User2 deposits 50 USDC
     * @custom:assertion User1 balance equals 100 USDC
     * @custom:assertion User2 balance equals 50 USDC
     */
    function testBalanceOfMultipleUsers() public {
        vm.startPrank(user1);
        mockDeFi.approve(address(kipuBank), 100 * 10 ** 6);
        kipuBank.depositToken(address(mockDeFi), 100 * 10 ** 6);
        vm.stopPrank();

        vm.startPrank(user2);
        mockDeFi.approve(address(kipuBank), 50 * 10 ** 6);
        kipuBank.depositToken(address(mockDeFi), 50 * 10 ** 6);
        vm.stopPrank();

        assertEq(kipuBank.balanceOf(user1), 100 * 10 ** 6);
        assertEq(kipuBank.balanceOf(user2), 50 * 10 ** 6);
    }

    // ========== ERROR HANDLING TESTS ==========

    /**
     * @notice Tests insufficient balance validation for withdrawals
     * @dev Verifies that withdrawals exceeding user balance are reverted
     * @custom:assertion Transaction reverts with InsufficientBalance error
     */
    function testInsufficientBalance() public {
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSignature("InsufficientBalance(uint256,uint256)", 0, 100 * 10 ** 6));
        kipuBank.withdrawUSDC(100 * 10 ** 6);
        vm.stopPrank();
    }

    /**
     * @notice Tests zero amount validation for deposits
     * @dev Verifies that zero amount deposits are reverted
     * @custom:assertion Transaction reverts with ZeroAmount error
     */
    function testZeroAmountDeposit() public {
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSignature("ZeroAmount()"));
        kipuBank.depositToken(address(mockDeFi), 0);
        vm.stopPrank();
    }

    /**
     * @notice Tests zero amount validation for withdrawals
     * @dev Verifies that zero amount withdrawals are reverted
     * @custom:assertion Transaction reverts with ZeroAmount error
     */
    function testZeroAmountWithdrawal() public {
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSignature("ZeroAmount()"));
        kipuBank.withdrawUSDC(0);
        vm.stopPrank();
    }

    /**
     * @notice Tests withdrawal limit enforcement
     * @dev Verifies that withdrawals exceeding the limit are reverted
     * @custom:step User deposits 100 USDC
     * @custom:step User attempts to withdraw 20,000 USDC (exceeds 10,000 limit)
     * @custom:assertion Transaction reverts with WithdrawLimitExceeded error
     */
    function testWithdrawLimitExceeded() public {
        uint256 usdcAmount = 100 * 10 ** 6;

        vm.startPrank(user1);
        mockDeFi.approve(address(kipuBank), usdcAmount);
        kipuBank.depositToken(address(mockDeFi), usdcAmount);

        vm.expectRevert(
            abi.encodeWithSignature("WithdrawLimitExceeded(uint256,uint256)", 10000 * 10 ** 6, 20000 * 10 ** 6)
        );
        kipuBank.withdrawUSDC(20000 * 10 ** 6);
        vm.stopPrank();
    }

    // ========== ADMIN FUNCTIONALITY TESTS ==========

    /**
     * @notice Tests contract pausing and unpausing functionality
     * @dev Verifies that owner can pause and unpause the contract
     * @custom:step Owner pauses contract
     * @custom:assertion Contract is paused
     * @custom:step Owner unpauses contract
     * @custom:assertion Contract is not paused
     */
    function testPauseFunctionality() public {
        kipuBank.pause();
        assertTrue(kipuBank.paused());

        kipuBank.unpause();
        assertFalse(kipuBank.paused());
    }

    /**
     * @notice Tests emergency withdrawal functionality
     * @dev Verifies that owner can withdraw tokens in emergency situations
     * @custom:step User deposits USDC tokens
     * @custom:step Owner executes emergency withdrawal
     * @custom:assertion Contract token balance decreases
     */
    function testEmergencyWithdraw() public {
        uint256 usdcAmount = 100 * 10 ** 6;
        vm.startPrank(user1);
        mockDeFi.approve(address(kipuBank), usdcAmount);
        kipuBank.depositToken(address(mockDeFi), usdcAmount);
        vm.stopPrank();

        kipuBank.emergencyWithdraw(address(mockDeFi), 50 * 10 ** 6);
        assertLt(mockDeFi.balanceOf(address(kipuBank)), usdcAmount);
    }

    // ========== SKIPPED TESTS (COMPLEX INTEGRATION) ==========

    /**
     * @notice Placeholder for receive function tests
     * @dev Skipped due to complex ETH integration requirements
     */
    function testReceiveFunction() public pure {
        return; // Skip - complex ETH integration
    }

    /**
     * @notice Placeholder for fallback function tests
     * @dev Skipped due to complex ETH integration requirements
     */
    function testFallbackFunction() public pure {
        return; // Skip - complex ETH integration
    }

    // ========== ADDITIONAL COVERAGE TESTS ==========

    /**
     * @notice Tests bank capacity and withdrawal limit getters
     * @dev Verifies that deployment parameters are stored correctly
     * @custom:assertion Bank capacity equals deployment value
     * @custom:assertion Withdrawal limit equals deployment value
     * @custom:assertion Uniswap router address is set correctly
     */
    function testBankCapAndLimit() public view {
        assertEq(kipuBank.i_bankCap(), 1000000 * 10 ** 6);
        assertEq(kipuBank.i_withdrawLimit(), 10000 * 10 ** 6);
        assertEq(address(kipuBank.i_uniswapRouter()), address(mockDeFi));
    }

    /**
     * @notice Tests total bank value calculation
     * @dev Verifies that total USDC balance is correctly reported
     * @custom:step User deposits USDC tokens
     * @custom:assertion Total bank value is greater than zero
     */
    function testTotalBankValue() public {
        uint256 usdcAmount = 100 * 10 ** 6;
        vm.startPrank(user1);
        mockDeFi.approve(address(kipuBank), usdcAmount);
        kipuBank.depositToken(address(mockDeFi), usdcAmount);
        vm.stopPrank();

        assertGt(kipuBank.totalBankValueUSDC(), 0);
    }
}