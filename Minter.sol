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

    struct Whitelist{
        uint mints;
        bool whitelisted;    
    }

    struct Rounds{
        mapping(uint => uint) participants;
        uint[] winners;
        uint roundPool;
        uint balances;
    }
}

contract BOBMinter is Ownable, IERC721Receiver{

    bytes16 private constant HEX_DIGITS = "0123456789abcdef";

    uint8 private constant ADDRESS_LENGTH = 20;

    uint internal _nextIdToMint = 1;
    
    uint8 internal _MaxMintPerWallet = 30; // max mint per wallet aggregated over all rounds
    
    uint internal _CurrentRoundPrice = 0.00069 ether; // btc
    
    uint internal _MintsPerRound = 500; // each round has this no of mints before next round is initiated

    uint internal _bonusPointsPerReferal = 69 * 10 ** 18; // each referal gives extra this amount of bonus point to their minted nft
    
    uint16 internal _CurrentRound = 1;
    
    uint8 internal _winnersPerRound = 5; // 5 random winner ids , each winner eligible for equal rewards from a reward pool from 15% of 500 mints (1 round)  
    
    uint8 internal _whitelistMint = 4; // 4 mints for whitelist

    uint8 internal maxWhitelistAddress = 100; // max whitelist is 100 
    
    uint8 internal whitelistCount; // internal count
    
    uint internal _lottery = 15 ; // 10% of mint per round goes to lottery

    uint8 internal _ReferalBonus = 15; // 15% of referal bonus on mint from referal
    
    uint public  currentRoundMints ; 
    
    bool public mintStarted = false;

    BOOBSOFBITCOIN internal NFTContract; // if you want to change to your own contract replace this with own
    
    event NFTRecieved(address operator , address from , uint256 tokenId , uint256 timeStamp, bytes data);

    mapping (address => LBOB.User) internal users;
    mapping (address => LBOB.UserMaps) internal  userMapping;
    mapping (address => uint) public  accruedSales;
    mapping (address => LBOB.Whitelist) internal whitelist; 
    mapping (uint16 => mapping (uint => bool)) internal winners; // lottery winners per round , lottery winners are nft ids , not addresses , and whoever get hold claim the balances
    mapping (uint16 => LBOB.Rounds) internal rounds; // data per round
    mapping (uint => uint) internal winBalances; // balances of ids that won in their mint round , only owner can claim
    mapping (address => uint) public bonusAllocations; // bonus allocations for referals that at the end user can bind to their nfts
      
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
    function getCurrentPrice() public view returns (uint price){
            price = _CurrentRoundPrice;
    }

    function getRoundPool(uint16 round) public view returns (uint, uint){
        return (rounds[round].roundPool, rounds[round].balances) ;
    }

    function getRoundWinnerIds(uint16 round) public view returns(uint[] memory){
        return rounds[round].winners;
    }

    function isWhitelisted(address user) public view returns(bool){
        return whitelist [user].whitelisted;
    }

    function supplyLeft() public view returns(uint){
        return 10001 - _nextIdToMint;
    }

    function totalMinted() public view returns (uint){
        return  _nextIdToMint -1;
    }

    function getCurrentRound() public view returns(uint16){
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

    function getReferalEarnings(address user) public view returns (uint) {
        return  userMapping[user].referalBalances[address(0)];
    }
    // binds the bonus allocations to BOB NFTs if they own one;
    function bindBonusAllocation(uint toId) public {
        require(NFTContract.ownerOf(toId)== msg.sender,"not owner of id to bind");
        require(bonusAllocations[msg.sender]>0,"already bound");
        bool x = NFTContract.addBonusAllocation(toId, bonusAllocations[msg.sender]);
        if(!x){
            revert();
        } else{
            bonusAllocations[msg.sender] = 0;
        }
    }
    // claims the raffle win amount to the owner of the winner id , one address can win multiple times 
    //if he/she owns (does not need to be minted) the lucky ids selected through random draw
    function claimRaffleWin(uint id) public {
        require(NFTContract.ownerOf(id)== msg.sender,"not owner of id to claim");
        require(winBalances[id]>0,"already withdrawn");
        bool x = payable(msg.sender).send(winBalances[id]);
        if(!x){
            revert("0x");
        } else {
            winBalances[id] = 0;
        }
    }
    // participants can claim their referal earnings through this
    function withdrawReferalEarnings(uint amount) public returns(bool){
        require(userMapping[msg.sender].referalBalances[address(0)]>= amount);
        bool x = payable(msg.sender).send(amount);
        if(x){
            userMapping[msg.sender].referalBalances[address(0)] -= amount;
            return true;
        } else {return false;}
    }

    // enter address(0) in case of non refered
    function mint(address referal) public payable {
        uint amount = whitelist[msg.sender].whitelisted? 0 : getCurrentPrice();
        require( users[msg.sender].mintCount < _MaxMintPerWallet,"mint limit reached"); 
        require(msg.value == amount,"incorrect mint fee amount");
        require(_nextIdToMint < 10001 && mintStarted,"mint over or not started");
        if(referal != address(0)){
            require( hasMinted(referal) && referal != msg.sender,"referer must mint first");     
        }
        uint id = _nextIdToMint;
        uint16 currentRound = _CurrentRound;
        // checks if whitelisted
        if(!whitelist[msg.sender].whitelisted){
            // calculate the referal and to pool amounts
            uint referalBonus = (amount * uint(_ReferalBonus)) / 100;
            uint toPool = (amount * _lottery) / 100;
            // mints the nft
            NFTContract.safeMint(msg.sender , id , _calculateUri(id));
            // handle adding to the pool the lottery amount, 15%
            _addRoundPool(currentRound, toPool);
            // randomize the indexes of participant and pushed to a mapping 
            _pushParticipant(currentRound, id);
            // handle states
            _nextIdToMint +=1;
            users[msg.sender].mintCount += 1;
            currentRoundMints += 1;
            // handle referals
            if(referal != address(0)){
                uint x = users[referal].totalReferals;
                users[referal].totalReferals +=1;
                userMapping[referal].referalBalances[address(0)] += referalBonus;
                userMapping[referal].referal[x] = msg.sender;
                bonusAllocations[referal] += _bonusPointsPerReferal;
                bonusAllocations[msg.sender] += _bonusPointsPerReferal;
            }
            
            LBOB.Mint memory Mint =LBOB.Mint({
                Id:id,
                MintedRound:currentRound,
                PriceCost:msg.value
            });
            
            users[msg.sender].mints.push(Mint);
            // adds to contract balances
            amount = amount - toPool;
            accruedSales[address(0)] += referal == address(0) ? amount: amount - referalBonus;
        } else {
            NFTContract.safeMint(msg.sender , id , _calculateUri(id));
            _pushParticipant(currentRound, id);
            _nextIdToMint +=1;
            users[msg.sender].mintCount += 1;
            currentRoundMints += 1;
            
            LBOB.Mint memory Mint =LBOB.Mint({
                Id:id,
                MintedRound:currentRound,
                PriceCost:msg.value
            });
            users[msg.sender].mints.push(Mint);
        }
        // if mints per round limit reached select winners and distribute rewards to winner ids to claim and start next round
        if(currentRoundMints >= _MintsPerRound){
                _selectWinnersAndDistribute(currentRound , rounds[currentRound].roundPool);
                currentRoundMints = 0;
                _CurrentRound +=1;
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

    function _pushParticipant(uint16 round,uint participant) internal{
        uint n = getRandomNumber();// Shuffle participants mapping according to random indexes
        rounds[round].participants[n] = participant;
    }

    function _addRoundPool(uint16 round,uint amount) internal{
        rounds[round].roundPool += amount;
        rounds[round].balances += amount;
    }

    function setWhitelist(address For , bool stat) public  onlyOwner{
        require(whitelistCount <= maxWhitelistAddress,"wl spots over");
        whitelist[For].whitelisted = stat;
        whitelistCount = stat ? whitelistCount + 1: whitelistCount -1;
    }

    // transfer back nft ownership after minting is over
    function transferOwnershipNFT(address to) public  onlyOwner{
        NFTContract.transferOwnership(to);
    }

    function setMintStatus(bool state) public onlyOwner{
        mintStarted = state;
    }
    
    function _selectWinnersAndDistribute(uint16 round, uint totalPool) internal {
        // Select the first _winnersPerRound no of shuffled participants as winners
        for (uint256 i = 0; i < uint(_winnersPerRound); i++) {
            rounds[round].winners.push(rounds[round].participants[i]);
        }
        _distribute(round,totalPool , rounds[round].winners);
    }

    // returns a random index for the mint for current round participant list, at end the, of the randomized participant list the first 3 indexes are awared the reward
    function getRandomNumber() public view returns (uint256) {
        uint256 randomNumber = uint256(keccak256(abi.encodePacked(_nextIdToMint, msg.sender, block.timestamp)));
        return (randomNumber % _MintsPerRound) + 1; // Range: 1-MintsPerRound
    }

    function _distribute(uint16 round,uint totalPool , uint[] memory participants) internal {
        uint amount = totalPool / uint(_winnersPerRound);
        for (uint i = 0; i < participants.length ; i++){
            uint to = participants[i];
            winBalances[to] += amount;
            rounds[round].balances -= amount;
        }
    } 

    receive() external payable {
        accruedSales[address(0)] += msg.value;
    }
}
