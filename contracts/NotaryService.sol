// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title NotaryService
 * @dev Manages a decentralized notary network for IP certification and verification
 * Features: Tiered notary system, reputation scoring, multi-signature verification
 */
contract NotaryService is Ownable, ReentrancyGuard {
    
    // ==================== Enums ====================
    enum NotaryTier { BRONZE, SILVER, GOLD, PLATINUM }
    
    // ==================== Structs ====================
    struct Notary {
        address notaryAddress;
        NotaryTier tier;
        uint256 reputation; // 0-100
        uint256 securityDeposit;
        bool isActive;
        uint256 certificationsIssued;
        uint256 registeredAt;
    }
    
    struct CertificationRequest {
        uint256 requestId;
        uint256 transcriptId;
        string ipfsHash;
        address requester;
        uint256 requiredNotaries;
        uint256 approvalsReceived;
        mapping(address => bool) hasVerified;
        mapping(address => string) verificationNotes;
        bool isApproved;
        uint256 createdAt;
        uint256 expiresAt;
    }
    
    // ==================== State Variables ====================
    IERC20 public stablecoin;
    uint256 public nextRequestId = 1;
    uint256 public certificateFee = 50e6; // 50 USDC (6 decimals)
    uint256 public minimumSecurityDeposit = 1000e6; // 1000 USDC
    
    mapping(address => Notary) public notaries;
    mapping(uint256 => CertificationRequest) public certifications;
    mapping(address => uint256) public notaryEarnings;
    mapping(address => bool) public approvedNotaries;
    
    uint256 public totalNotaries = 0;
    uint256 public totalCertifications = 0;
    
    // ==================== Events ====================
    event NotaryRegistered(address indexed notary, NotaryTier tier);
    event NotaryDeactivated(address indexed notary);
    event CertificationRequested(uint256 indexed requestId, address indexed requester, uint256 requiredNotaries);
    event VerificationSubmitted(uint256 indexed requestId, address indexed notary, bool approved);
    event CertificationApproved(uint256 indexed requestId);
    event CertificationRejected(uint256 indexed requestId);
    event ReputationUpdated(address indexed notary, uint256 newReputation);
    event TierUpgraded(address indexed notary, NotaryTier newTier);
    
    // ==================== Modifiers ====================
    modifier onlyActiveNotary() {
        require(notaries[msg.sender].isActive, "Not an active notary");
        _;
    }
    
    modifier certificationExists(uint256 requestId) {
        require(certifications[requestId].createdAt > 0, "Certification does not exist");
        _;
    }
    
    // ==================== Constructor ====================
    constructor(address _stablecoin) {
        stablecoin = IERC20(_stablecoin);
    }
    
    // ==================== Notary Management ====================
    
    /**
     * @dev Register as a notary
     * @param initialTier Starting tier (usually BRONZE)
     */
    function registerNotary(NotaryTier initialTier) public nonReentrant {
        require(!notaries[msg.sender].isActive, "Already registered as notary");
        
        // Deposit security amount
        require(
            stablecoin.transferFrom(msg.sender, address(this), minimumSecurityDeposit),
            "Insufficient deposit"
        );
        
        notaries[msg.sender] = Notary({
            notaryAddress: msg.sender,
            tier: initialTier,
            reputation: initialTier == NotaryTier.BRONZE ? 30 : 0,
            securityDeposit: minimumSecurityDeposit,
            isActive: true,
            certificationsIssued: 0,
            registeredAt: block.timestamp
        });
        
        approvedNotaries[msg.sender] = true;
        totalNotaries++;
        
        emit NotaryRegistered(msg.sender, initialTier);
    }
    
    /**
     * @dev Deactivate as a notary
     */
    function deactivateNotary() public nonReentrant {
        require(notaries[msg.sender].isActive, "Not an active notary");
        
        Notary storage notary = notaries[msg.sender];
        notary.isActive = false;
        approvedNotaries[msg.sender] = false;
        
        // Return security deposit minus any slashing
        uint256 returnAmount = notary.securityDeposit;
        require(stablecoin.transfer(msg.sender, returnAmount), "Deposit return failed");
        
        emit NotaryDeactivated(msg.sender);
    }
    
    /**
     * @dev Update notary reputation
     * @param notaryAddress The notary address
     * @param newReputation New reputation score (0-100)
     */
    function updateReputation(address notaryAddress, uint256 newReputation) 
        public 
        onlyOwner 
    {
        require(newReputation <= 100, "Reputation must be <= 100");
        require(notaries[notaryAddress].isActive, "Notary not active");
        
        Notary storage notary = notaries[notaryAddress];
        notary.reputation = newReputation;
        
        // Check for tier upgrade
        NotaryTier oldTier = notary.tier;
        if (newReputation >= 90 && oldTier != NotaryTier.PLATINUM) {
            notary.tier = NotaryTier.PLATINUM;
            emit TierUpgraded(notaryAddress, NotaryTier.PLATINUM);
        } else if (newReputation >= 75 && oldTier != NotaryTier.GOLD && oldTier != NotaryTier.PLATINUM) {
            notary.tier = NotaryTier.GOLD;
            emit TierUpgraded(notaryAddress, NotaryTier.GOLD);
        } else if (newReputation >= 60 && oldTier == NotaryTier.BRONZE) {
            notary.tier = NotaryTier.SILVER;
            emit TierUpgraded(notaryAddress, NotaryTier.SILVER);
        }
        
        emit ReputationUpdated(notaryAddress, newReputation);
    }
    
    /**
     * @dev Slash security deposit for malicious behavior
     * @param notaryAddress The notary to slash
     * @param slashAmount Amount to slash
     */
    function slashDeposit(address notaryAddress, uint256 slashAmount) 
        public 
        onlyOwner 
    {
        Notary storage notary = notaries[notaryAddress];
        require(notary.isActive, "Notary not active");
        require(slashAmount <= notary.securityDeposit, "Slash exceeds deposit");
        
        notary.securityDeposit -= slashAmount;
        
        if (notary.reputation > 10) {
            notary.reputation -= 10;
        } else {
            notary.isActive = false;
        }
    }
    
    // ==================== Certification Functions ====================
    
    /**
     * @dev Request IP certification from notaries
     * @param transcriptId The ID of the transcript
     * @param ipfsHash IPFS hash of the content
     * @param requiredNotaries Number of notaries needed for consensus
     */
    function requestCertification(
        uint256 transcriptId,
        string memory ipfsHash,
        uint256 requiredNotaries
    ) public nonReentrant returns (uint256) {
        require(requiredNotaries >= 1 && requiredNotaries <= 5, "Invalid notary count");
        require(totalNotaries >= requiredNotaries, "Not enough active notaries");
        
        // Charge certification fee
        require(
            stablecoin.transferFrom(msg.sender, address(this), certificateFee),
            "Fee payment failed"
        );
        
        uint256 requestId = nextRequestId++;
        CertificationRequest storage cert = certifications[requestId];
        
        cert.requestId = requestId;
        cert.transcriptId = transcriptId;
        cert.ipfsHash = ipfsHash;
        cert.requester = msg.sender;
        cert.requiredNotaries = requiredNotaries;
        cert.approvalsReceived = 0;
        cert.isApproved = false;
        cert.createdAt = block.timestamp;
        cert.expiresAt = block.timestamp + 7 days;
        
        totalCertifications++;
        
        emit CertificationRequested(requestId, msg.sender, requiredNotaries);
        
        return requestId;
    }
    
    /**
     * @dev Submit verification for a certification request
     * @param requestId The certification request ID
     * @param approved Whether the notary approves
     * @param notes Notes from the notary
     */
    function submitVerification(
        uint256 requestId,
        bool approved,
        string memory notes
    ) 
        public 
        nonReentrant 
        onlyActiveNotary 
        certificationExists(requestId) 
    {
        CertificationRequest storage cert = certifications[requestId];
        
        require(cert.createdAt > 0, "Certification expired");
        require(block.timestamp <= cert.expiresAt, "Certification request expired");
        require(!cert.hasVerified[msg.sender], "Already verified");
        
        cert.hasVerified[msg.sender] = true;
        cert.verificationNotes[msg.sender] = notes;
        
        if (approved) {
            cert.approvalsReceived++;
        }
        
        // Update notary earnings
        uint256 notaryFee = certificateFee / 2; // 50% to notaries
        notaryEarnings[msg.sender] += notaryFee;
        
        // Increment certifications issued
        notaries[msg.sender].certificationsIssued++;
        
        emit VerificationSubmitted(requestId, msg.sender, approved);
        
        // Check if consensus reached
        if (cert.approvalsReceived >= cert.requiredNotaries) {
            cert.isApproved = true;
            emit CertificationApproved(requestId);
        }
        
        // Check if rejection (majority against)
        uint256 totalVerifications = 0;
        for (uint256 i = 0; i < totalNotaries; i++) {
            if (cert.hasVerified[address(uint160(i))]) {
                totalVerifications++;
            }
        }
        
        if (totalVerifications >= cert.requiredNotaries && cert.approvalsReceived < cert.requiredNotaries / 2 + 1) {
            emit CertificationRejected(requestId);
        }
    }
    
    /**
     * @dev Get certification details
     * @param requestId The certification request ID
     */
    function getCertification(uint256 requestId) 
        public 
        view 
        certificationExists(requestId) 
        returns (
            uint256,
            address,
            uint256,
            uint256,
            bool
        ) 
    {
        CertificationRequest storage cert = certifications[requestId];
        return (
            cert.requestId,
            cert.requester,
            cert.approvalsReceived,
            cert.requiredNotaries,
            cert.isApproved
        );
    }
    
    // ==================== Earnings Management ====================
    
    /**
     * @dev Withdraw notary earnings
     */
    function withdrawNotaryEarnings() public nonReentrant {
        uint256 earnings = notaryEarnings[msg.sender];
        require(earnings > 0, "No earnings to withdraw");
        
        notaryEarnings[msg.sender] = 0;
        require(stablecoin.transfer(msg.sender, earnings), "Withdrawal failed");
    }
    
    /**
     * @dev Get notary information
     * @param notaryAddress The notary address
     */
    function getNotaryInfo(address notaryAddress) 
        public 
        view 
        returns (
            NotaryTier,
            uint256,
            bool,
            uint256
        ) 
    {
        Notary storage notary = notaries[notaryAddress];
        return (
            notary.tier,
            notary.reputation,
            notary.isActive,
            notary.certificationsIssued
        );
    }
    
    /**
     * @dev Set certification fee
     * @param newFee The new fee in stablecoin
     */
    function setCertificationFee(uint256 newFee) public onlyOwner {
        certificateFee = newFee;
    }
}
