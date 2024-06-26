// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title DSC Engine
 * @author Mariosso
 * @notice
 */
contract DSCEngine is ReentrancyGuard {
    ////////////
    // Errors //
    ////////////
    error DSCEngine__MustBeMoreThanZero();
    error DSCEngine__TokenAddressesMustBeSameLengthThanPriceFeedAddresses();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__DepositCollateralFailed();
    error DSCEngine__BreaksHealthFactor(uint256 userHealthFactor);
    error DSCEngine__MintDSCFailed();
    error DSCEngine__RedeemCollateralFailed();
    error DSCEngine__BurnDSCFailed();
    error DSCEngine__BreaksHealthFactorOK(uint256 userHealthFactor);

    /////////////////////
    // State variables //
    /////////////////////
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_TRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10; // 10%

    mapping(address tokenAddress => address priceFeedAddress) private s_tokenAddressToPriceFeedAddress;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDSCMinted) private s_userToAmounOfDSCMinted;
    address[] private s_collateralTokenAddresses;

    DecentralizedStableCoin private immutable i_dscContractAddress;

    ////////////
    // Events //
    ////////////
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(address indexed from, address indexed to, address indexed token, uint256 amount);

    ///////////////
    // Modifiers //
    ///////////////
    modifier moreThenZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__MustBeMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address tokenAddress) {
        if (s_tokenAddressToPriceFeedAddress[tokenAddress] == address(0)) {
            revert DSCEngine__NotAllowedToken();
        }
        _;
    }

    ///////////////
    // Functions //
    ///////////////
    constructor(
        address[] memory _tokenAddresses,
        address[] memory _priceFeedAddresses,
        DecentralizedStableCoin _dscContractAddress
    ) {
        if (_tokenAddresses.length != _priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesMustBeSameLengthThanPriceFeedAddresses();
        }
        for (uint256 i = 0; i < _tokenAddresses.length; i++) {
            s_tokenAddressToPriceFeedAddress[_tokenAddresses[i]] = _priceFeedAddresses[i];
            s_collateralTokenAddresses.push(_tokenAddresses[i]);
        }
        i_dscContractAddress = _dscContractAddress;
    }

    ////////////////////////
    // Functions External //
    ////////////////////////
    function depositCollateralAndMintDSC(
        address _tokenCollateralAddress,
        uint256 _amountCollateral,
        uint256 _amountOfDSCToMint
    ) external {
        depositCollateral(_tokenCollateralAddress, _amountCollateral);
        mintDSC(_amountOfDSCToMint);
    }

    /**
     *
     * @param _tokenCollateralAddress The address of the deposited collateral
     * @param _amountCollateral The amount of the deposited collateral
     */
    function depositCollateral(address _tokenCollateralAddress, uint256 _amountCollateral)
        public
        moreThenZero(_amountCollateral)
        isAllowedToken(_tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][_tokenCollateralAddress] += _amountCollateral;
        emit CollateralDeposited(msg.sender, _tokenCollateralAddress, _amountCollateral);
        bool success = IERC20(_tokenCollateralAddress).transferFrom(msg.sender, address(this), _amountCollateral);
        if (!success) {
            revert DSCEngine__DepositCollateralFailed();
        }
    }

    function redeemCollateralForDSC(
        address _tokenCollateralAddress,
        uint256 _amountCollateral,
        uint256 _amountOfDSCToBurn
    ) external {
        burnDSC(_amountOfDSCToBurn);
        redeemCollateral(_tokenCollateralAddress, _amountCollateral);
        // redeemCollateral already check if the healFactor is broken so we dont have to check here
    }

    function redeemCollateral(address _tokenCollateralAddress, uint256 _amountCollateral)
        public
        moreThenZero(_amountCollateral)
        nonReentrant
    {
        _redeemCollateral(_tokenCollateralAddress, _amountCollateral, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     *
     * @param _amountOfDSCToMint The amount of DSC to mint
     */
    function mintDSC(uint256 _amountOfDSCToMint) public moreThenZero(_amountOfDSCToMint) nonReentrant {
        s_userToAmounOfDSCMinted[msg.sender] += _amountOfDSCToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        (bool success) = i_dscContractAddress.mint(msg.sender, _amountOfDSCToMint);
        if (!success) {
            revert DSCEngine__MintDSCFailed();
        }
    }

    function burnDSC(uint256 _amount) public moreThenZero(_amount) {
        s_userToAmounOfDSCMinted[msg.sender] -= _amount;
        // first we transfer the tokens to our contract
        (bool success) = i_dscContractAddress.transferFrom(msg.sender, address(this), _amount);
        if (!success) {
            revert DSCEngine__BurnDSCFailed();
        }
        // then we burn them
        i_dscContractAddress.burn(_amount);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function liquidate(address _tokenCollateralAddress, address _user, uint256 _debtToCover)
        external
        moreThenZero(_debtToCover)
        nonReentrant
    {
        uint256 startingUserHealthFactor = _healthFactor(_user);
        if (startingUserHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactorOK(startingUserHealthFactor);
        }
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(_tokenCollateralAddress, _debtToCover);
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralRedeemed = tokenAmountFromDebtCovered + bonusCollateral;
        _redeemCollateral(_tokenCollateralAddress, totalCollateralRedeemed, _user, msg.sender);
    }

    function getHealthFactor() external view returns (uint256) {}

    //////////////////////////////////
    // Functions Internal & Private //
    //////////////////////////////////
    function _redeemCollateral(address _tokenCollateralAddress, uint256 _amountCollateral, address _from, address _to)
        private
    {
        s_collateralDeposited[_from][_tokenCollateralAddress] -= _amountCollateral;
        emit CollateralRedeemed(_from, _to, _tokenCollateralAddress, _amountCollateral);

        bool success = IERC20(_tokenCollateralAddress).transfer(_to, _amountCollateral);
        if (!success) {
            revert DSCEngine__RedeemCollateralFailed();
        }
    }

    function _getAccountInformation(address _user)
        private
        view
        returns (uint256 totalDSCMinted, uint256 collateralValueInUsd)
    {
        totalDSCMinted = s_userToAmounOfDSCMinted[_user];
        collateralValueInUsd = getAccountCollateralValue(_user);
    }

    function _healthFactor(address _user) private view returns (uint256) {
        (uint256 totalDSCMinted, uint256 collateralValueInUsd) = _getAccountInformation(_user);
        uint256 collateralAdjustedForTreshold = (collateralValueInUsd * LIQUIDATION_TRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForTreshold * PRECISION) / totalDSCMinted;
    }

    function _revertIfHealthFactorIsBroken(address _user) internal view {
        uint256 userHealthFactor = _healthFactor(_user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    //////////////////////
    // Functions Public //
    //////////////////////
    function getAccountCollateralValue(address _user) public view returns (uint256) {
        uint256 totalCollateralValueInUsd = 0;
        for (uint256 i = 0; i < s_collateralTokenAddresses.length; i++) {
            address tokenAddress = s_collateralTokenAddresses[i];
            uint256 tokenAmount = s_collateralDeposited[_user][tokenAddress];
            totalCollateralValueInUsd += getUSDValue(tokenAddress, tokenAmount);
        }
        return totalCollateralValueInUsd;
    }

    function getUSDValue(address _tokenAddress, uint256 _tokenAmount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_tokenAddressToPriceFeedAddress[_tokenAddress]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        // we have to make sure that the decimal places from the price feed are correct. In our case ETH and BTC have the same decimals, but other chains might not.
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * _tokenAmount) / PRECISION;
    }

    function getTokenAmountFromUsd(address _tokenAddress, uint256 _usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_tokenAddressToPriceFeedAddress[_tokenAddress]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return _usdAmountInWei * PRECISION / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    //////////////////////
    // Getter Functions //
    //////////////////////
    function getTokenAddressToPriceFeedAddress(address _tokenAddress) public view returns (address) {
        return s_tokenAddressToPriceFeedAddress[_tokenAddress];
    }

    function getCollateralTokenAddress(uint256 _index) public view returns (address) {
        return s_collateralTokenAddresses[_index];
    }

    function getCollateralTokenAddressesLenght() public view returns (uint256) {
        return s_collateralTokenAddresses.length;
    }

    function getDSCCoinAddress() public view returns (DecentralizedStableCoin) {
        return i_dscContractAddress;
    }

    function getCollateralDeposited(address _user, address _tokenAddress) public view returns (uint256) {
        return s_collateralDeposited[_user][_tokenAddress];
    }
}
