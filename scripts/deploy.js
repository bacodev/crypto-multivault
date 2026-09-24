const hre = require("hardhat");

async function main() {
    const [deployer] = await hre.ethers.getSigners();

    console.log("Deploying with:", deployer.address);

    const MultiVaultStaking =
        await hre.ethers.getContractFactory("MultiVaultStaking");

    const staking =
        await MultiVaultStaking.deploy(deployer.address);

    await staking.waitForDeployment();

    console.log(
        "MultiVaultStaking:",
        await staking.getAddress()
    );
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
