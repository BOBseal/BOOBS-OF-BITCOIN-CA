// SPDX-License-Identifier:  MIT
/*
TOKENIZED VAULT NFTs - ERC-4627

=> each NFT is a Tokenized Vault Earning Yeild from various sources such as paltform revenue and resells
=> deposit and mint shares that are paired with an ID , resembles erc1155 but is erc721
*/
pragma solidity ^0.8.20;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC2981} from "@openzeppelin/contracts/token/common/ERC2981.sol";

contract BOOBSOFBITCOIN is ERC721, ERC721URIStorage, Ownable, ERC2981{
    using Math for uint;
    uint public totalSupply = 10000;
    //IERC20 internal asset;
    //uint internal _totalAssets ;
    uint internal _totalShares;
    uint8 private immutable _underlyingDecimals;

    event Deposit(address indexed sender, uint indexed to, uint256 assets, uint256 shares);

    event Withdraw(
        uint indexed from,
        address indexed receiver,
        address indexed caller,
        uint256 assets,
        uint256 shares 
    );

    mapping (uint => uint) public shareBalances; // ierc721

    constructor(address initialOwner)
        ERC721("BOOBS OF BITCOIN TESTNET", "BOB TEST")
        Ownable(initialOwner)
    {   
        _underlyingDecimals = 18;
        _setDefaultRoyalty(address(this), 690);        
    }

    function decimals() public view virtual returns (uint8) {
        return _underlyingDecimals + _decimalsOffset();
    }

    /** @dev See {IERC4626-totalAssets}. */
    function totalAssets() public view virtual returns (uint256) {
        return address(this).balance;
    }

    function totalShares() public view returns(uint){
        return _totalShares;
    }

    /** @dev See {IERC4626-convertToShares}. */
    function convertToShares(uint256 assets) public view virtual returns (uint256) {
        return _convertToShares(assets, Math.Rounding.Floor);
    }

    /** @dev See {IERC4626-convertToAssets}. */
    function convertToAssets(uint256 shares) public view virtual returns (uint256) {
        return _convertToAssets(shares, Math.Rounding.Floor);
    }

    /** @dev See {IERC4626-maxDeposit}. */
    function maxDeposit(uint) public view virtual returns (uint256) {
        return type(uint256).max;
    }

    /** @dev See {IERC4626-maxMint}. */
    function maxMint(uint) public view virtual returns (uint256) {
        return type(uint256).max;
    }

    /** @dev See {IERC4626-maxWithdraw}. */
    function maxWithdraw(uint id) public view virtual returns (uint256) {
        return _convertToAssets(shareBalances[id], Math.Rounding.Floor);
    }

    /** @dev See {IERC4626-maxRedeem}. */
    function maxRedeem(uint id) public view virtual returns (uint256) {
        return shareBalances[id];
    }

     /** @dev See {IERC4626-previewDeposit}. */
    function previewDeposit(uint256 assets) public view virtual returns (uint256) {
        return _convertToShares(assets, Math.Rounding.Floor);
    }

    /** @dev See {IERC4626-previewWithdraw}. */
    function previewWithdraw(uint256 assets) public view virtual returns (uint256) {
        return _convertToShares(assets, Math.Rounding.Ceil);
    }

      /** @dev See {IERC4626-previewMint}. */
    function previewMint(uint256 shares) public view virtual returns (uint256) {
        return _convertToAssets(shares, Math.Rounding.Ceil);
    }

     /** @dev See {IERC4626-previewRedeem}. */
    function previewRedeem(uint256 shares) public view virtual returns (uint256) {
        return _convertToAssets(shares, Math.Rounding.Floor);
    }

    function _baseURI() internal pure override returns (string memory) {
        return "ipfs://bafybeidl7cpycjiqza6rudgzl4q5ll6x7nfpqll5qeqw6toqiuecwg2hje";
    }

    //wrap wei into a id by owner of the id
    function deposit(uint reciever) public payable returns(bool){
        require(msg.value>0,"send val > 0");
        uint shares = previewDeposit(msg.value);
        shareBalances[reciever] += shares;
        _totalShares += shares;
        emit Deposit(msg.sender,reciever,msg.value, shares);
        return true;
    }

    function mintShare(uint shares_, uint reciever) public payable returns(bool){
        uint amt = previewMint(shares_);
        require(msg.value == amt,"send val == previewMint()");
        shareBalances[reciever] += shares_;
        _totalShares += shares_;
        emit Deposit(msg.sender,reciever,msg.value, shares_);
        return true;
    }

    // withdraw wei , msg.sender must be owner
    function withdraw(uint amount , uint id, address to) public returns (bool status){
        require(_requireOwned(id)== msg.sender,"not owner");
        require(to != address(0),"to cant be 0 address");
        require(amount < totalAssets());
        uint256 maxAssets = maxWithdraw(id);
        require(amount <= maxAssets ,"amount < maxWithdraw");
        uint shares = previewWithdraw(amount);
        status = payable (to).send(amount);
        if(status){
            shareBalances[id] -= shares;
            _totalShares -= shares;
            emit Withdraw(id, to, msg.sender,amount, shares);
        } else {revert();}
    }

    function redeemShare(uint shares , uint id, address to) public returns (bool stat){
        require(_requireOwned(id)== msg.sender,"not owner");
        require(to != address(0),"to cant be 0 address");
        uint256 maxAssets = maxRedeem(id);
        require(shares <= shareBalances[id], "not enough shares");
        require(maxAssets <totalAssets());
        uint amt = previewRedeem(shares);
        stat = payable(to).send(amt);
        if(stat){
            shareBalances[id] -= shares;
            _totalShares -= shares;
            emit Withdraw(id , to, msg.sender, amt , shares);
        } else {revert();}
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

     function _convertToShares(uint256 assets, Math.Rounding rounding) internal view virtual returns (uint256) {
        return assets.mulDiv(_totalShares + 10 ** _decimalsOffset(), totalAssets(), rounding);
    }

    /**
     * @dev Internal conversion function (from shares to assets) with support for rounding direction.
     */
    function _convertToAssets(uint256 shares, Math.Rounding rounding) internal view virtual returns (uint256) {
        return shares.mulDiv(totalAssets() + 1, _totalShares + 10 ** _decimalsOffset(), rounding);
    }

    function _decimalsOffset() internal view virtual returns (uint8) {
        return 0;
    }

    receive() external payable {}
}