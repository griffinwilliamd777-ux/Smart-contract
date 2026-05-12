const hre = require("hardhat");
const fs = require("fs");

async function main() {
  console.log("🚀 Deploying Dynamic Monsoon...\n");

  // Get deployer account
  const [deployer] = await hre.ethers.getSigners();
  console.log(`📍 Deploying with account: ${deployer.address}\n`);

  // Deploy MockUSDC first (if on local network)
  let usdcAddress;
  if (hre.network.name === "hardhat" || hre.network.name === "localhost") {
    console.log("📦 Deploying MockUSDC...");
    const MockUSDC = await hre.ethers.getContractFactory("MockUSDC");
    const usdc = await MockUSDC.deploy();
    await usdc.deployed();
    usdcAddress = usdc.address;
    console.log(`✅ MockUSDC deployed to: ${usdcAddress}\n`);

    // Mint test tokens
    const mintAmount = hre.ethers.utils.parseUnits("100000", 6);
    await usdc.mint(deployer.address, mintAmount);
    console.log(`💰 Minted 100,000 USDC to deployer\n`);
  } else {
    // Use actual USDC on testnets
    usdcAddress = process.env.USDC_ADDRESS || "0x0";
    console.log(`📍 Using USDC at: ${usdcAddress}\n`);
  }

  // Deploy TranscriptMonetization
  console.log("📦 Deploying TranscriptMonetization...");
  const TranscriptMonetization = await hre.ethers.getContractFactory(
    "TranscriptMonetization"
  );
  const transcriptMonetization = await TranscriptMonetization.deploy(usdcAddress);
  await transcriptMonetization.deployed();
  console.log(`✅ TranscriptMonetization deployed to: ${transcriptMonetization.address}\n`);

  // Deploy NotaryService
  console.log("📦 Deploying NotaryService...");
  const NotaryService = await hre.ethers.getContractFactory("NotaryService");
  const notaryService = await NotaryService.deploy(usdcAddress);
  await notaryService.deployed();
  console.log(`✅ NotaryService deployed to: ${notaryService.address}\n`);

  // Save deployment addresses
  const deploymentData = {
    network: hre.network.name,
    deployer: deployer.address,
    timestamp: new Date().toISOString(),
    contracts: {
      MockUSDC: usdcAddress,
      TranscriptMonetization: transcriptMonetization.address,
      NotaryService: notaryService.address,
    },
  };

  const deploymentDir = "./deployments";
  if (!fs.existsSync(deploymentDir)) {
    fs.mkdirSync(deploymentDir);
  }

  const filename = `${deploymentDir}/${hre.network.name}.json`;
  fs.writeFileSync(filename, JSON.stringify(deploymentData, null, 2));

  console.log("📋 Deployment Summary:");
  console.log("========================");
  console.log(`Network: ${hre.network.name}`);
  console.log(`Deployer: ${deployer.address}`);
  console.log(`MockUSDC: ${usdcAddress}`);
  console.log(`TranscriptMonetization: ${transcriptMonetization.address}`);
  console.log(`NotaryService: ${notaryService.address}`);
  console.log(`\n✅ Deployment saved to: ${filename}\n`);

  console.log("🎉 Deployment complete!");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
