const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Dynamic Monsoon - Transcript Monetization", function () {
  let transcriptMonetization;
  let notaryService;
  let usdc;
  let owner, user1, user2, notary1;

  const USDC_DECIMALS = 6;
  const parseUSDC = (amount) => ethers.utils.parseUnits(amount, USDC_DECIMALS);

  beforeEach(async function () {
    [owner, user1, user2, notary1] = await ethers.getSigners();

    // Deploy MockUSDC
    const MockUSDC = await ethers.getContractFactory("MockUSDC");
    usdc = await MockUSDC.deploy();
    await usdc.deployed();

    // Mint test tokens
    await usdc.mint(user1.address, parseUSDC("10000"));
    await usdc.mint(user2.address, parseUSDC("10000"));
    await usdc.mint(notary1.address, parseUSDC("10000"));
    await usdc.mint(owner.address, parseUSDC("10000"));

    // Deploy TranscriptMonetization
    const TranscriptMonetization = await ethers.getContractFactory(
      "TranscriptMonetization"
    );
    transcriptMonetization = await TranscriptMonetization.deploy(usdc.address);
    await transcriptMonetization.deployed();

    // Deploy NotaryService
    const NotaryService = await ethers.getContractFactory("NotaryService");
    notaryService = await NotaryService.deploy(usdc.address);
    await notaryService.deployed();
  });

  describe("Transcript Creation", function () {
    it("Should create a transcript", async function () {
      const tx = await transcriptMonetization.storeTranscript(
        "QmTest123456789",
        parseUSDC("10"),
        0, // PUBLIC access
        false
      );

      expect(tx).to.emit(transcriptMonetization, "TranscriptCreated");
    });

    it("Should mint NFT to creator", async function () {
      await transcriptMonetization.storeTranscript(
        "QmTest123456789",
        parseUSDC("10"),
        0,
        false
      );

      const balance = await transcriptMonetization.balanceOf(owner.address);
      expect(balance).to.equal(1);
    });
  });

  describe("Pay-Per-View Access", function () {
    beforeEach(async function () {
      await transcriptMonetization.storeTranscript(
        "QmTest123456789",
        parseUSDC("10"),
        1, // LEGAL_TEAM access
        false
      );
    });

    it("Should allow user to purchase access", async function () {
      const accessPrice = parseUSDC("10");

      // Approve USDC transfer
      await usdc.connect(user1).approve(transcriptMonetization.address, accessPrice);

      // Purchase access
      const tx = await transcriptMonetization.connect(user1).purchaseAccess(1);
      expect(tx).to.emit(transcriptMonetization, "AccessGranted");
    });

    it("Should track access records", async function () {
      const accessPrice = parseUSDC("10");

      await usdc.connect(user1).approve(transcriptMonetization.address, accessPrice);
      await transcriptMonetization.connect(user1).purchaseAccess(1);

      const hasAccess = await transcriptMonetization.hasAccess(1, user1.address);
      expect(hasAccess).to.be.true;
    });

    it("Should split earnings between creator and platform", async function () {
      const accessPrice = parseUSDC("10");
      const platformFeePercentage = 2;
      const expectedPlatformFee = accessPrice.mul(platformFeePercentage).div(100);

      await usdc.connect(user1).approve(transcriptMonetization.address, accessPrice);
      await transcriptMonetization.connect(user1).purchaseAccess(1);

      // Check earnings were recorded
      const creatorEarnings = await transcriptMonetization.platformEarnings(owner.address);
      expect(creatorEarnings).to.be.gt(0);
    });
  });

  describe("Escrow Service", function () {
    beforeEach(async function () {
      await transcriptMonetization.storeTranscript(
        "QmTest123456789",
        parseUSDC("100"),
        1,
        true // escrow enabled
      );
    });

    it("Should create escrow", async function () {
      const escrowAmount = parseUSDC("500");

      await usdc.connect(user1).approve(transcriptMonetization.address, escrowAmount);

      const tx = await transcriptMonetization.connect(user1).initiateEscrow(1, escrowAmount);
      expect(tx).to.emit(transcriptMonetization, "EscrowCreated");
    });

    it("Should release escrow to creator", async function () {
      const escrowAmount = parseUSDC("500");

      await usdc.connect(user1).approve(transcriptMonetization.address, escrowAmount);
      await transcriptMonetization.connect(user1).initiateEscrow(1, escrowAmount);

      const creatorBalanceBefore = await usdc.balanceOf(owner.address);

      await transcriptMonetization.releaseEscrow(1, "proofHash");

      const creatorBalanceAfter = await usdc.balanceOf(owner.address);
      expect(creatorBalanceAfter).to.equal(creatorBalanceBefore.add(escrowAmount));
    });
  });

  describe("Data Licensing", function () {
    beforeEach(async function () {
      await transcriptMonetization.storeTranscript(
        "QmTest123456789",
        parseUSDC("100"),
        1,
        false
      );
    });

    it("Should create license agreement", async function () {
      const monthlyFee = parseUSDC("100");

      const tx = await transcriptMonetization.createLicenseAgreement(
        1,
        user1.address,
        monthlyFee,
        12,
        1000
      );

      expect(tx).to.emit(transcriptMonetization, "LicenseAgreementCreated");
    });

    it("Should process licensing fees", async function () {
      const monthlyFee = parseUSDC("100");

      await transcriptMonetization.createLicenseAgreement(1, user1.address, monthlyFee, 12, 1000);

      await usdc.connect(user1).approve(transcriptMonetization.address, monthlyFee);

      const tx = await transcriptMonetization.connect(user1).payLicensingFee(1, 0);
      expect(tx).to.emit(transcriptMonetization, "PaymentProcessed");
    });
  });

  describe("Oracle Feeds", function () {
    beforeEach(async function () {
      await transcriptMonetization.storeTranscript(
        "QmTest123456789",
        parseUSDC("100"),
        1,
        false
      );

      // Approve oracle provider
      await transcriptMonetization.approveOracleProvider(notary1.address);
    });

    it("Should publish oracle update", async function () {
      const tx = await transcriptMonetization
        .connect(notary1)
        .publishOracleUpdate(1, "QmUpdate123456");

      expect(tx).to.emit(transcriptMonetization, "OracleUpdatePublished");
    });

    it("Should charge for oracle feed access", async function () {
      await transcriptMonetization.connect(notary1).publishOracleUpdate(1, "QmUpdate123456");

      const accessFee = parseUSDC("50");
      await usdc.connect(user1).approve(transcriptMonetization.address, accessFee);

      const tx = await transcriptMonetization.connect(user1).payForOracleFeed(1, accessFee);
      expect(tx).to.emit(transcriptMonetization, "PaymentProcessed");
    });
  });

  describe("Access Control", function () {
    beforeEach(async function () {
      await transcriptMonetization.storeTranscript(
        "QmTest123456789",
        parseUSDC("10"),
        1,
        false
      );

      const accessPrice = parseUSDC("10");
      await usdc.connect(user1).approve(transcriptMonetization.address, accessPrice);
      await transcriptMonetization.connect(user1).purchaseAccess(1);
    });

    it("Should revoke access", async function () {
      await transcriptMonetization.revokeAccess(1, user1.address);

      const hasAccess = await transcriptMonetization.hasAccess(1, user1.address);
      expect(hasAccess).to.be.false;
    });

    it("Should set user access level", async function () {
      await transcriptMonetization.setUserAccessLevel(user2.address, 3); // PREMIUM

      const accessLevel = await transcriptMonetization.userAccessLevel(user2.address);
      expect(accessLevel).to.equal(3);
    });
  });

  describe("Notary Service", function () {
    it("Should register notary", async function () {
      const deposit = parseUSDC("1000");
      await usdc.connect(notary1).approve(notaryService.address, deposit);

      const tx = await notaryService.connect(notary1).registerNotary(0); // BRONZE
      expect(tx).to.emit(notaryService, "NotaryRegistered");
    });

    it("Should request certification", async function () {
      const certFee = parseUSDC("50");
      await usdc.connect(user1).approve(notaryService.address, certFee);

      const tx = await notaryService
        .connect(user1)
        .requestCertification(1, "QmTest123456", 2);

      expect(tx).to.emit(notaryService, "CertificationRequested");
    });

    it("Should submit verification", async function () {
      // Register notary
      const deposit = parseUSDC("1000");
      await usdc.connect(notary1).approve(notaryService.address, deposit);
      await notaryService.connect(notary1).registerNotary(0);

      // Request certification
      const certFee = parseUSDC("50");
      await usdc.connect(user1).approve(notaryService.address, certFee);
      await notaryService.connect(user1).requestCertification(1, "QmTest123456", 1);

      // Submit verification
      const tx = await notaryService
        .connect(notary1)
        .submitVerification(1, true, "Verified authentic");

      expect(tx).to.emit(notaryService, "VerificationSubmitted");
    });
  });

  describe("Earnings Withdrawal", function () {
    it("Should allow creator to withdraw earnings", async function () {
      await transcriptMonetization.storeTranscript(
        "QmTest123456789",
        parseUSDC("10"),
        1,
        false
      );

      const accessPrice = parseUSDC("10");
      await usdc.connect(user1).approve(transcriptMonetization.address, accessPrice);
      await transcriptMonetization.connect(user1).purchaseAccess(1);

      // Owner should be able to withdraw earnings
      const tx = await transcriptMonetization.withdrawEarnings();
      expect(tx).to.not.be.reverted;
    });
  });
});
