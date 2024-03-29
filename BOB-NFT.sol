// SPDX-License-Identifier:  MIT

pragma solidity ^0.8.20;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import {ERC2981} from "@openzeppelin/contracts/token/common/ERC2981.sol";

contract BOOBSOFBITCOIN is ERC721, ERC721URIStorage, Ownable, ERC2981{

    uint public totalSupply = 10000;
    
    event Wrap(uint indexed  id , uint amount , address indexed from);
    event Unwrap(uint indexed  id , uint amount , address indexed to);
    event Burn(uint indexed  id , address indexed from);

    mapping (uint => uint) internal wrapperBalances;

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

    // returns deposited wei value for a boobs wrapper , acts to add value to a nft
    function tokenBalances(uint id) public  view returns (uint balances){
        return (balances = wrapperBalances[id]);
    }

    //wrap wei into a id by owner of the id
    function deposit(uint id) public payable returns(bool){
        require(msg.value>0,"send val > 0");
        require(_requireOwned(id)==msg.sender,"not owner");
        wrapperBalances[id] += msg.value;
        emit Wrap(id, msg.value, msg.sender);
        return  true;
    }

    // unwrap wei value into an id
    function _withdraw(uint id, uint amount, address to) internal returns(bool stat) {
        //require(_requireOwned(id)==msg.sender,"not owner");
        require(wrapperBalances[id]>= amount,"not enough balances");
        stat = payable (to).send(amount);
        emit Unwrap(id, amount , to);
    }

    // withdraw wei , msg.sender must be owner
    function withdraw(uint id , uint amount, address to) public returns (bool status){
        require(_requireOwned(id)== msg.sender,"not owner");
        require(to != address(0),"to cant be 0 address");
        status = _withdraw(id, amount, to);
        if(!status) revert("failed to withdraw");
    }

    function burn(uint id) public {
        require(_requireOwned(id) == msg.sender);
        uint bal = wrapperBalances[id];
        if(bal > 0){
            _withdraw(id, bal, msg.sender);
        }
        _burn(id);
        emit Burn(id, msg.sender);
    }

    function safeMint(address to, uint256 tokenId, string memory uri)
        public
        onlyOwner
    {
        require(tokenId <= totalSupply);
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, uri);
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