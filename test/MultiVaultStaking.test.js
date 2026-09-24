const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("MultiVaultStaking", function () {
    let owner;
    let alice;
    let bob;
    let stakeToken;
    let rewardToken;
    let staking;

    const parse = ethers.parseEther;

    beforeEach(async function () {
        [owner, alice, bob] = await ethers.getSigners();

        const MockERC20 = await ethers.getContractFactory("MockERC20");

        stakeToken = await MockERC20.deploy("Stake Token", "STK");
        rewardToken = await MockERC20.deploy("Reward Token", "RWD");

        await stakeToken.waitForDeployment();
        await rewardToken.waitForDeployment();

        const MultiVaultStaking =
            await ethers.getContractFactory("MultiVaultStaking");

        staking = await MultiVaultStaking.deploy(owner.address);
        await staking.waitForDeployment();

        await staking.createPool(
            await stakeToken.getAddress(),
            await rewardToken.getAddress(),
            parse("1")
        );

        await stakeToken.mint(alice.address, parse("1000"));
        await stakeToken.mint(bob.address, parse("1000"));
        await rewardToken.mint(owner.address, parse("100000"));

        await rewardToken.approve(
            await staking.getAddress(),
            parse("100000")
        );

        await staking.fundRewards(0, parse("100000"));

        await stakeToken
            .connect(alice)
            .approve(await staking.getAddress(), parse("1000"));

        await stakeToken
            .connect(bob)
            .approve(await staking.getAddress(), parse("1000"));
    });

    it("creates a pool correctly", async function () {
        expect(await staking.poolCount()).to.equal(1);

        const pool = await staking.pools(0);

        expect(pool.stakingToken)
            .to.equal(await stakeToken.getAddress());

        expect(pool.rewardToken)
            .to.equal(await rewardToken.getAddress());

        expect(pool.active).to.equal(true);
    });

    it("allows staking without a lock", async function () {
        await staking
            .connect(alice)
            .stake(0, parse("100"), 0);

        const position =
            await staking.getPosition(0, alice.address);

        expect(position.amount).to.equal(parse("100"));
        expect(position.multiplierBps).to.equal(10000);
    });

    it("gives a higher multiplier for long locks", async function () {
        const oneYear = 365 * 24 * 60 * 60;

        await staking
            .connect(alice)
            .stake(0, parse("100"), oneYear);

        const position =
            await staking.getPosition(0, alice.address);

        expect(position.multiplierBps).to.equal(25000);
        expect(position.weight).to.equal(parse("250"));
    });

    it("accrues rewards over time", async function () {
        await staking
            .connect(alice)
            .stake(0, parse("100"), 0);

        await ethers.provider.send(
            "evm_increaseTime",
            [10]
        );

        await ethers.provider.send("evm_mine", []);

        const reward =
            await staking.earned(0, alice.address);

        expect(reward).to.be.gt(0);
    });

    it("prevents withdrawing before lock expiry", async function () {
        const sevenDays = 7 * 24 * 60 * 60;

        await staking
            .connect(alice)
            .stake(0, parse("100"), sevenDays);

        await expect(
            staking
                .connect(alice)
                .withdraw(0, parse("10"))
        ).to.be.revertedWithCustomError(
            staking,
            "PositionLocked"
        );
    });

    it("allows withdrawal after lock expiry", async function () {
        const sevenDays = 7 * 24 * 60 * 60;

        await staking
            .connect(alice)
            .stake(0, parse("100"), sevenDays);

        await ethers.provider.send(
            "evm_increaseTime",
            [sevenDays + 1]
        );

        await ethers.provider.send("evm_mine", []);

        await staking
            .connect(alice)
            .withdraw(0, parse("100"));

        const position =
            await staking.getPosition(0, alice.address);

        expect(position.amount).to.equal(0);
    });

    it("allows users to claim rewards", async function () {
        await staking
            .connect(alice)
            .stake(0, parse("100"), 0);

        await ethers.provider.send(
            "evm_increaseTime",
            [20]
        );

        await ethers.provider.send("evm_mine", []);

        const before =
            await rewardToken.balanceOf(alice.address);

        await staking.connect(alice).claim(0);

        const after =
            await rewardToken.balanceOf(alice.address);

        expect(after).to.be.gt(before);
    });

    it("lets the owner pause staking", async function () {
        await staking.pause();

        await expect(
            staking
                .connect(alice)
                .stake(0, parse("10"), 0)
        ).to.be.revertedWithCustomError(
            staking,
            "EnforcedPause"
        );
    });
});
