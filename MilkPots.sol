// SPDX-License-Identifier:  MIT

pragma solidity ^0.8.20;

import {IERC721, BOOBSOFBITCOIN, Ownable} from "./BOB-NFT.sol";

interface  IBOBNFT is IERC721 {
    function getNFTExtraData(uint id) external view returns(BOOBSOFBITCOIN.BOB memory);
    function subBonusAllocation(uint id, uint amount) external returns(bool);
    function addBonusAllocation(uint id, uint amount) external returns(bool);
    function getDefaultPoints() external view returns(uint);
}

contract MilkPotsV1 is Ownable{

    uint public currentRound = 1;
    uint public maxTicketsPerRound = 100;
    uint public maxWinners = 3;
    uint public houseFee = 15; //15 % of pool 
    uint internal ticketNonce = 1;
    uint internal maxTicketsPerUser = 3; // 4% chance , max tickets per user, per round
    uint internal luckyWinnerBonus = 50 *(10 **18);
    uint public ticketPrice = 0.00002 ether; // btc
    uint public accumulatedFee;

    IBOBNFT public NftContract;

    struct Tickets{
        bytes12 ticketId;
        address owner;
        bool isWinner;
    }

    struct Rounds{
        uint totalParticipants;
        uint totalPool;
        uint poolBalances;
    }

    struct RoundMappings{
        mapping (uint => Tickets) participants;
        mapping (address =>bytes12[]) userTickets;
        mapping (address => uint16) ticketBalances;
        mapping (address => uint16) winningTicketCount;
        mapping (bytes12 => bool) isWinner;
        mapping (address => uint) winBonus;
        bytes12[] winners;
    }

    mapping (uint => Rounds) internal rounds;
    mapping (uint => RoundMappings) internal roundMaps;
    mapping (address => mapping (uint => uint)) public userUnclaimedRewards;
    mapping (address => uint) public userTotalWinAmount;

    constructor(address ca)
    Ownable(msg.sender){
        NftContract = IBOBNFT(ca);
    }

    function getRoundData(uint round) public view returns(Rounds memory){
        return rounds[round];
    }

    function getWinBonuses(uint round, address user) public view returns (uint){
        return roundMaps[round].winBonus[user];
    }

    function getUserTicketCount(address user, uint round) public view returns(uint16){
        return roundMaps[round].ticketBalances[user];
    }

    function getUserTickets(address user, uint round) public view returns (bytes12 [] memory){
        return roundMaps[round].userTickets[user];
    }

    function getUserWinnerTicketCount(address user , uint round) public view returns(uint16){
        return roundMaps[round].winningTicketCount[user];
    }

    function getTickets(uint participantIndex, uint round) public view returns(Tickets memory){
        return roundMaps[round].participants[participantIndex];
    }

    function getRoundWinners(uint round) public view returns(bytes12[] memory){
        return roundMaps[round].winners;
    }

    function isWinnerTicket(bytes12 ticketId, uint round) public view returns(bool){
        return roundMaps[round].isWinner[ticketId];
    }

    function buyMilk() public payable{
        require(msg.value == ticketPrice,"incorrect price");
        uint r = currentRound;
        require(getUserTicketCount(msg.sender, r)<=maxTicketsPerUser,"exceed max limit");
        bytes12 id = bytes12(keccak256(abi.encode(r , ticketNonce, msg.sender, block.timestamp)));
        uint pIndex = rounds[r].totalParticipants + 1;
        Rounds memory rRound = Rounds({
            totalParticipants: pIndex,
            totalPool:rounds[r].totalPool + msg.value,
            poolBalances:rounds[r].poolBalances + msg.value
        });
        Tickets memory tTicket = Tickets({
            ticketId: id,
            owner: msg.sender,
            isWinner: false
        });
        // register ticket into round
        roundMaps[r].participants[pIndex] = tTicket;
        ticketNonce += 1;
        // update round data
        rounds[r] = rRound;
        // do raffle and push into winner array if dice return below 6 , ie upto 5 winners per round
        if(_getRandomIndexInRange(maxTicketsPerRound) <= maxWinners){
            roundMaps[r].winners.push(id);
            roundMaps[r].participants[pIndex].isWinner = true;
            roundMaps[r].winningTicketCount[msg.sender] += 1;
        }
        // if ticket nonce == max tickets start next round
        if(ticketNonce == maxTicketsPerRound){
            ticketNonce = 1;
            currentRound += 1;
            uint toFee = (rounds[r].totalPool * houseFee) / 100; 
            uint am = rounds[r].totalPool - toFee;
            uint winAmount = am / maxWinners;
            accumulatedFee += toFee;
            // distribute amount to winners
            for (uint i = 0; i< roundMaps[r].winners.length;i++){
                address to = roundMaps[r].participants[pIndex].owner;
                userUnclaimedRewards[to][r] += winAmount;
                rounds[r].poolBalances -= winAmount;
                // reward bonus allocation for user to claim later
                roundMaps[r].winBonus[msg.sender] += luckyWinnerBonus;
            }
        }
    }
    // claims raffle win amount
    function claimWinAmounts(uint amount, uint round) public {
        require(userUnclaimedRewards[msg.sender][round]>= amount,"nothing to withdraw");
        require(address(this).balance >= amount);
        bool x = payable(msg.sender).send(amount);
        if(x){
            userUnclaimedRewards[msg.sender][round] -= amount;
            userTotalWinAmount[msg.sender] += amount; 
        }
    }
    // claims raffle win bonus points to nft if user hold one
    function claimWinBonuses(uint round, uint amount, uint nftId) public {
        require(roundMaps[round].winBonus[msg.sender] >= amount);
        require( nftId >0 && NftContract.ownerOf(nftId) == msg.sender,"To Claim Directly You Need BOB NFT");
        bool res = NftContract.addBonusAllocation(nftId, amount);
        if(res){
            roundMaps[round].winBonus[msg.sender] -= amount;
        }
    }

    function setTicketPrice(uint amount) public onlyOwner{
        ticketPrice = amount;
    }

    function withdrawFee(uint amount,address to) public onlyOwner{
        require(accumulatedFee >= amount);
        bool x = payable(to).send(amount);
        if(x){accumulatedFee -= amount;}
    }

    function setTicketConfig(
        uint _maxWinners, 
        uint maxTickets , 
        uint _houseFee,
        uint _maxTicketsPerUser,
        uint bonusAmount
        ) public onlyOwner{
            require(houseFee <= 20 && maxWinners < 16);
            maxTicketsPerRound = maxTickets;
            maxWinners = _maxWinners;
            houseFee = _houseFee;
            maxTicketsPerUser = _maxTicketsPerUser;
            luckyWinnerBonus = bonusAmount * (10 ** 18); 
    }

    function _getRandomIndexInRange(uint range) internal view returns (uint256) {
        uint256 randomNumber = uint256(keccak256(abi.encodePacked(ticketNonce, msg.sender, currentRound, block.timestamp)));
        return (randomNumber % range) + 1; // Range: 1-MintsPerRound
    }
}