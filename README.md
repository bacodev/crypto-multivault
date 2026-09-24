# Crypto MultiVault

Crypto MultiVault is an experimental Ethereum staking protocol that supports multiple ERC20 staking pools, configurable reward rates, time-lock multipliers, emergency pause controls and reward accounting.

The project is designed as a more advanced Solidity / DeFi example than a basic token or single staking contract.

## Features

- Multiple independent staking pools
- Separate staking and reward tokens
- Time-lock based reward multipliers
- Up to 2.5x staking weight for long locks
- Per-user reward accounting
- Owner-funded reward reserves
- Configurable reward emission rates
- Emergency pause mechanism
- SafeERC20 token transfers
- Reentrancy protection
- Two-step ownership transfer
- Local demo deployment
- Sepolia-ready configuration
- GitHub Actions CI
- Hardhat test suite

## Architecture

Each pool contains:

- staking token
- reward token
- reward emission rate
- total amount staked
- total weighted stake
- reward reserve
- active/inactive state

Each user position contains:

- deposited amount
- weighted stake
- lock expiration
- multiplier
- accrued rewards

Rewards are distributed proportionally to weighted stake.

A longer lock increases the user's effective staking weight.

## Example

A user staking 100 tokens with no lock has approximately:

```text
100 tokens × 1.00 = 100 reward weight
```

A user using the maximum lock duration has:

```text
100 tokens × 2.50 = 250 reward weight
```

The higher reward weight means a larger share of emitted rewards.

## Project Structure

```text
crypto-multivault/
├── .github/
│   └── workflows/
│       └── test.yml
├── contracts/
│   ├── mocks/
│   │   └── MockERC20.sol
│   └── MultiVaultStaking.sol
├── scripts/
│   ├── deploy.js
│   └── deploy-local-demo.js
├── test/
│   └── MultiVaultStaking.test.js
├── .env.example
├── .gitignore
├── hardhat.config.js
├── LICENSE
├── package.json
└── README.md
```

## Install

```bash
npm install
```

## Compile

```bash
npm run compile
```

## Test

```bash
npm test
```

## Coverage

```bash
npm run coverage
```

## Local Demo

Start a local blockchain:

```bash
npm run node
```

Then open another terminal:

```bash
npm run deploy:local
```

The demo deployment creates:

- a demo staking token
- a demo reward token
- the staking protocol
- one funded staking pool

## Sepolia Deployment

Copy the environment example:

```bash
cp .env.example .env
```

Set:

```text
SEPOLIA_RPC_URL=...
PRIVATE_KEY=...
```

Then:

```bash
npm run deploy:sepolia
```

Only use a dedicated test wallet. Never commit a private key to GitHub.

## Core Functions

### Create Pool

```solidity
createPool(
    address stakingToken,
    address rewardToken,
    uint256 rewardRate
)
```

### Fund Rewards

```solidity
fundRewards(
    uint256 poolId,
    uint256 amount
)
```

### Stake

```solidity
stake(
    uint256 poolId,
    uint256 amount,
    uint256 lockDuration
)
```

### Claim Rewards

```solidity
claim(uint256 poolId)
```

### Withdraw

```solidity
withdraw(
    uint256 poolId,
    uint256 amount
)
```

### Exit

```solidity
exit(uint256 poolId)
```

## Security Notes

This project uses:

- OpenZeppelin SafeERC20
- ReentrancyGuard
- Pausable
- Ownable2Step
- Checks-effects-interactions style state handling

This repository is an educational project and has not been professionally audited.

Do not deploy it with significant real funds without a full security review, invariant testing and independent audit.

## License

MIT
