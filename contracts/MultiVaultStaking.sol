// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title MultiVaultStaking
 * @notice Multi-pool ERC20 staking contract with configurable reward rates,
 *         lock multipliers, reward funding, emergency pause and claim logic.
 *
 * @dev This project is intended for educational and experimental use.
 */
contract MultiVaultStaking is Ownable2Step, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    uint256 public constant PRECISION = 1e18;
    uint256 public constant MAX_LOCK_DURATION = 365 days;
    uint256 public constant MAX_MULTIPLIER_BPS = 25_000; // 2.5x
    uint256 public constant BPS = 10_000;

    struct Pool {
        IERC20 stakingToken;
        IERC20 rewardToken;
        uint256 rewardRate;
        uint256 lastUpdateTime;
        uint256 rewardPerWeightStored;
        uint256 totalStaked;
        uint256 totalWeight;
        uint256 rewardBalance;
        bool active;
    }

    struct Position {
        uint256 amount;
        uint256 weight;
        uint256 lockEnd;
        uint256 multiplierBps;
        uint256 rewardPerWeightPaid;
        uint256 rewards;
    }

    Pool[] public pools;

    mapping(uint256 => mapping(address => Position)) public positions;

    error InvalidPool();
    error PoolInactive();
    error ZeroAmount();
    error InvalidLockDuration();
    error InvalidMultiplier();
    error PositionLocked(uint256 lockEnd);
    error InsufficientRewardBalance();
    error SameTokenNotAllowed();

    event PoolCreated(
        uint256 indexed poolId,
        address indexed stakingToken,
        address indexed rewardToken,
        uint256 rewardRate
    );

    event PoolStatusChanged(uint256 indexed poolId, bool active);
    event RewardRateChanged(uint256 indexed poolId, uint256 oldRate, uint256 newRate);
    event RewardsFunded(uint256 indexed poolId, uint256 amount);
    event Staked(
        uint256 indexed poolId,
        address indexed user,
        uint256 amount,
        uint256 lockEnd,
        uint256 multiplierBps
    );
    event Withdrawn(uint256 indexed poolId, address indexed user, uint256 amount);
    event RewardPaid(uint256 indexed poolId, address indexed user, uint256 reward);

    constructor(address initialOwner) Ownable(initialOwner) {}

    modifier validPool(uint256 poolId) {
        if (poolId >= pools.length) revert InvalidPool();
        _;
    }

    modifier updateReward(uint256 poolId, address account) {
        Pool storage pool = pools[poolId];

        pool.rewardPerWeightStored = rewardPerWeight(poolId);
        pool.lastUpdateTime = block.timestamp;

        if (account != address(0)) {
            Position storage p = positions[poolId][account];
            p.rewards = earned(poolId, account);
            p.rewardPerWeightPaid = pool.rewardPerWeightStored;
        }

        _;
    }

    function createPool(
        address stakingToken,
        address rewardToken,
        uint256 rewardRate
    ) external onlyOwner returns (uint256 poolId) {
        if (stakingToken == address(0) || rewardToken == address(0)) {
            revert ZeroAmount();
        }

        if (stakingToken == rewardToken) {
            revert SameTokenNotAllowed();
        }

        poolId = pools.length;

        pools.push(
            Pool({
                stakingToken: IERC20(stakingToken),
                rewardToken: IERC20(rewardToken),
                rewardRate: rewardRate,
                lastUpdateTime: block.timestamp,
                rewardPerWeightStored: 0,
                totalStaked: 0,
                totalWeight: 0,
                rewardBalance: 0,
                active: true
            })
        );

        emit PoolCreated(poolId, stakingToken, rewardToken, rewardRate);
    }

    function setPoolActive(
        uint256 poolId,
        bool active
    ) external onlyOwner validPool(poolId) {
        pools[poolId].active = active;
        emit PoolStatusChanged(poolId, active);
    }

    function setRewardRate(
        uint256 poolId,
        uint256 newRate
    )
        external
        onlyOwner
        validPool(poolId)
        updateReward(poolId, address(0))
    {
        Pool storage pool = pools[poolId];
        uint256 oldRate = pool.rewardRate;
        pool.rewardRate = newRate;

        emit RewardRateChanged(poolId, oldRate, newRate);
    }

    function fundRewards(
        uint256 poolId,
        uint256 amount
    )
        external
        onlyOwner
        validPool(poolId)
        nonReentrant
    {
        if (amount == 0) revert ZeroAmount();

        Pool storage pool = pools[poolId];

        pool.rewardToken.safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );

        pool.rewardBalance += amount;

        emit RewardsFunded(poolId, amount);
    }

    function stake(
        uint256 poolId,
        uint256 amount,
        uint256 lockDuration
    )
        external
        validPool(poolId)
        nonReentrant
        whenNotPaused
        updateReward(poolId, msg.sender)
    {
        if (amount == 0) revert ZeroAmount();

        Pool storage pool = pools[poolId];
        if (!pool.active) revert PoolInactive();

        if (lockDuration > MAX_LOCK_DURATION) {
            revert InvalidLockDuration();
        }

        Position storage p = positions[poolId][msg.sender];

        uint256 multiplierBps = lockMultiplier(lockDuration);

        if (p.amount > 0 && block.timestamp < p.lockEnd) {
            if (multiplierBps < p.multiplierBps) {
                multiplierBps = p.multiplierBps;
            }
        }

        uint256 oldWeight = p.weight;

        p.amount += amount;
        p.multiplierBps = multiplierBps;

        uint256 newLockEnd = block.timestamp + lockDuration;
        if (newLockEnd > p.lockEnd) {
            p.lockEnd = newLockEnd;
        }

        p.weight = (p.amount * p.multiplierBps) / BPS;

        pool.totalStaked += amount;
        pool.totalWeight = pool.totalWeight - oldWeight + p.weight;

        pool.stakingToken.safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );

        emit Staked(
            poolId,
            msg.sender,
            amount,
            p.lockEnd,
            p.multiplierBps
        );
    }

    function withdraw(
        uint256 poolId,
        uint256 amount
    )
        public
        validPool(poolId)
        nonReentrant
        updateReward(poolId, msg.sender)
    {
        if (amount == 0) revert ZeroAmount();

        Position storage p = positions[poolId][msg.sender];

        if (block.timestamp < p.lockEnd) {
            revert PositionLocked(p.lockEnd);
        }

        require(p.amount >= amount, "insufficient stake");

        Pool storage pool = pools[poolId];

        uint256 oldWeight = p.weight;

        p.amount -= amount;

        if (p.amount == 0) {
            p.multiplierBps = BPS;
            p.lockEnd = 0;
            p.weight = 0;
        } else {
            p.weight = (p.amount * p.multiplierBps) / BPS;
        }

        pool.totalStaked -= amount;
        pool.totalWeight = pool.totalWeight - oldWeight + p.weight;

        pool.stakingToken.safeTransfer(msg.sender, amount);

        emit Withdrawn(poolId, msg.sender, amount);
    }

    function claim(
        uint256 poolId
    )
        public
        validPool(poolId)
        nonReentrant
        updateReward(poolId, msg.sender)
    {
        Position storage p = positions[poolId][msg.sender];
        uint256 reward = p.rewards;

        if (reward == 0) return;

        Pool storage pool = pools[poolId];

        if (reward > pool.rewardBalance) {
            revert InsufficientRewardBalance();
        }

        p.rewards = 0;
        pool.rewardBalance -= reward;

        pool.rewardToken.safeTransfer(msg.sender, reward);

        emit RewardPaid(poolId, msg.sender, reward);
    }

    function exit(
        uint256 poolId
    ) external validPool(poolId) {
        uint256 amount = positions[poolId][msg.sender].amount;

        if (amount > 0) {
            withdraw(poolId, amount);
        }

        claim(poolId);
    }

    function rewardPerWeight(
        uint256 poolId
    ) public view validPool(poolId) returns (uint256) {
        Pool storage pool = pools[poolId];

        if (pool.totalWeight == 0) {
            return pool.rewardPerWeightStored;
        }

        uint256 elapsed = block.timestamp - pool.lastUpdateTime;

        return
            pool.rewardPerWeightStored +
            ((elapsed * pool.rewardRate * PRECISION) / pool.totalWeight);
    }

    function earned(
        uint256 poolId,
        address account
    ) public view validPool(poolId) returns (uint256) {
        Position storage p = positions[poolId][account];

        return
            ((p.weight *
                (rewardPerWeight(poolId) - p.rewardPerWeightPaid)) /
                PRECISION) +
            p.rewards;
    }

    function lockMultiplier(
        uint256 lockDuration
    ) public pure returns (uint256) {
        if (lockDuration > MAX_LOCK_DURATION) {
            revert InvalidLockDuration();
        }

        if (lockDuration == 0) {
            return BPS;
        }

        uint256 bonus =
            (lockDuration * (MAX_MULTIPLIER_BPS - BPS)) /
            MAX_LOCK_DURATION;

        return BPS + bonus;
    }

    function poolCount() external view returns (uint256) {
        return pools.length;
    }

    function getPosition(
        uint256 poolId,
        address account
    )
        external
        view
        validPool(poolId)
        returns (
            uint256 amount,
            uint256 weight,
            uint256 lockEnd,
            uint256 multiplierBps,
            uint256 pendingRewards
        )
    {
        Position storage p = positions[poolId][account];

        return (
            p.amount,
            p.weight,
            p.lockEnd,
            p.multiplierBps,
            earned(poolId, account)
        );
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
