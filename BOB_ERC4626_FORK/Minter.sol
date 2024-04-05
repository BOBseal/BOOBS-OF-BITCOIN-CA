// SPDX-License-Identifier:  MIT

pragma solidity ^0.8.20;

import {BOOBSOFBITCOIN, Ownable} from "./BOB-NFT.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

library LBOB {

    struct Mint {
        uint Id ;
        uint16 MintedRound;
        uint PriceCost; 
    }

    struct User{
        uint totalReferals;
        uint8 mintCount;
        Mint [] mints;
    }

    struct UserMaps{
        mapping (address => uint) referalBalances;
        mapping (uint => address) referal;
    }
}

contract BOBMinter is Ownable, IERC721Receiver{
    bytes16 private constant HEX_DIGITS = "0123456789abcdef";

    uint8 private constant ADDRESS_LENGTH = 20;

    uint internal _nextIdToMint = 1;
    
    uint8 internal _MaxMintPerWallet = 10;
    
    uint internal _CurrentRoundPrice = 0.001 ether; // btc
    
    uint internal _MintsPerRound = 500; // each round has this no of mints before next round is initiated
    
    uint16 internal _CurrentRound = 1;

    uint16 internal _roundMultiplier = 200; // each round increase lead to 20 % price hike

    uint8 internal _ReferalBonus = 15; // 5% of referal bonus and 5% mint discount on mint from referal
    
    uint8 internal _shareDeposit = 50; // 40 % of mint price get deposited to minter's minted id as default share
    
    uint public  currentRoundMints ; 
    
    bool public mintStarted = false;

    BOOBSOFBITCOIN internal NFTContract; // if you want to change to your own contract replace this with own
    
    event NFTRecieved(address operator , address from , uint256 tokenId , uint256 timeStamp, bytes data);

    mapping (address => LBOB.User) internal users;
    mapping (address => LBOB.UserMaps) internal  userMapping;
    mapping (address => uint) public  accruedSales;

    constructor()
    Ownable(msg.sender)
    { 
       NFTContract = new BOOBSOFBITCOIN(address(this));
    }

    // return nft contract minted on deployement of minter
    function nftContractAddress() public view returns (address _contract){
        _contract = address(NFTContract);
    }
    /*
    @Returns => 
        roundNo = Current Round 
        price   = Current Round Price Per Mint
    */
    function getCurrentPrice(address referal) public view returns (uint price){
        if(referal == address(0))
        {
            price = _CurrentRoundPrice;
        }
        else {
            price = _CurrentRoundPrice - (_CurrentRoundPrice * 5 /100);
        }
    }

    function getNextRoundPrice() public view returns (uint){
        return  (_CurrentRoundPrice + ((_CurrentRoundPrice * _roundMultiplier)/1000));
    }

    function supplyLeft() public view returns(uint){
        return 10001 - _nextIdToMint;
    }

    function totalMinted() public view returns (uint){
        return  _nextIdToMint -1;
    }

    function getCurrentRound() public view returns(uint){
        return  _CurrentRound;
    }

    function hasMinted(address user) public view returns (bool) {
        if (users[user].mintCount == 0) {return false;} 
        else return  true;
    }

    function getUserMints(address user) public view returns (LBOB.Mint [] memory){
        return users[user].mints;
    }

    function getUserData (address user) public view returns (LBOB.User memory){
        return users[user];   
    }

    function getUserReferals(address user, uint refNonce) public view returns (address){
        return  userMapping[user].referal[refNonce];
    }

    function getUserEarnings(address user) public view returns (uint) {
        return  userMapping[user].referalBalances[address(0)];
    }

    function withdrawEarnings(uint amount) public returns(bool){
        require(userMapping[msg.sender].referalBalances[address(0)]>= amount);
        bool x = payable(msg.sender).send(amount);
        if(x){
            userMapping[msg.sender].referalBalances[address(0)] -= amount;
            return true;
        } else {return false;}
    }
    // enter address(0) in case of non refered
    function mint(address referal) public payable {
        uint amount = getCurrentPrice(referal);
        uint ref = referal == address(0) ? 0 : ((amount * _ReferalBonus) / 100);
        require( users[msg.sender].mintCount < _MaxMintPerWallet,"mint limit reached"); 
        require(msg.value == amount,"incorrect amount");
        require(_nextIdToMint < 10001 && mintStarted,"mint over or not started");
        if(referal != address(0)){
            require( hasMinted(referal) && referal != msg.sender,"referer must mint first");     
        }
        uint id = _nextIdToMint;
        uint16 currentRound = _CurrentRound;
        uint depositAmount = amount * uint(_shareDeposit) /100;
        accruedSales[address(0)] += referal == address(0) ? amount - depositAmount :(amount - ref) - depositAmount;
        NFTContract.safeMint(msg.sender , id , _calculateUri(id));
        NFTContract.deposit{value: depositAmount}(id);
        _nextIdToMint +=1;
        users[msg.sender].mintCount += 1;
        currentRoundMints += 1;
        
        if(referal != address(0)){
            uint x = users[referal].totalReferals;
            users[referal].totalReferals +=1;
            userMapping[referal].referalBalances[address(0)] += (amount * _ReferalBonus) / 100;
            userMapping[referal].referal[x] = msg.sender;
        }
        
        LBOB.Mint memory Mint =LBOB.Mint({
            Id:id,
            MintedRound:currentRound,
            PriceCost:msg.value
        });
        
        users[msg.sender].mints.push(Mint);

        if(currentRoundMints >= _MintsPerRound){
            currentRoundMints = 0;
            _CurrentRound +=1;
            _CurrentRoundPrice = getNextRoundPrice();
        }
    }

    // erc721 reciever function
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4){
        emit NFTRecieved(operator, from, tokenId,block.timestamp, data);
        return IERC721Receiver.onERC721Received.selector;
    }

    // Owner Withdraw mistakenly sent NFTs
    function withdrawNFT(address Token, uint256 Id) public  onlyOwner{
        require(IERC721(Token).ownerOf(Id) == address(this),"not recieved");
        IERC721(Token).safeTransferFrom(address(this), msg.sender, Id);
    }

    function withdrawSales(uint amount , address to ) public  onlyOwner returns(bool){
        return payable(to).send(amount);
    }

    // uint to str helper
    function _toString(uint256 value) internal pure returns (string memory) {
        unchecked {
            uint256 length = Math.log10(value) + 1;
            string memory buffer = new string(length);
            uint256 ptr;
            /// @solidity memory-safe-assembly
            assembly {
                ptr := add(buffer, add(32, length))
            }
            while (true) {
                ptr--;
                /// @solidity memory-safe-assembly
                assembly {
                    mstore8(ptr, byte(mod(value, 10), HEX_DIGITS))
                }
                value /= 10;
                if (value == 0) break;
            }
            return buffer;
        }
    }
    // minting uri generation helper
    function _calculateUri(uint id) internal pure returns(string memory){
        return (string.concat("/json/",_toString(id),".json"));
    }
    // transfer back nft ownership after minting is over
    function transferOwnershipNFT(address to) public  onlyOwner{
        NFTContract.transferOwnership(to);
    }

    function setMintStatus(bool state) public onlyOwner{
        mintStarted = state;
    }

    receive() external payable {
        accruedSales[address(0)] += msg.value;
    }
}
