// SPDX-License-Identifier:  MIT

pragma solidity ^0.8.20;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import {ERC2981} from "@openzeppelin/contracts/token/common/ERC2981.sol";

/*
Features: 
    1: Each NFT's Original Minter is Eligible to Earn all the Royalty Generated by user's minted id from secondary sales in Native Token , Mint once and earn lifetime from royalty
    2: Each NFT has default Points/token allocation of 0.5% / total supply of ecosystem token ...34,500,000 tokens pool
    3: Bonus Allocations, Through Events Each NFT's Bonus Points Allocation can be increased
*/
contract BOOBSOFBITCOIN is ERC721, ERC721URIStorage, Ownable, ERC2981{

    uint public totalSupply = 10000;
    uint internal defaultAllocation = (34_500_000 * (10 ** 18))/totalSupply;
    event Wrap(uint indexed  id , uint amount , address indexed from);
    event Unwrap(uint indexed  id , uint amount , address indexed to);
    event Burn(uint indexed  id , address indexed from);

    struct BOB{
        uint bonusAllocation; // for each referal user can earn extra 300 token allocation
        address originalMinter; // original Minter
    }

    mapping (uint => BOB) internal extraData;

    constructor(address initialOwner)
        ERC721("BOOBS OF BITCOIN TESTNET", "BOB TEST")
        Ownable(initialOwner)
    {   
        //Royalty of 6.9%
        _setDefaultRoyalty(initialOwner, 690);        
    }

    function _baseURI() internal pure override returns (string memory) {
        return "ipfs://bafybeidl7cpycjiqza6rudgzl4q5ll6x7nfpqll5qeqw6toqiuecwg2hje";
    }

    function getNFTExtraData(uint id) public view returns(BOB memory){
        return  extraData[id];
    }

    function getDefaultPoints() public view returns(uint) {
        return defaultAllocation;
    }

    function getIdTotalAllocation(uint id) public view returns(uint){
        return (getDefaultPoints() + extraData[id].bonusAllocation);
    }

    function burn(uint id) public {
        require(_requireOwned(id) == msg.sender);
        _burn(id);
        emit Burn(id, msg.sender);
    }

    function safeMint(address to, uint256 tokenId, string memory uri)
        public
        onlyOwner
    {
        require(tokenId <= totalSupply);
        _safeMint(to, tokenId);
        extraData[tokenId].originalMinter = to;
        _setTokenURI(tokenId, uri);
        _setTokenRoyalty(tokenId , to , 690);
    }

    function addBonusAllocation(uint id, uint amount) public onlyOwner returns(bool){
        extraData[id].bonusAllocation += amount; 
        return true;
    }

    // The following functions are overrides required by Solidity.
    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function setRoyalty(address reciever, uint96 fraction) public  onlyOwner{
        _setDefaultRoyalty(reciever,  fraction);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721URIStorage, ERC2981)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    receive() external payable {}
}