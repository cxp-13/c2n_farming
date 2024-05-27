// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract FarmingC2N is Ownable {
    using Math for uint256;
    using SafeERC20 for IERC20;

    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. ERC20s to distribute per block.
        uint256 lastRewardTimestamp; // Last timstamp that ERC20s distribution occurs.
        uint256 accERC20PerShare; // Accumulated ERC20s per share, times 1e36.
        uint256 totalDeposits; // Total amount of tokens deposited at the moment (staked)
    }

    // Address of the ERC20 Token contract.
    IERC20 public erc20;
    // The total amount of ERC20 that's paid out as reward.
    uint256 public paidOut;
    // ERC20 tokens rewarded per second.
    uint256 public rewardPerSecond;
    // Total rewards added to farm
    uint256 public totalRewards;
    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint;

    // The timestamp when farming starts.
    uint256 public startTimestamp;
    // The timestamp when farming ends.
    uint256 public endTimestamp;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount
    );

    constructor(
        IERC20 _erc20,
        uint256 _rewardPerSecond,
        uint256 _startTimestamp
    ) Ownable(msg.sender) {
        erc20 = _erc20;
        rewardPerSecond = _rewardPerSecond;
        startTimestamp = _startTimestamp;
        endTimestamp = _startTimestamp;
    }

    // Number of LP pools
    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Fund the farm, increase the end block
    function fund(uint256 _amount) public {
        require(
            block.timestamp < endTimestamp,
            "fund: too late, the farm is closed"
        );
        erc20.safeTransferFrom(address(msg.sender), address(this), _amount);
        (, uint256 timestamp) = _amount.tryDiv(rewardPerSecond);
        endTimestamp += timestamp;

        (, totalRewards) = totalRewards.tryAdd(_amount);
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(
        uint256 _allocPoint,
        IERC20 _lpToken,
        bool _withUpdate
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardTimestamp = block.timestamp > startTimestamp
            ? block.timestamp
            : startTimestamp;
        (, totalAllocPoint) = totalAllocPoint.tryAdd(_allocPoint);
        poolInfo.push(
            PoolInfo({
                lpToken: _lpToken,
                allocPoint: _allocPoint,
                lastRewardTimestamp: lastRewardTimestamp,
                accERC20PerShare: 0,
                totalDeposits: 0
            })
        );
    }

    // Update the given pool's ERC20 allocation point. Can only be called by the owner.
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        bool _withUpdate
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        (, totalAllocPoint) = totalAllocPoint.trySub(poolInfo[_pid].allocPoint);

        (, totalAllocPoint) = totalAllocPoint.tryAdd(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    // View function to see deposited LP for a user.
    function deposited(
        uint256 _pid,
        address _user
    ) external view returns (uint256) {
        UserInfo storage user = userInfo[_pid][_user];
        return user.amount;
    }

    // View function to see pending ERC20s for a user.
    function pending(
        uint256 _pid,
        address _user
    ) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accERC20PerShare = pool.accERC20PerShare;
        uint256 userAmount = user.amount;

        uint256 lpSupply = pool.totalDeposits;

        if (block.timestamp > pool.lastRewardTimestamp && lpSupply != 0) {
            uint256 lastTimestamp = block.timestamp < endTimestamp
                ? block.timestamp
                : endTimestamp;
            uint256 timestampToCompare = pool.lastRewardTimestamp < endTimestamp
                ? pool.lastRewardTimestamp
                : endTimestamp;
            (, uint256 nrOfSeconds) = lastTimestamp.trySub(timestampToCompare);
            uint newAccERC20PerShare = getNewAccERC20PerShare(
                nrOfSeconds,
                pool.allocPoint,
                lpSupply
            );
            // (, uint256 erc20Reward) = nrOfSeconds.tryMul(rewardPerSecond);
            // erc20Reward = erc20Reward.mulDiv(pool.allocPoint, totalAllocPoint);

            // (, uint256 newAccERC20PerShare) = erc20Reward.tryDiv(lpSupply);

            (, accERC20PerShare) = accERC20PerShare.tryAdd(newAccERC20PerShare);
        }

        (, uint256 totalReward) = userAmount.tryMul(accERC20PerShare);
        (, uint256 result) = totalReward.trySub(user.rewardDebt);

        return result;
    }

    // View function for total reward the farm has yet to pay out.
    function totalPending() external view returns (uint256) {
        if (block.timestamp <= startTimestamp) {
            return 0;
        }

        uint256 lastTimestamp = block.timestamp < endTimestamp
            ? block.timestamp
            : endTimestamp;

        (, uint256 totalSave) = rewardPerSecond.tryMul(
            lastTimestamp - startTimestamp
        );
        (, uint256 result) = totalSave.trySub(paidOut);

        return result;
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        uint256 lastTimestamp = block.timestamp < endTimestamp
            ? block.timestamp
            : endTimestamp;

        if (lastTimestamp <= pool.lastRewardTimestamp) {
            return;
        }
        uint256 lpSupply = pool.totalDeposits;

        if (lpSupply == 0) {
            pool.lastRewardTimestamp = lastTimestamp;
            return;
        }

        (, uint256 nrOfSeconds) = lastTimestamp.trySub(
            pool.lastRewardTimestamp
        );

        uint newAccERC20PerShare = getNewAccERC20PerShare(
            nrOfSeconds,
            pool.allocPoint,
            lpSupply
        );

        // (, uint256 erc20Reward) = nrOfSeconds.tryMul(rewardPerSecond);

        // erc20Reward = erc20Reward.mulDiv(pool.allocPoint, totalAllocPoint);

        // (, uint256 newAccERC20PerShare) = erc20Reward.tryDiv(lpSupply);

        (, pool.accERC20PerShare) = pool.accERC20PerShare.tryAdd(
            newAccERC20PerShare
        );
        pool.lastRewardTimestamp = block.timestamp;
    }

    function getNewAccERC20PerShare(
        uint nrOfSeconds,
        uint curPoolAllocPoint,
        uint lpSupply
    ) internal view returns (uint256 newAccERC20PerShare) {
        (, uint256 erc20Reward) = nrOfSeconds.tryMul(rewardPerSecond);

        erc20Reward = erc20Reward.mulDiv(curPoolAllocPoint, totalAllocPoint);

        (, newAccERC20PerShare) = erc20Reward.tryDiv(lpSupply);
    }

    // Deposit LP tokens to Farm for ERC20 allocation.
    function deposit(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        updatePool(_pid);

        if (user.amount > 0) {
            (, uint256 userReward) = user.amount.tryMul(pool.accERC20PerShare);
            (, uint256 pendingAmount) = userReward.trySub(user.rewardDebt);

            erc20Transfer(msg.sender, pendingAmount);
        }

        pool.lpToken.safeTransferFrom(
            address(msg.sender),
            address(this),
            _amount
        );
        (, pool.totalDeposits) = pool.totalDeposits.tryAdd(_amount);

        (, user.amount) = user.amount.tryAdd(_amount);
        (, user.rewardDebt) = user.amount.tryMul(pool.accERC20PerShare);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from Farm.
    function withdraw(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(
            user.amount >= _amount,
            "withdraw: can't withdraw more than deposit"
        );
        updatePool(_pid);

        (, uint256 userReward) = user.amount.tryMul(pool.accERC20PerShare);
        (, uint256 pendingAmount) = userReward.trySub(user.rewardDebt);
        erc20Transfer(msg.sender, pendingAmount);
        (, user.amount) = user.amount.trySub(_amount);
        (, user.rewardDebt) = user.amount.tryMul(pool.accERC20PerShare);
        pool.lpToken.safeTransfer(address(msg.sender), _amount);
        (, pool.totalDeposits) = pool.totalDeposits.trySub(_amount);

        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        pool.lpToken.safeTransfer(address(msg.sender), user.amount);
        (, pool.totalDeposits) = pool.totalDeposits.trySub(user.amount);
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        delete userInfo[_pid][msg.sender];
    }

    // Transfer ERC20 and update the required ERC20 to payout all rewards
    function erc20Transfer(address _to, uint256 _amount) internal {
        erc20.transfer(_to, _amount);
        paidOut += _amount;
    }
}
