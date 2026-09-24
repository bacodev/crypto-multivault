const hre = require("hardhat");

async function main() {
    const [deployer] = await hre.ethers.getSigners();

    const MockERC20 =
        await hre.ethers.getContractFactory("MockERC20");

    const stake =
        await MockERC20.deploy("Demo Stake Token", "DST");

    const reward =
        await MockERC20.deploy("Demo Reward Token", "DRT");

    await stake.waitForDeployment();
    await reward.waitForDeployment();

    const MultiVaultStaking =
        await hre.ethers.getContractFactory("MultiVaultStaking");

    const staking =
        await MultiVaultStaking.deploy(deployer.address);

    await staking.waitForDeployment();

    const rewardRate = hre.ethers.parseEther("0.01");

    await staking.createPool(
        await stake.getAddress(),
        await reward.getAddress(),
        rewardRate
    );

    await reward.mint(
        deployer.address,
        hre.ethers.parseEther("100000")
    );

    await reward.approve(
        await staking.getAddress(),
        hre.ethers.parseEther("100000")
    );

    await staking.fundRewards(
        0,
        hre.ethers.parseEther("100000")
    );

    console.log("Stake token:", await stake.getAddress());
    console.log("Reward token:", await reward.getAddress());
    console.log("Staking:", await staking.getAddress());
    console.log("Pool ID: 0");
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
