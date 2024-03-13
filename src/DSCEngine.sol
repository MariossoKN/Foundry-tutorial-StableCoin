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

    /////////////////////
    // State variables //
    /////////////////////
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;

    mapping(address tokenAddress => address priceFeedAddress) private s_tokenAddressToPriceFeedAddress;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDSCMinted) private s_userToAmounOfDSCMinted;
    address[] private s_collateralTokenAddresses;

    DecentralizedStableCoin private immutable i_dscContractAddress;

    ////////////
    // Events //
    ////////////
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);

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
    function depositCollateralAndMintDSC() external {}

    /**
     *
     * @param _tokenCollateralAddress The address of the deposited collateral
     * @param _amountCollateral The amount of the deposited collateral
     */
    function depositCollateral(address _tokenCollateralAddress, uint256 _amountCollateral)
        external
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

    function redeemCollateralForDSC() external {}

    function redeemCollateral() external {}

    /**
     *
     * @param _amountOfDSCToMint The amount of DSC to mint
     */
    function mintDSC(uint256 _amountOfDSCToMint) external moreThenZero(_amountOfDSCToMint) nonReentrant {
        s_userToAmounOfDSCMinted[msg.sender] += _amountOfDSCToMint;
    }

    function burnDSC() external {}

    function liquidate() external {}

    function getHealthFactor() external view returns (uint256) {}

    //////////////////////////////////
    // Functions Internal & Private //
    //////////////////////////////////
    function _getAccountInformation(address _user)
        private
        view
        returns (uint256 totalDSCMinted, uint256 collateralValueInUsd)
    {
        totalDSCMinted = s_userToAmounOfDSCMinted[_user];
        collateralValueInUsd = getAccountCollateralValue(_user);
    }

    function _healthFactor(address user) private view returns (uint256) {}

    function _revertIfHealthFactorIsBroken(address _user) internal view {}

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
    }

    function getUSDValue(address _tokenAddress, uint256 _tokenAmount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_tokenAddressToPriceFeedAddress[_tokenAddress]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        // we have to make sure that the decimal places from the price feed are correct. In our case ETH and BTC have the same decimals, but other chains might not.
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * _tokenAmount) / PRECISION;
    }
}
