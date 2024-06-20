// SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;
pragma abicoder v2;

import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { SafeMathUpgradeable } from "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import { SignedSafeMathUpgradeable } from "@openzeppelin/contracts-upgradeable/math/SignedSafeMathUpgradeable.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";
import { ExponentialMovingAverage } from "../common/math/ExponentialMovingAverage.sol";
import { IJackPriceOracle } from "../interfaces/jack/IJackPriceOracle.sol";
import { IJackSyntheticToken } from "../interfaces/jack/IJackSyntheticToken.sol";
import { IJackLeveragedToken } from "../interfaces/jack/IJackLeveragedToken.sol";
import { IJackMarket } from "../interfaces/jack/IJackMarket.sol";
import { IJackRateProvider } from "../interfaces/jack/IJackRateProvider.sol";
import { IJackTreasury } from "../interfaces/jack/IJackTreasury.sol";
import { StableCoinMath } from "./StableCoinMath.sol";

// solhint-disable no-empty-blocks
// solhint-disable not-rely-on-time

contract Treasury is OwnableUpgradeable, IJackTreasury {
  using SafeERC20Upgradeable for IERC20Upgradeable;
  using SafeMathUpgradeable for uint256;
  using SignedSafeMathUpgradeable for int256;
  using StableCoinMath for StableCoinMath.SwapState;
  using ExponentialMovingAverage for ExponentialMovingAverage.EMAStorage;

  /**********
   * Events *
   **********/
  /// @notice Emitted when the whitelist status for settle is updated.
  /// @param account The address of account to change.
  /// @param status The new whitelist status.
  event UpdateSettleWhitelist(address account, bool status);

  /// @notice Emitted when the price oracle contract is updated.
  /// @param priceOracle The address of new price oracle.
  event UpdatePriceOracle(address priceOracle);

  /// @notice Emitted when the rate provider contract is updated.
  /// @param rateProvider The address of new rate provider.
  event UpdateRateProvider(address rateProvider);

  /// @notice Emitted when the beta for aToken is updated.
  /// @param beta The new value of beta.
  event UpdateBeta(uint256 beta);

  /// @notice Emitted when the base token cap is updated.
  /// @param baseTokenCap The new base token cap.
  event UpdateBaseTokenCap(uint256 baseTokenCap);

  /// @notice Emitted when v2 is initialized
  /// @param sampleInterval Init parameter
  event V2Initialized(uint24 sampleInterval);

  /// @notice Emitted when ema sample is updated
  /// @param sampleInterval Init parameter
  event UpdateEMASampleInterval(uint24 sampleInterval);

  /*************
   * Constants *
   *************/

  /// @dev The precision used to compute nav.
  uint256 internal constant PRECISION = 1e18;

  /// @dev The precision used to compute nav.
  int256 private constant PRECISION_I256 = 1e18;

  /// @dev The initial mint ratio for aToken.
  uint256 private immutable initialMintRatio;

  /*************
   * Variables *
   *************/

  /// @notice The address of market contract.
  address public market;

  /// @inheritdoc IJackTreasury
  address public override baseToken;

  /// @inheritdoc IJackTreasury
  address public override aToken;

  /// @inheritdoc IJackTreasury
  address public override xToken;

  /// @notice The address of price oracle contract.
  address public priceOracle;

  /// @notice The volitality multiple of aToken compare to base token.
  uint256 public beta;

  /// @inheritdoc IJackTreasury
  uint256 public override lastPermissionedPrice;

  /// @notice The maximum amount of base token can be deposited.
  uint256 public baseTokenCap;

  /// @inheritdoc IJackTreasury
  uint256 public override totalBaseToken;

  /// @notice Whether the sender is allowed to do settlement.
  mapping(address => bool) public settleWhitelist;

  /// @notice The address of rate provider contract.
  address public rateProvider;

  /// @notice The ema storage of the leverage ratio.
  ExponentialMovingAverage.EMAStorage public emaLeverageRatio;

  /// @dev Slots for future use.
  uint256[37] private _gap;

  /************
   * Modifier *
   ************/

  modifier onlyMarket() {
    require(msg.sender == market, "Only market");
    _;
  }

  /***************
   * Constructor *
   ***************/

  constructor(uint256 _initialMintRatio) {
    require(0 < _initialMintRatio, "invalid initial mint ratio");
    require(_initialMintRatio < PRECISION, "invalid initial mint ratio"); 
    initialMintRatio = _initialMintRatio;
  }

  function initialize(
    address _market,
    address _baseToken,
    address _aToken,
    address _xToken,
    address _priceOracle,
    uint256 _beta,
    uint256 _baseTokenCap,
    address _rateProvider
  ) external initializer {
    OwnableUpgradeable.__Ownable_init();

    market = _market;
    baseToken = _baseToken;
    aToken = _aToken;
    xToken = _xToken;
    priceOracle = _priceOracle;
    beta = _beta;
    baseTokenCap = _baseTokenCap;

    if (_rateProvider != address(0)) {
      rateProvider = _rateProvider;
    }
  }

  function initializeV2(uint24 sampleInterval) external {
    ExponentialMovingAverage.EMAStorage memory cachedEmaLeverageRatio = emaLeverageRatio;
    require(cachedEmaLeverageRatio.lastTime == 0, "v2 initialized");

    cachedEmaLeverageRatio.lastTime = uint40(block.timestamp);
    cachedEmaLeverageRatio.sampleInterval = sampleInterval;
    cachedEmaLeverageRatio.lastValue = uint96(PRECISION);
    cachedEmaLeverageRatio.lastEmaValue = uint96(PRECISION);

    emaLeverageRatio = cachedEmaLeverageRatio;
    emit V2Initialized(sampleInterval);
  }

  /*************************
   * Public View Functions *
   *************************/

  /// @inheritdoc IJackTreasury
  function collateralRatio() external view override returns (uint256) {
    StableCoinMath.SwapState memory _state = _loadSwapState();

    if (_state.baseSupply == 0) return PRECISION;
    if (_state.fSupply == 0) return PRECISION * PRECISION;

    return _state.baseSupply.mul(_state.baseNav).div(_state.fSupply);
  }

  /// @inheritdoc IJackTreasury
  function currentBaseTokenPrice() external view override returns (uint256) {
    return _fetchTwapPrice();
  }


  /// @inheritdoc IJackTreasury
  function isBaseTokenPriceValid() external view override returns (bool _isValid) {
    (_isValid, ) = IJackPriceOracle(priceOracle).getPrice();
  }

  /// @inheritdoc IJackTreasury
  function isUnderCollateral() external view override returns (bool) {
    StableCoinMath.SwapState memory _state = _loadSwapState();
    return _state.xNav == 0;
  }

  /// @inheritdoc IJackTreasury
  function xAVAXLeverageRatio() external view override returns (uint256) {
    StableCoinMath.SwapState memory _state = _loadSwapState();
    return _state.leverageRatio();
  }

  /// @inheritdoc IJackTreasury
  function getCurrentNav()
    external
    view
    override
    returns (
      uint256 _baseNav,
      uint256 _aNav,
      uint256 _xNav
    )
  {
    StableCoinMath.SwapState memory _state = _loadSwapState();

    _baseNav = _state.baseNav;
    _aNav = IJackSyntheticToken(aToken).nav();
    _xNav = _state.xNav;
  }

  /// @inheritdoc IJackTreasury
  /// @dev If the current collateral ratio <= new collateral ratio, we should return 0.
  function maxMintableaToken(uint256 _newCollateralRatio)
    external
    view
    override
    returns (uint256 _maxBaseIn, uint256 _maxaTokenMintable)
  {
    require(_newCollateralRatio > PRECISION, "collateral ratio too small");

    StableCoinMath.SwapState memory _state = _loadSwapState();
    (_maxBaseIn, _maxaTokenMintable) = _state.maxMintableaToken(_newCollateralRatio);
  }

  /// @inheritdoc IJackTreasury
  /// @dev If the current collateral ratio >= new collateral ratio, we should return 0.
  function maxMintableXToken(uint256 _newCollateralRatio)
    external
    view
    override
    returns (uint256 _maxBaseIn, uint256 _maxXTokenMintable)
  {
    require(_newCollateralRatio > PRECISION, "collateral ratio too small");

    StableCoinMath.SwapState memory _state = _loadSwapState();
    (_maxBaseIn, _maxXTokenMintable) = _state.maxMintableXToken(_newCollateralRatio);
  }

  /// @inheritdoc IJackTreasury
  /// @dev If the current collateral ratio >= new collateral ratio, we should return 0.
  function maxMintableXTokenWithIncentive(uint256 _newCollateralRatio, uint256 _incentiveRatio)
    external
    view
    override
    returns (uint256 _maxBaseIn, uint256 _maxXTokenMintable)
  {
    require(_newCollateralRatio > PRECISION, "collateral ratio too small");

    StableCoinMath.SwapState memory _state = _loadSwapState();
    (_maxBaseIn, _maxXTokenMintable) = _state.maxMintableXTokenWithIncentive(_newCollateralRatio, _incentiveRatio);
  }

  /// @inheritdoc IJackTreasury
  /// @dev If the current collateral ratio >= new collateral ratio, we should return 0.
  function maxRedeemableaToken(uint256 _newCollateralRatio)
    external
    view
    override
    returns (uint256 _maxBaseOut, uint256 _maxaTokenRedeemable)
  {
    require(_newCollateralRatio > PRECISION, "collateral ratio too small");

    StableCoinMath.SwapState memory _state = _loadSwapState();
    (_maxBaseOut, _maxaTokenRedeemable) = _state.maxRedeemableaToken(_newCollateralRatio);
  }

  /// @inheritdoc IJackTreasury
  /// @dev If the current collateral ratio <= new collateral ratio, we should return 0.
  function maxRedeemableXToken(uint256 _newCollateralRatio)
    external
    view
    override
    returns (uint256 _maxBaseOut, uint256 _maxXTokenRedeemable)
  {
    require(_newCollateralRatio > PRECISION, "collateral ratio too small");

    StableCoinMath.SwapState memory _state = _loadSwapState();
    (_maxBaseOut, _maxXTokenRedeemable) = _state.maxRedeemableXToken(_newCollateralRatio);
  }

  /// @inheritdoc IJackTreasury
  /// @dev If the current collateral ratio >= new collateral ratio, we should return 0.
  function maxLiquidatable(uint256 _newCollateralRatio, uint256 _incentiveRatio)
    external
    view
    override
    returns (uint256 _maxBaseOut, uint256 _maxaTokenLiquidatable)
  {
    require(_newCollateralRatio > PRECISION, "collateral ratio too small");

    StableCoinMath.SwapState memory _state = _loadSwapState();
    (_maxBaseOut, _maxaTokenLiquidatable) = _state.maxLiquidatable(_newCollateralRatio, _incentiveRatio);
  }


  /// @inheritdoc IJackTreasury
  function convertToWrapped(uint256 _amount) public view override returns (uint256) {
    address _rateProvider = rateProvider;
    if (_rateProvider != address(0)) {
      _amount = _amount.mul(PRECISION).div(IJackRateProvider(_rateProvider).getRate());
    }
    return _amount;
  }

  /// @inheritdoc IJackTreasury
  function convertToUnwrapped(uint256 _amount) external view override returns (uint256) {
    address _rateProvider = rateProvider;
    if (_rateProvider != address(0)) {
      _amount = _amount.mul(IJackRateProvider(_rateProvider).getRate()).div(PRECISION);
    }
    return _amount;
  }

  /// @inheritdoc IJackTreasury
  function leverageRatio() external view override returns (uint256) {
    return emaLeverageRatio.emaValue();
  }

  /****************************
   * Public Mutated Functions *
   ****************************/

  /// @inheritdoc IJackTreasury
  function mint(
    uint256 _baseIn,
    address _recipient,
    MintOption _option
  ) external override onlyMarket returns (uint256 _aTokenOut, uint256 _xTokenOut) {
    StableCoinMath.SwapState memory _state;

    if (_option == MintOption.aToken) {
      _state = _loadSwapState();
      require(_state.xNav != 0, "Error Under Collateral");
      _updateEMALeverageRatio(_state);
    } else if (_option == MintOption.XToken) {
      _state = _loadSwapState();
      require(_state.xNav != 0, "Error Under Collateral");
      _updateEMALeverageRatio(_state);
    } else {
      _state = _loadSwapState();
    }

    if (_option == MintOption.aToken) {
      _aTokenOut = _state.mintaToken(_baseIn);
      require(_aTokenOut != 0, "a very small amount");
    } else if (_option == MintOption.XToken) {
      _xTokenOut = _state.mintXToken(_baseIn);
    } else {
      if (_state.baseSupply == 0) {
        uint256 _totalVal = _baseIn.mul(_state.baseNav);
        _aTokenOut = _totalVal.mul(initialMintRatio).div(PRECISION).div(PRECISION);
        _xTokenOut = _totalVal.div(PRECISION).sub(_aTokenOut);
      } else {
        (_aTokenOut, _xTokenOut) = _state.mint(_baseIn);
      }
    }

    require(_state.baseSupply + _baseIn <= baseTokenCap, "Exceed total cap");
    totalBaseToken = _state.baseSupply + _baseIn;

    if (_aTokenOut > 0) {
      IJackSyntheticToken(aToken).mint(_recipient, _aTokenOut);
    }
    if (_xTokenOut > 0) {
      IJackLeveragedToken(xToken).mint(_recipient, _xTokenOut);
    }
  }

  /// @inheritdoc IJackTreasury
  function redeem(
    uint256 _aTokenIn,
    uint256 _xTokenIn,
    address _owner
  ) external override onlyMarket returns (uint256 _baseOut) {
    StableCoinMath.SwapState memory _state;

    if (_aTokenIn > 0) {
      _state = _loadSwapState();
    } else {
      _state = _loadSwapState();
    }
    _updateEMALeverageRatio(_state);

    _baseOut = _state.redeem(_aTokenIn, _xTokenIn);

    if (_aTokenIn > 0) {
      IJackSyntheticToken(aToken).burn(_owner, _aTokenIn);
    }

    if (_xTokenIn > 0) {
      IJackLeveragedToken(xToken).burn(_owner, _xTokenIn);
    }

    totalBaseToken = _state.baseSupply.sub(_baseOut);

    _transferBaseToken(_baseOut, msg.sender);
  }

  /*******************************
   * Public Restricted Functions *
   *******************************/

  function initializePrice() external onlyOwner {
    require(lastPermissionedPrice == 0, "only initialize price once");
    uint256 _price = _fetchTwapPrice();
    lastPermissionedPrice = _price;
    emit ProtocolSettle(_price, PRECISION);
  }

  /// @notice Change the value of aToken beta.
  /// @param _beta The new value of beta.
  function updateBeta(uint256 _beta) external onlyOwner {
    beta = _beta;

    emit UpdateBeta(_beta);
  }

  /// @notice Change address of price oracle contract.
  /// @param _priceOracle The new address of price oracle contract.
  function updatePriceOracle(address _priceOracle) external onlyOwner {
    require(_priceOracle != address(0), "zero registry address");
    priceOracle = _priceOracle;

    emit UpdatePriceOracle(_priceOracle);
  }

  /// @notice Change address of rate provider contract.
  /// @param _rateProvider The new address of rate provider contract.
  function updateRateProvider(address _rateProvider) external onlyOwner {
    require(_rateProvider != address(0), "zero registry address");
    rateProvider = _rateProvider;

    emit UpdateRateProvider(_rateProvider);
  }

  /// @notice Update the whitelist status for settle account.
  /// @param _account The address of account to update.
  /// @param _status The status of the account to update.
  function updateSettleWhitelist(address _account, bool _status) external onlyOwner {
    require(_account != address(0), "zero registry address");
    settleWhitelist[_account] = _status;

    emit UpdateSettleWhitelist(_account, _status);
  }

  /// @notice Update the base token cap.
  /// @param _baseTokenCap The new base token cap.
  function updateBaseTokenCap(uint256 _baseTokenCap) external onlyOwner {
    baseTokenCap = _baseTokenCap;

    emit UpdateBaseTokenCap(_baseTokenCap);
  }

  /// @notice Update the EMA sample interval.
  /// @param _sampleInterval The new EMA sample interval.
  function updateEMASampleInterval(uint24 _sampleInterval) external onlyOwner {
    require(_sampleInterval >= 1 minutes, "EMA sample interval too small");

    StableCoinMath.SwapState memory _state = _loadSwapState();
    _updateEMALeverageRatio(_state);

    emaLeverageRatio.sampleInterval = _sampleInterval;
    emit UpdateEMASampleInterval(_sampleInterval);
  }

  /**********************
   * Internal Functions *
   **********************/

  /// @dev Internal function to transfer base token to receiver.
  /// @param _amount The amount of base token to transfer.
  /// @param _recipient The address of receiver.
  function _transferBaseToken(uint256 _amount, address _recipient) internal returns (uint256) {
    _amount = convertToWrapped(_amount);
    address _baseToken = baseToken;

    IERC20Upgradeable(_baseToken).safeTransfer(_recipient, _amount);
    return _amount;
  }

  /// @dev Internal function to load swap variable to memory
  function _loadSwapState() internal view returns (StableCoinMath.SwapState memory _state) {
    _state.baseSupply = totalBaseToken;
    _state.baseNav = _fetchTwapPrice();

    if (_state.baseSupply == 0) {
      _state.xNav = PRECISION;
    } else {
      _state.fSupply = IERC20Upgradeable(aToken).totalSupply();
      _state.xSupply = IERC20Upgradeable(xToken).totalSupply();

      if (_state.xSupply == 0) {
        // no xToken, treat the nav of xToken as 1.0
        _state.xNav = PRECISION;
      } else {
        uint256 _baseVal = _state.baseSupply.mul(_state.baseNav);
        uint256 _aVal = _state.fSupply.mul(PRECISION);
        if (_baseVal >= _aVal) {
          _state.xNav = (_baseVal.sub(_aVal)).div(_state.xSupply);
        } else {
          // under collateral
          _state.xNav = 0;
        }
      }
    }
  }

  /// @dev Internal function to update ema leverage ratio.
  function _updateEMALeverageRatio(StableCoinMath.SwapState memory _state) internal {
    uint256 _ratio = _state.leverageRatio();

    ExponentialMovingAverage.EMAStorage memory cachedEmaLeverageRatio = emaLeverageRatio;
    // The value is capped with 100*10^18, it is safe to cast.
    cachedEmaLeverageRatio.saveValue(uint96(_ratio));
    emaLeverageRatio = cachedEmaLeverageRatio;
  }

  /// @dev Internal function to fetch twap price.
  /// @return _price The twap price of the base token.
  function _fetchTwapPrice() internal view returns (uint256 _price) {
    (bool _isValid, uint256 _safePrice) = IJackPriceOracle(priceOracle).getPrice();
    _price = _safePrice;
    require(_isValid, "oracle price is invalid");
    require(_price > 0, "invalid twap price");
  }
}