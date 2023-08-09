// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;

interface IXENFT {
    /**
        @dev mapping: NFT tokenId => count of Virtual Mining Units
    */
    function vmuCount(uint256 tokenID) external view returns (uint256 count);

    /**
        @dev mapping: NFT tokenId => MintInfo (used in tokenURI generation)
        MintInfo encoded as:
             term (uint16)
             | maturityTs (uint64)
             | rank (uint128)
             | amp (uint16)
             | eaa (uint16)
             | class (uint8):
                 [7] isApex
                 [6] isLimited
                 [0-5] powerGroupIdx
             | redeemed (uint8)
    */
    function mintInfo(uint256 tokenID) external view returns (uint256 info);

    /**
        @dev public getter for tokens owned by address
    */
    function ownedTokens() external view returns (uint256[] memory);

    /**
        @dev encodes MintInfo record from its props
    */
    function encodeMintInfo(
        uint256 term,
        uint256 maturityTs,
        uint256 rank,
        uint256 amp,
        uint256 eaa,
        bool redeemed
    ) external returns (uint256 info);

    /**
        @dev decodes MintInfo record and extracts all of its props
    */
    function decodeMintInfo(uint256 info)
    external
    returns (
        uint256 term,
        uint256 maturityTs,
        uint256 rank,
        uint256 amp,
        uint256 eaa,
        bool redeemed
    );

    /**
        @dev extracts `term` prop from encoded MintInfo
    */
    function getTerm(uint256 info) external returns (uint256 term);

    /**
        @dev extracts `maturityTs` prop from encoded MintInfo
    */
    function getMaturityTs(uint256 info) external returns (uint256 maturityTs);

    /**
        @dev extracts `rank` prop from encoded MintInfo
    */
    function getRank(uint256 info) external returns (uint256 rank);

    /**
        @dev extracts `AMP` prop from encoded MintInfo
    */
    function getAMP(uint256 info) external returns (uint256 amp);

    /**
        @dev extracts `EAA` prop from encoded MintInfo
    */
    function getEAA(uint256 info) external returns (uint256 eaa);

    /**
        @dev extracts `redeemed` prop from encoded MintInfo
    */
    function getRedeemed(uint256 info) external returns (bool redeemed);

    /**
        @dev determines if tokenId corresponds to limited series
    */
    function isLimited(uint256 tokenId) external returns (bool limited);

    /**
        @dev compliance with ERC-721 standard (NFT); returns NFT metadata, including SVG-encoded image
    */
    function tokenURI(uint256 tokenId) external returns (string memory);

    /**
        @dev function callable only in proxy contracts from the original one => XENCrypto.claimRank(term)
    */
    function callClaimRank(uint256 term) external;

    /**
        @dev function callable only in proxy contracts from the original one => XENCrypto.claimMintRewardAndShare()
    */
    function callClaimMintReward(address to) external;

    /**
        @dev function callable only in proxy contracts from the original one => destroys the proxy contract
    */
    function powerDown() external;

    /**
        @dev main torrent interface. initiates Bulk Mint (Torrent) Operation
    */
    function bulkClaimRank(uint256 count, uint256 term) external returns (uint256);

    /**
        @dev main torrent interface. initiates Mint Reward claim and collection and terminates Torrent Operation
    */
    function bulkClaimMintReward(uint256 tokenId, address to) external;
}
