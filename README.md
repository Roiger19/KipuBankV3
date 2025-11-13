# 🏦 KipuBankV3 - Decentralized Banking Protocol

## 📜 Overview

**KipuBankV3** represents the evolution of a simple savings vault into a robust DeFi integration protocol. Unlike its predecessors, V3 integrates directly with **Uniswap V2** to automate asset conversion and unify accounting.

The core philosophy of V3 is **"Single Asset Accounting"**. Regardless of whether a user deposits ETH, USDC, or any other ERC-20 token, the protocol automatically swaps the input asset into **USDC** via the Uniswap Router. This ensures that the bank's liabilities and limits (`bankCap`) are always pegged to a stable value store, drastically simplifying risk management and auditing.

### 🚀 Key Improvements & Architecture

1.  **Automated Uniswap V2 Integration**:
    * **Why:** Manual price feeds (Oracles) introduce latency and maintenance overhead.
    * **Solution:** V3 uses the Uniswap V2 Router to instantly swap incoming assets (ETH or ERC-20s) for USDC at the moment of deposit. This acts as an atomic price discovery and conversion mechanism.

2.  **Unified USDC Accounting**:
    * **Why:** Managing multiple `mapping(token => balance)` creates fragmentation and makes calculating the "Total Value Locked" (TVL) risky due to price volatility.
    * **Solution:** Users only hold a balance in USDC. The `bankCap` and `withdrawLimit` are strictly enforced in USDC terms (6 decimals).

3.  **Enhanced Security & Optimization**:
    * **Gas Optimization:** Implements `unchecked` blocks for arithmetic operations where overflow is impossible due to prior checks (fulfilling the C1-6 requirement).
    * **State Management:** Loads state variables into memory to minimize expensive `SLOAD` operations (fulfilling the C1-5 requirement).
    * **Security:** Implements `ReentrancyGuard`, `Pausable` (circuit breaker), and strict `Ownable` controls.

---

## 🛠️ Deployment & Interaction

### deployed Contracts (Sepolia Testnet)

| Contract | Address | Status |
| :--- | :--- | :--- |
| **KipuBankV3** | `0xe1a15e7A05B82a90C50cE14935F49b69b8986c9E` | ✅ Verified |

**[View verified code on Sepolia Etherscan](https://sepolia.etherscan.io/address/0xe1a15e7A05B82a90C50cE14935F49b69b8986c9E#code)**

### 📸 Deployment Proof
The contract was successfully deployed and verified using Foundry scripts.

> **[📸 PASTE YOUR DEPLOYMENT SUCCESS IMAGE HERE]**
> *(The screenshot showing "Script ran successfully" and the contract address)*

---

## 💻 Local Installation & Testing

This project uses **Foundry** for the development lifecycle.

### 1. Installation
```bash
git clone [https://github.com/Roiger19/KipuBankV3](https://github.com/Roiger19/KipuBankV3)
cd KipuBankV3
forge install

### 2. Setup Environment
Create a `.env` file in the root directory:
```ini
SEPOLIA_RPC_URL=[https://eth-sepolia.g.alchemy.com/v2/YOUR_KEY](https://eth-sepolia.g.alchemy.com/v2/YOUR_KEY)
PRIVATE_KEY=YOUR_WALLET_PRIVATE_KEY
ETHERSCAN_API_KEY=YOUR_ETHERSCAN_KEY

### 3. Compile & Test 
forge build
forge test -vvv

---

## ⚖️ Design Decisions & Trade-offs

* **Mocking vs. Forking**:
    * **Decision:** We chose to use a `MockDeFi` contract for testing instead of Mainnet Forking.
    * **Trade-off:** While forking offers "real-world" state, Mocks provide faster execution and deterministic results, which is ideal for unit testing logic like `BankCap` and `WithdrawLimits` without network latency.

* **No Deadline on Swaps**:
    * **Decision:** The `swapExact...` functions use `block.timestamp + 15 minutes` but do not allow the user to set a custom deadline.
    * **Trade-off:** This simplifies the UX (fewer arguments) but exposes the user to potential transaction delays being executed later than intended.

* **Owner Centralization**:
    * **Decision:** The `owner` has the power to `pause` the contract and `recoverERC20` tokens.
    * **Trade-off:** This is a centralization risk. If the owner key is compromised, the service can be halted. However, the owner **cannot** withdraw user USDC funds (`recoverERC20` explicitly reverts for USDC), maintaining the trustlessness of user deposits.