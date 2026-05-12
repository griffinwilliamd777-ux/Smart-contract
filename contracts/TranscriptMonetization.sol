// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title TranscriptMonetization
 * @dev Advanced smart contract for monetizing legal transcripts with multiple revenue streams
 * Features: Pay-per-view access, notary services, escrow, data licensing, and oracle feeds
 */

contract TranscriptMonetization is ERC721, Ownable, ReentrancyGuard {
    // ==================== State Variables ====================
    
    IERC20 public stablecoin; // Stablecoin for payments (USDC, USDT, etc.)
    uint256 public nextTokenId = 1;
    uint256 public platformFeePercentage = 2; // 2% platform fee
    
    // Access control levels
    enum AccessLevel { PUBLIC, LEGAL_TEAM, JOURNALIST, PREMIUM }
    
    // Transcript NFT metadata
    struct Transcript {
        string transcriptHash; // IPFS hash of encrypted transcript
        address creator;
        uint256 createdAt;
        uint256 accessPrice; // Price in stablecoin (6 decimals)
        AccessLevel minimumAccessLevel;
        bool isLicensed;
        uint256 licensingFee; // Monthly fee for licensing
        bool escrowEnabled;
        uint256 escrowAmount;
        address escrowBuyer;
        bool escrowReleased;
    }
    
    // Access records
    struct AccessRecord {
        address accessor;
        uint256 timestamp;
        AccessLevel accessLevel;
        bool revoked;
    }
    
    // Licensing agreement
    struct LicenseAgreement {
        address licensee;
        uint256 tokenId;
        uint256 monthlyFee;
        uint256 startDate;
        uint256 endDate;
        bool isActive;
        uint256 totalDataVolume; // in MB
    }
    
    // Oracle data feed
    struct OracleUpdate {
        uint256 tokenId;
        string updateHash;
        uint256 timestamp;
        address oracleProvider;
    }
    
    // ==================== Mappings ====================
    mapping(uint256 => Transcript) public transcripts;
    mapping(uint256 => mapping(address => AccessRecord)) public accessRecords;
    mapping(uint256 => OracleUpdate[]) public oracleUpdates;
    mapping(address => AccessLevel) public userAccessLevel;
    mapping(uint256 => LicenseAgreement[]) public licenseAgreements;
    mapping(address => bool) public approvedOracles;
    mapping(address => uint256) public platformEarnings;
    
    // ==================== Events ====================
    event TranscriptCreated(uint256 indexed tokenId, address indexed creator, uint256 price);
    event AccessGranted(uint256 indexed tokenId, address indexed accessor, AccessLevel level);
    event AccessRevoked(uint256 indexed tokenId, address indexed accessor);
    event PaymentProcessed(uint256 indexed tokenId, address indexed payer, uint256 amount);
    event EscrowCreated(uint256 indexed tokenId, address indexed buyer, uint256 amount);
    event EscrowReleased(uint256 indexed tokenId, address indexed seller, uint256 amount);
    event LicenseAgreementCreated(uint256 indexed tokenId, address indexed licensee, uint256 monthlyFee);
    event OracleUpdatePublished(uint256 indexed tokenId, address indexed oracle, string updateHash);
    event UserAccessLevelUpdated(address indexed user, AccessLevel newLevel);
    
    // ==================== Modifiers ====================
    modifier onlyOracleProvider() {
        require(approvedOracles[msg.sender], "Not an approved oracle provider");
        _;
    }
    
    // ==================== Constructor ====================
    constructor(address _stablecoin) ERC721("TranscriptNFT", "TNFT") {
        stablecoin = IERC20(_stablecoin);
    }
    
    // ==================== Core Functions ====================
    
    /**
     * @dev Store encrypted transcript data as an NFT
     * @param transcriptHash IPFS hash of the encrypted transcript
     * @param accessPrice Price to access the transcript
     * @param minimumAccessLevel Minimum access level required
     * @param enableEscrow Whether to enable escrow for this transcript
     */
    function storeTranscript(
        string memory transcriptHash,
        uint256 accessPrice,
        AccessLevel minimumAccessLevel,
        bool enableEscrow
    ) public nonReentrant {
        uint256 tokenId = nextTokenId++;
        
        transcripts[tokenId] = Transcript({
            transcriptHash: transcriptHash,
            creator: msg.sender,
            createdAt: block.timestamp,
            accessPrice: accessPrice,
            minimumAccessLevel: minimumAccessLevel,
            isLicensed: false,
            licensingFee: 0,
            escrowEnabled: enableEscrow,
            escrowAmount: 0,
            escrowBuyer: address(0),
            escrowReleased: false
        });
        
        _safeMint(msg.sender, tokenId);
        emit TranscriptCreated(tokenId, msg.sender, accessPrice);
    }
    
    /**
     * @dev Purchase access to a transcript
     * @param tokenId The ID of the transcript
     */
    function purchaseAccess(uint256 tokenId) public nonReentrant {
        Transcript storage transcript = transcripts[tokenId];
        require(transcript.createdAt != 0, "Transcript does not exist");
        require(transcript.accessPrice > 0, "Transcript not available for purchase");
        
        // Calculate fees
        uint256 platformFee = (transcript.accessPrice * platformFeePercentage) / 100;
        uint256 creatorPayment = transcript.accessPrice - platformFee;
        
        // Transfer payment
        require(
            stablecoin.transferFrom(msg.sender, address(this), transcript.accessPrice),
            "Payment failed"
        );
        
        // Record access
        accessRecords[tokenId][msg.sender] = AccessRecord({
            accessor: msg.sender,
            timestamp: block.timestamp,
            accessLevel: AccessLevel.LEGAL_TEAM,
            revoked: false
        });
        
        // Update earnings
        platformEarnings[address(this)] += platformFee;
        platformEarnings[transcript.creator] += creatorPayment;
        
        emit AccessGranted(tokenId, msg.sender, AccessLevel.LEGAL_TEAM);
        emit PaymentProcessed(tokenId, msg.sender, transcript.accessPrice);
    }
    
    /**
     * @dev Reveal encrypted transcript data (requires access)
     * @param tokenId The ID of the transcript
     */
    function revealTranscriptData(uint256 tokenId) 
        public 
        view 
        returns (string memory) 
    {
        require(ownerOf(tokenId) == msg.sender || hasAccess(tokenId, msg.sender), 
                "No access to this transcript");
        return transcripts[tokenId].transcriptHash;
    }
    
    /**
     * @dev Check if an address has access to a transcript
     */
    function hasAccess(uint256 tokenId, address accessor) public view returns (bool) {
        return ownerOf(tokenId) == accessor || 
               (!accessRecords[tokenId][accessor].revoked && 
                accessRecords[tokenId][accessor].timestamp > 0);
    }
    
    // ==================== Escrow Functions ====================
    
    /**
     * @dev Initiate escrow for high-value transcripts
     * @param tokenId The ID of the transcript
     * @param amount The escrow amount
     */
    function initiateEscrow(uint256 tokenId, uint256 amount) public nonReentrant {
        Transcript storage transcript = transcripts[tokenId];
        require(transcript.escrowEnabled, "Escrow not enabled for this transcript");
        require(transcript.escrowAmount == 0, "Escrow already in progress");
        
        require(
            stablecoin.transferFrom(msg.sender, address(this), amount),
            "Escrow deposit failed"
        );
        
        transcript.escrowAmount = amount;
        transcript.escrowBuyer = msg.sender;
        
        emit EscrowCreated(tokenId, msg.sender, amount);
    }
    
    /**
     * @dev Release escrow after proof of delivery
     * @param tokenId The ID of the transcript
     * @param proofHash Hash of delivery proof
     */
    function releaseEscrow(uint256 tokenId, string memory proofHash) 
        public 
        nonReentrant 
        onlyOwner 
    {
        Transcript storage transcript = transcripts[tokenId];
        require(transcript.escrowAmount > 0, "No active escrow");
        require(!transcript.escrowReleased, "Escrow already released");
        
        transcript.escrowReleased = true;
        uint256 amount = transcript.escrowAmount;
        
        require(
            stablecoin.transfer(ownerOf(tokenId), amount),
            "Escrow release failed"
        );
        
        emit EscrowReleased(tokenId, ownerOf(tokenId), amount);
    }
    
    // ==================== Licensing Functions ====================
    
    /**
     * @dev Create a licensing agreement for bulk data access
     * @param tokenId The ID of the transcript
     * @param licensee The address of the licensee
     * @param monthlyFee The monthly licensing fee
     * @param durationMonths How long the license lasts
     * @param dataVolume Total data volume in MB
     */
    function createLicenseAgreement(
        uint256 tokenId,
        address licensee,
        uint256 monthlyFee,
        uint256 durationMonths,
        uint256 dataVolume
    ) public nonReentrant {
        require(ownerOf(tokenId) == msg.sender, "Only transcript owner can license");
        
        uint256 startDate = block.timestamp;
        uint256 endDate = startDate + (durationMonths * 30 days);
        
        LicenseAgreement memory agreement = LicenseAgreement({
            licensee: licensee,
            tokenId: tokenId,
            monthlyFee: monthlyFee,
            startDate: startDate,
            endDate: endDate,
            isActive: true,
            totalDataVolume: dataVolume
        });
        
        licenseAgreements[tokenId].push(agreement);
        transcripts[tokenId].isLicensed = true;
        transcripts[tokenId].licensingFee = monthlyFee;
        
        emit LicenseAgreementCreated(tokenId, licensee, monthlyFee);
    }
    
    /**
     * @dev Pay licensing fee (called periodically by licensees)
     * @param tokenId The ID of the transcript
     * @param agreementIndex The index of the license agreement
     */
    function payLicensingFee(uint256 tokenId, uint256 agreementIndex) 
        public 
        nonReentrant 
    {
        LicenseAgreement storage agreement = licenseAgreements[tokenId][agreementIndex];
        require(agreement.licensee == msg.sender, "Not the licensee");
        require(agreement.isActive, "License not active");
        require(block.timestamp <= agreement.endDate, "License expired");
        
        uint256 platformFee = (agreement.monthlyFee * platformFeePercentage) / 100;
        uint256 creatorPayment = agreement.monthlyFee - platformFee;
        
        require(
            stablecoin.transferFrom(msg.sender, address(this), agreement.monthlyFee),
            "Payment failed"
        );
        
        platformEarnings[address(this)] += platformFee;
        platformEarnings[ownerOf(tokenId)] += creatorPayment;
        
        emit PaymentProcessed(tokenId, msg.sender, agreement.monthlyFee);
    }
    
    // ==================== Oracle Functions ====================
    
    /**
     * @dev Add an approved oracle provider
     * @param oracleAddress The address of the oracle provider
     */
    function approveOracleProvider(address oracleAddress) public onlyOwner {
        approvedOracles[oracleAddress] = true;
    }
    
    /**
     * @dev Publish real-time transcript updates from oracle
     * @param tokenId The ID of the transcript
     * @param updateHash IPFS hash of the update
     */
    function publishOracleUpdate(uint256 tokenId, string memory updateHash) 
        public 
        onlyOracleProvider 
    {
        OracleUpdate memory update = OracleUpdate({
            tokenId: tokenId,
            updateHash: updateHash,
            timestamp: block.timestamp,
            oracleProvider: msg.sender
        });
        
        oracleUpdates[tokenId].push(update);
        emit OracleUpdatePublished(tokenId, msg.sender, updateHash);
    }
    
    /**
     * @dev Charge for oracle data feed access
     * @param tokenId The ID of the transcript
     * @param accessFee The fee for accessing the oracle feed
     */
    function payForOracleFeed(uint256 tokenId, uint256 accessFee) 
        public 
        nonReentrant 
    {
        require(oracleUpdates[tokenId].length > 0, "No oracle updates available");
        
        uint256 platformFee = (accessFee * platformFeePercentage) / 100;
        uint256 creatorPayment = accessFee - platformFee;
        
        require(
            stablecoin.transferFrom(msg.sender, address(this), accessFee),
            "Payment failed"
        );
        
        platformEarnings[address(this)] += platformFee;
        platformEarnings[ownerOf(tokenId)] += creatorPayment;
        
        emit PaymentProcessed(tokenId, msg.sender, accessFee);
    }
    
    // ==================== Access Control ====================
    
    /**
     * @dev Update user access level
     * @param user The address of the user
     * @param level The new access level
     */
    function setUserAccessLevel(address user, AccessLevel level) 
        public 
        onlyOwner 
    {
        userAccessLevel[user] = level;
        emit UserAccessLevelUpdated(user, level);
    }
    
    /**
     * @dev Revoke access to a transcript
     * @param tokenId The ID of the transcript
     * @param accessor The address to revoke access from
     */
    function revokeAccess(uint256 tokenId, address accessor) 
        public 
    {
        require(ownerOf(tokenId) == msg.sender, "Only owner can revoke access");
        accessRecords[tokenId][accessor].revoked = true;
        emit AccessRevoked(tokenId, accessor);
    }
    
    // ==================== Financial Functions ====================
    
    /**
     * @dev Withdraw earnings
     */
    function withdrawEarnings() public nonReentrant {
        uint256 earnings = platformEarnings[msg.sender];
        require(earnings > 0, "No earnings to withdraw");
        
        platformEarnings[msg.sender] = 0;
        require(stablecoin.transfer(msg.sender, earnings), "Withdrawal failed");
    }
    
    /**
     * @dev Get oracle updates for a transcript
     * @param tokenId The ID of the transcript
     */
    function getOracleUpdates(uint256 tokenId) 
        public 
        view 
        returns (OracleUpdate[] memory) 
    {
        return oracleUpdates[tokenId];
    }
    
    /**
     * @dev Get license agreements for a transcript
     * @param tokenId The ID of the transcript
     */
    function getLicenseAgreements(uint256 tokenId) 
        public 
        view 
        returns (LicenseAgreement[] memory) 
    {
        return licenseAgreements[tokenId];
    }
}
