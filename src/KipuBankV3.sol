// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/* -------------------------------------------------------------------------- */
/*                                  IMPORTS                                   */
/* -------------------------------------------------------------------------- */

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IUniswapV2Router02} from "v2-periphery/interfaces/IUniswapV2Router02.sol";

/**
 * @title KipuBankV3
 * @notice Decentralized banking protocol with automatic conversion via Uniswap V2
 * @dev Vault architecture that processes deposits in ETH, USDC, and Uniswap V2-compatible ERC-20 tokens
 *      Automatically converting them to USDC. Withdrawals are exclusively denominated in USDC.
 *      Features: capacity ceilings, withdrawal limits, anti-reentrancy security, and emergency mechanisms.
 * @author Juan Pablo Soto Roig
 */

contract KipuBankV3 is Ownable, Pausable {
    using SafeERC20 for IERC20;

    /* -------------------------------------------------------------------------- */
    /*                                  CONSTANTS                                 */
    /* -------------------------------------------------------------------------- */

    /// @notice Address representing native ETH in the contract
    address public constant ETH_ADDRESS = address(0);

    /// @notice Immutable USDC token address    
    address public immutable i_usdc;

    /// @notice Immutable Uniswap V2 Router interface for token swaps
    IUniswapV2Router02 public immutable i_uniswapRouter;

    /* -------------------------------------------------------------------------- */
    /*                                  VARIABLES                                 */
    /* -------------------------------------------------------------------------- */

    /// @notice Maximum total bank capacity expressed in USDC (6 decimals)
    uint256 public immutable i_bankCap;

    /// @notice Maximum withdrawal limit per transaction in USDC (6 decimals)
    uint256 public immutable i_withdrawLimit;

    /// @notice Total USDC balance held by the bank
    uint256 public s_totalUSDCBalance;

    /// @notice Mapping of user addresses to their USDC balances
    mapping(address => uint256) private balances;

    /// @notice Reentrancy lock
    bool private locked;

    /* -------------------------------------------------------------------------- */
    /*                                  EVENTS                                    */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Emitted when a deposit is made
     * @param token The token address that was deposited (address(0) for ETH)
     * @param user address of the depositing account
     * @param tokenAmount The amount of tokens deposited
     * @param usdcAmount The amount of USDC received after swap (for non-USDC tokens)
     * @param newBalance The new USDC balance of the user
     */
    event Deposit(address indexed token, address indexed user, uint256 tokenAmount, uint256 usdcAmount, uint256 newBalance);

    /**
     * @notice Emitted when a withdrawal is made
     * @param user The address of the user who withdrew
     * @param usdcAmount The amount of USDC withdrawn
     * @param newBalance The new USDC balance of the user after withdrawal
     */
    event Withdraw(address indexed user, uint256 usdcAmount, uint256 newBalance);

    /**
     * @notice Emitted when a token swap is executed via Uniswap
     * @param fromToken The input token address
     * @param toToken The output token address (always USDC)
     * @param amountIn The input amount swapped
     * @param amountOut The output amount received
     */
    event SwapExecuted(address indexed fromToken, address indexed toToken, uint256 amountIn, uint256 amountOut);

    /**
     * @notice Emitted when the contract pause state changes
     * @param paused True if contract was paused, false if unpaused
     */
    event PauseStateChanged(bool paused);

    /* -------------------------------------------------------------------------- */
    /*                                  ERRORS                                    */
    /* -------------------------------------------------------------------------- */

    /// @notice Thrown when an operation is attempted with zero amount
    error ZeroAmount();

    /// @notice Thrown when a deposit would exceed the bank's capacity
    /// @param bankCap The maximum bank capacity
    /// @param attempted The attempted deposit amount that would exceed capacity
    error BankCapExceeded(uint256 bankCap, uint256 attempted);

    /// @notice Thrown when a withdrawal exceeds the per-transaction limit
    /// @param limit The configured withdrawal limit
    /// @param requested The requested withdrawal amount
    error WithdrawLimitExceeded(uint256 limit, uint256 requested);

    /// @notice Thrown when a user attempts to withdraw more than their balance
    /// @param available The user's available balance
    /// @param requested The requested withdrawal amount
    error InsufficientBalance(uint256 available, uint256 requested);

    /// @notice Thrown when a transfer operation fails
    /// @param to The recipient address
    /// @param amount The amount attempted to transfer
    error TransferFailed(address to, uint256 amount);

    /// @notice Thrown when an invalid token address is provided
    /// @param token The invalid token address
    error InvalidToken(address token);

    /// @notice Thrown when a reentrancy attempt is detected
    error ReentrancyAttempt();

    /// @notice Thrown when a token swap via Uniswap fails
    /// @param reason The reason for the swap failure
    error SwapFailed(string reason);

    /// @notice Thrown when there is insufficient liquidity for a swap
    error InsufficientLiquidity();

    /// @notice Thrown when an invalid USDC address is provided
    error InvalidUSDCAddress();

    /// @notice Thrown when an invalid Uniswap router address is provided
    error InvalidUniswapRouter();

    /* -------------------------------------------------------------------------- */
    /*                                MODIFIERS                                   */
    /* -------------------------------------------------------------------------- */

    /**
     * @dev Prevents reentrancy attacks by checking locked state
     * @custom:error ReentrancyAttempt if contract is already locked
     */    
    modifier nonReentrant() {
        if (locked) revert ReentrancyAttempt();
        locked = true;
        _;
        locked = false;
    }

    /**
     * @dev Ensures the provided amount is not zero
     * @param amount The amount to validate
     * @custom:error ZeroAmount if amount is zero
     */
    modifier validAmount(uint256 amount) {
        if (amount == 0) revert ZeroAmount();
        _;
    }

    /**
     * @dev Ensures the provided token is not the USDC token
     * @param token The token address to validate
     * @custom:error InvalidToken if token is the USDC address
     */
    modifier validToken(address token) {
        if (token == address(this)) revert InvalidToken(token);
        _;
    }

    /**
     * @dev Ensures the withdrawal amount does not exceed the configured limit
     * @param amount The withdrawal amount to validate
     * @custom:error WithdrawLimitExceeded if amount exceeds i_withdrawLimit
     */
    modifier withinWithdrawLimit(uint256 amount) {
        if (amount > i_withdrawLimit) revert WithdrawLimitExceeded(i_withdrawLimit, amount);
        _;
    }

    /* -------------------------------------------------------------------------- */
    /*                               CONSTRUCTOR                                  */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Initializes the KipuBankV3 contract with configuration parameters
     * @dev Sets up the bank with capacity limits, USDC address, and Uniswap router
     * @param _bankCap Maximum total bank capacity in USDC (6 decimals)
     * @param _withdrawLimit Maximum amount per individual withdrawal in USDC (6 decimals)
     * @param _usdc Address of the USDC token contract
     * @param _uniswapRouter Address of the Uniswap V2 Router contract
     * @custom:error ZeroAmount if bankCap or withdrawLimit is zero
     * @custom:error InvalidUSDCAddress if USDC address is zero
     * @custom:error InvalidUniswapRouter if router address is zero
     */    
    constructor(uint256 _bankCap, uint256 _withdrawLimit, address _usdc, address _uniswapRouter) Ownable(msg.sender) {
        if (_bankCap == 0 || _withdrawLimit == 0) revert ZeroAmount();
        if (_usdc == address(0)) revert InvalidUSDCAddress();
        if (_uniswapRouter == address(0)) revert InvalidUniswapRouter();

        i_bankCap = _bankCap;
        i_withdrawLimit = _withdrawLimit;
        i_usdc = _usdc;
        i_uniswapRouter = IUniswapV2Router02(_uniswapRouter);
        locked = false;
    }

    /* -------------------------------------------------------------------------- */
    /*                             SPECIAL FUNCTIONS                              */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Receive function to accept ETH deposits directly
     * @dev Automatically called when ETH is sent to the contract without data
     *      Executes swap to USDC and credits user's balance
     * @custom:modifier whenNotPaused Only allowed when contract is not paused
     */
    receive() external payable whenNotPaused { _depositETH(msg.sender, msg.value); }
    
    /**
     * @notice Fallback function to handle unrecognized calls with ETH
     * @dev Processes ETH deposits even when sent with unrecognized function calls
     * @custom:modifier whenNotPaused Only allowed when contract is not paused
     */    
    fallback() external payable whenNotPaused { if (msg.value > 0) _depositETH(msg.sender, msg.value); }

    /* -------------------------------------------------------------------------- */
    /*                             PUBLIC FUNCTIONS                               */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Allows users to deposit ETH into the banking contract
     * @dev ETH is automatically swapped to USDC via Uniswap V2 and user's USDC balance is credited
     * @custom:modifier nonReentrant Prevents reentrancy attacks
     * @custom:modifier validAmount Ensures deposit amount is not zero
     * @custom:modifier whenNotPaused Only allowed when contract is not paused
     * @custom:event Deposit Emitted after successful deposit
     */    
    function depositETH() external payable nonReentrant validAmount(msg.value) whenNotPaused {
        _depositETH(msg.sender, msg.value);
    }

    /**
     * @notice Allows users to deposit ERC-20 tokens into the banking contract
     * @dev Tokens are automatically swapped to USDC via Uniswap V2 (except for USDC deposits)
     * @param token Address of the ERC-20 token to deposit
     * @param amount Amount of tokens to deposit (in token's native decimals)
     * @custom:modifier nonReentrant Prevents reentrancy attacks
     * @custom:modifier validAmount Ensures deposit amount is not zero
     * @custom:modifier validToken Ensures token address is valid
     * @custom:modifier whenNotPaused Only allowed when contract is not paused
     * @custom:event Deposit Emitted after successful deposit
     * @custom:error BankCapExceeded If deposit would exceed bank capacity
     */
    function depositToken(address token, uint256 amount) external nonReentrant validAmount(amount) validToken(token) whenNotPaused {
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        if (token == i_usdc) {
            _depositUSDC(msg.sender, amount);
        } else {
            _depositAndSwap(token, amount, msg.sender);
        }
    }

    /**
     * @notice Allows users to withdraw USDC from their balance
     * @param amount Amount of USDC to withdraw (6 decimals)
     * @custom:modifier nonReentrant Prevents reentrancy attacks
     * @custom:modifier validAmount Ensures withdrawal amount is not zero
     * @custom:modifier withinWithdrawLimit Ensures withdrawal is within per-transaction limit
     * @custom:modifier whenNotPaused Only allowed when contract is not paused
     * @custom:event Withdraw Emitted after successful withdrawal
     * @custom:error InsufficientBalance If user doesn't have enough balance
     * @custom:error TransferFailed If USDC transfer to user fails
     */
    function withdrawUSDC(uint256 amount) external nonReentrant validAmount(amount) withinWithdrawLimit(amount) whenNotPaused {
        _withdrawUSDC(msg.sender, amount);
    }

    /**
     * @notice Returns the USDC balance of a specific user
     * @param user Address of the user to query
     * @return balance User's USDC balance (6 decimals)
     */
    function balanceOf(address user) external view returns (uint256) { return balances[user]; }

    /**
     * @notice Returns the total USDC balance held by the bank
     * @return totalUSDC Total USDC balance across all users (6 decimals)
     */
    function totalBankValueUSDC() external view returns (uint256) { return s_totalUSDCBalance; }

    /**
     * @notice Estimates the amount of USDC that would be received for a token swap
     * @dev Uses Uniswap V2 Router's getAmountsOut for price estimation
     * @param token Input token address (address(0) for ETH)
     * @param amount Amount of input tokens to swap
     * @return usdcAmount Estimated USDC output amount (6 decimals)
     * @custom:error InsufficientLiquidity If there's not enough liquidity for the swap
     */
    function estimateSwap(address token, uint256 amount) external view returns (uint256 usdcAmount) {
        if (token == i_usdc) return amount;
        address[] memory path = new address[](2);
        if (token == ETH_ADDRESS) {
            path[0] = i_uniswapRouter.WETH();
            path[1] = i_usdc;
        } else {
            path[0] = token;
            path[1] = i_usdc;
        }
        try i_uniswapRouter.getAmountsOut(amount, path) returns (uint256[] memory amounts) {
            return amounts[1];
        } catch {
            revert InsufficientLiquidity();
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                            PRIVATE FUNCTIONS                               */
    /* -------------------------------------------------------------------------- */

    /**
     * @dev Internal function to handle ETH deposits and swap to USDC
     * @param from Address of the user making the deposit
     * @param amount Amount of ETH deposited (in wei)
     */
    function _depositETH(address from, uint256 amount) private {
        uint256 usdcAmount = _swapETHToUSDC(amount);
        _updateBalances(from, usdcAmount, true);
        emit Deposit(ETH_ADDRESS, from, amount, usdcAmount, balances[from]);
    }

    /**
     * @dev Internal function to handle direct USDC deposits
     * @param from Address of the user making the deposit
     * @param amount Amount of USDC deposited (6 decimals)
     */
    function _depositUSDC(address from, uint256 amount) private {
        _updateBalances(from, amount, true);
        emit Deposit(i_usdc, from, amount, amount, balances[from]);
    }

    /**
     * @dev Internal function to handle ERC-20 token deposits with swap to USDC
     * @param token Address of the token being deposited
     * @param amount Amount of tokens deposited
     * @param from Address of the user making the deposit
     */
    function _depositAndSwap(address token, uint256 amount, address from) private {
        uint256 usdcAmount = _swapTokenToUSDC(token, amount);
        _updateBalances(from, usdcAmount, true);
        emit Deposit(token, from, amount, usdcAmount, balances[from]);
    }

    /**
     * @dev Internal function to handle USDC withdrawals
     * @param from Address of the user withdrawing
     * @param amount Amount of USDC to withdraw (6 decimals)
     */
    function _withdrawUSDC(address from, uint256 amount) private {
        if (balances[from] < amount) revert InsufficientBalance(balances[from], amount);
        _updateBalances(from, amount, false);
        IERC20(i_usdc).safeTransfer(from, amount);
        emit Withdraw(from, amount, balances[from]);
    }

/**
     * @dev Internal function to update user and total balances
     * @param user Address of the user
     * @param usdcAmount USDC amount to add or subtract (6 decimals)
     * @param isDeposit True for deposit operations, false for withdrawals
     */
    function _updateBalances(address user, uint256 usdcAmount, bool isDeposit) private {
        uint256 currentTotalUSDC = s_totalUSDCBalance;
        uint256 userBalance = balances[user];

        uint256 newTotalUSDC;
        uint256 newUserBalance;

        if (isDeposit) {
            // Check overflow/cap BEFORE math to save gas on revert
            uint256 newTotal = currentTotalUSDC + usdcAmount;
            if (newTotal > i_bankCap) revert BankCapExceeded(i_bankCap, newTotal);
            
            // OPTIMIZATION: Use unchecked because we checked limits above
            unchecked {
                newTotalUSDC = newTotal;
                newUserBalance = userBalance + usdcAmount;
            }
        } else {
            // OPTIMIZATION: withdrawUSDC already checked sufficient balance
            unchecked {
                newTotalUSDC = currentTotalUSDC - usdcAmount;
                newUserBalance = userBalance - usdcAmount;
            }
        }

        // Update storage ONCE
        balances[user] = newUserBalance;
        s_totalUSDCBalance = newTotalUSDC;
    }

    /**
     * @dev Internal function to swap ETH to USDC via Uniswap V2
     * @param ethAmount Amount of ETH to swap (in wei)
     * @return usdcAmount Amount of USDC received from swap (6 decimals)
     * @custom:event SwapExecuted Emitted after successful swap
     */
    function _swapETHToUSDC(uint256 ethAmount) private returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = i_uniswapRouter.WETH();
        path[1] = i_usdc;
        uint256[] memory amounts = i_uniswapRouter.swapExactETHForTokens{value: ethAmount}(1, path, address(this), block.timestamp + 15 minutes);
        emit SwapExecuted(ETH_ADDRESS, i_usdc, ethAmount, amounts[1]);
        return amounts[1];
    }

    /**
     * @dev Internal function to swap ERC-20 tokens to USDC via Uniswap V2
     * @param token Address of the token to swap
     * @param amount Amount of tokens to swap
     * @return usdcAmount Amount of USDC received from swap (6 decimals)
     * @custom:event SwapExecuted Emitted after successful swap
     */
    function _swapTokenToUSDC(address token, uint256 amount) private returns (uint256) {
        IERC20(token).approve(address(i_uniswapRouter), amount);
        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = i_usdc;
        uint256[] memory amounts = i_uniswapRouter.swapExactTokensForTokens(amount, 1, path, address(this), block.timestamp + 15 minutes);
        emit SwapExecuted(token, i_usdc, amount, amounts[1]);
        return amounts[1];
    }

    /* -------------------------------------------------------------------------- */
    /*                           ADMINISTRATIVE FUNCTIONS                         */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Allows contract owner to pause all deposits and withdrawals
     * @dev Only callable by the owner when contract is not paused
     * @custom:modifier onlyOwner Only contract owner can call this function
     * @custom:event PauseStateChanged Emitted with true when paused
     */
    function pause() external onlyOwner { _pause(); emit PauseStateChanged(true); }

    /**
     * @notice Allows contract owner to unpause the contract
     * @dev Only callable by the owner when contract is paused
     * @custom:modifier onlyOwner Only contract owner can call this function
     * @custom:event PauseStateChanged Emitted with false when unpaused
     */
    function unpause() external onlyOwner { _unpause(); emit PauseStateChanged(false); }
    
    /**
     * @notice Emergency function to withdraw trapped funds from the contract
     * @dev Only for exceptional circumstances, exclusively by the owner
     * @param token Token address to withdraw (address(0) for ETH)
     * @param amount Amount to withdraw
     * @custom:modifier onlyOwner Only contract owner can call this function
     * @custom:error TransferFailed If the transfer to owner fails
     */
    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        if (token == ETH_ADDRESS) {
            (bool success,) = payable(owner()).call{value: amount}("");
            if (!success) revert TransferFailed(owner(), amount);
        } else {
            IERC20(token).safeTransfer(owner(), amount);
        }
    }

    /**
     * @notice Allows owner to recover accidentally sent ERC-20 tokens (except USDC)
     * @dev Prevents recovery of USDC to maintain accounting integrity
     * @param token Token address to recover
     * @param amount Amount to recover
     * @custom:modifier onlyOwner Only contract owner can call this function
     * @custom:error InvalidToken If attempting to recover USDC
     */
    function recoverERC20(address token, uint256 amount) external onlyOwner {
        if (token == i_usdc) revert InvalidToken(token);
        IERC20(token).safeTransfer(owner(), amount);
    }
}