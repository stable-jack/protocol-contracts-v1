// SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { SafeMathUpgradeable } from "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import { IJackMarket } from "../interfaces/jack/IJackMarket.sol";
import { IJackReservePool } from "../interfaces/jack/IJackReservePool.sol";
import { IJackTreasury } from "../interfaces/jack/IJackTreasury.sol";

// solhint-disable max-states-count

contract Market is AccessControlUpgradeable, ReentrancyGuardUpgradeable, IJackMarket {
  using SafeERC20Upgradeable for IERC20Upgradeable;
  using SafeMathUpgradeable for uint256;

  /**********
   * Events *
   **********/

  /// @notice Emitted when the fee ratio for minting aToken is updated.
  /// @param defaultFeeRatio The new default fee ratio, multipled by 1e18.
  /// @param extraFeeRatio The new extra fee ratio, multipled by 1e18.
  event UpdateMintFeeRatioaToken(uint128 defaultFeeRatio, int128 extraFeeRatio);

  /// @notice Emitted when the fee ratio for minting xToken is updated.
  /// @param defaultFeeRatio The new default fee ratio, multipled by 1e18.
  /// @param extraFeeRatio The new extra fee ratio, multipled by 1e18.
  event UpdateMintFeeRatioXToken(uint128 defaultFeeRatio, int128 extraFeeRatio);

  /// @notice Emitted when the fee ratio for redeeming aToken is updated.
  /// @param defaultFeeRatio The new default fee ratio, multipled by 1e18.
  /// @param extraFeeRatio The new extra fee ratio, multipled by 1e18.
  event UpdateRedeemFeeRatioaToken(uint128 defaultFeeRatio, int128 extraFeeRatio);

  /// @notice Emitted when the fee ratio for redeeming xToken is updated.
  /// @param defaultFeeRatio The new default fee ratio, multipled by 1e18.
  /// @param extraFeeRatio The new extra fee ratio, multipled by 1e18.
  event UpdateRedeemFeeRatioXToken(uint128 defaultFeeRatio, int128 extraFeeRatio);

  /// @notice Emitted when the market config is updated.
  /// @param stabilityRatio The new start collateral ratio to enter system stability mode, multiplied by 1e18.
  /// @param liquidationRatio The new start collateral ratio to enter incentivized user liquidation mode, multiplied by 1e18.
  /// @param selfLiquidationRatio The new start collateral ratio to enter self liquidation mode, multiplied by 1e18.
  /// @param recapRatio The new start collateral ratio to enter recap mode, multiplied by 1e18.
  event UpdateMarketConfig(
    uint64 stabilityRatio,
    uint64 liquidationRatio,
    uint64 selfLiquidationRatio,
    uint64 recapRatio
  );

  /// @notice Emitted when the incentive config is updated.
  /// @param stabilityIncentiveRatio The new incentive ratio for system stability mode, multiplied by 1e18.
  /// @param liquidationIncentiveRatio The new incentive ratio for incentivized user liquidation mode, multiplied by 1e18.
  /// @param selfLiquidationIncentiveRatio The new incentive ratio for self liquidation mode, multiplied by 1e18.
  event UpdateIncentiveConfig(
    uint64 stabilityIncentiveRatio,
    uint64 liquidationIncentiveRatio,
    uint64 selfLiquidationIncentiveRatio
  );

  /// @notice Emitted when the whitelist status for settle is changed.
  /// @param account The address of account to change.
  /// @param status The new whitelist status.
  event UpdateLiquidationWhitelist(address account, bool status);

  /// @notice Emitted when the platform contract is changed.
  /// @param platform The address of new platform.
  event UpdatePlatform(address platform);

  /// @notice Emitted when the  reserve pool contract is changed.
  /// @param reservePool The address of new reserve pool.
  event UpdateReservePool(address reservePool);

  /// @notice Pause or unpause mint.
  /// @param status The new status for mint.
  event PauseMint(bool status);

  /// @notice Pause or unpause special functions.
  /// @param status The new status for mint.
  event PauseFunctions(bool status); 

  /// @notice Pause or unpause redeem.
  /// @param status The new status for redeem.
  event PauseRedeem(bool status);

  /// @notice Pause or unpause aToken mint in system stability mode.
  /// @param status The new status for mint.
  event PauseaTokenMintInSystemStabilityMode(bool status);

  /// @notice Pause or unpause xToken redeem in system stability mode.
  /// @param status The new status for redeem.
  event PauseXTokenRedeemInSystemStabilityMode(bool status);

  /*************
   * Constants *
   *************/

  /// @dev The precision used to compute nav.
  uint256 private constant PRECISION = 1e18;

  /***********
   * Structs *
   ***********/

  /// @dev Compiler will pack this into single `uint256`.
  struct FeeRatio {
    // The default fee ratio, multiplied by 1e18.
    uint128 defaultFeeRatio;
    // The extra delta fee ratio, multiplied by 1e18.
    int128 extraFeeRatio;
  }

  /// @dev Compiler will pack this into single `uint256`.
  struct MarketConfig {
    // The start collateral ratio to enter system stability mode, multiplied by 1e18.
    uint64 stabilityRatio;
    // The start collateral ratio to enter incentivized user liquidation mode, multiplied by 1e18.
    uint64 liquidationRatio;
    // The start collateral ratio to enter self liquidation mode, multiplied by 1e18.
    uint64 selfLiquidationRatio;
    // The start collateral ratio to enter recap mode, multiplied by 1e18.
    uint64 recapRatio;
  }

  /// @dev Compiler will pack this into single `uint256`.
  struct IncentiveConfig {
    // The incentive ratio for system stability mode, multiplied by 1e18.
    uint64 stabilityIncentiveRatio;
    // The incentive ratio for incentivized user liquidation mode, multiplied by 1e18.
    uint64 liquidationIncentiveRatio;
    // The incentive ratio for self liquidation mode, multiplied by 1e18.
    uint64 selfLiquidationIncentiveRatio;
  }

  /*************
   * Variables *
   *************/

  /// @notice The address of Treasury contract.
  address public treasury;

  /// @notice The address of platform contract;
  address public platform;

  /// @notice The address base token;
  address public baseToken;

  /// @notice The address fractional base token.
  address public aToken;

  /// @notice The address leveraged base token.
  address public xToken;

  ///@notice The address of sAVAXGateway
  address public sAVAXGateway;

  /// @notice The market config in each mode.
  MarketConfig public marketConfig;

  /// @notice The incentive config in each mode.
  IncentiveConfig public incentiveConfig;

  /// @notice The mint fee ratio for aToken.
  FeeRatio public aTokenMintFeeRatio;

  /// @notice The mint fee ratio for xToken.
  FeeRatio public xTokenMintFeeRatio;

  /// @notice The redeem fee ratio for aToken.
  FeeRatio public aTokenRedeemFeeRatio;

  /// @notice The redeem fee ratio for xToken.
  FeeRatio public xTokenRedeemFeeRatio;

  /// @notice Whether the sender is allowed to do self liquidation.
  mapping(address => bool) public liquidationWhitelist;

  /// @notice Whether the mint is paused.
  bool public mintPaused;

  /// @notice Whether the redeem is paused.
  bool public redeemPaused;

  /// @notice Whether to unpause the functions
  bool public functionsPaused;

  /// @notice Whether to pause aToken mint in system stability mode
  bool public aTokenMintInSystemStabilityModePaused;

  /// @notice Whether to pause xToken redeem in system stability mode
  bool public xTokenRedeemInSystemStabilityModePaused;

  /// @notice The address of ReservePool contract.
  address public reservePool;

  /************
   * Modifier *
   ************/

  modifier onlyAdmin() {
    require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "only Admin");
    _;
  }

  modifier onlyGateway() {
    require(msg.sender == sAVAXGateway, "only gateway");
    _;
  }

  /***************
   * Constructor *
   ***************/

  function initialize(address _treasury, address _platform, address _gateway) external initializer {
    AccessControlUpgradeable.__AccessControl_init();
    ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
    _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);

    treasury = _treasury;
    platform = _platform;

    baseToken = IJackTreasury(_treasury).baseToken();
    aToken = IJackTreasury(_treasury).aToken();
    xToken = IJackTreasury(_treasury).xToken();
    sAVAXGateway = _gateway;
  }

  /****************************
   * Public Mutated Functions *
   ****************************/

  /// @inheritdoc IJackMarket
  function mint(
    uint256 _baseIn,
    address _recipient,
    uint256 _minaTokenMinted,
    uint256 _minXTokenMinted
  ) external override nonReentrant returns (uint256 _aTokenMinted, uint256 _xTokenMinted) {
    address _baseToken = baseToken;
    if (_baseIn == uint256(-1)) {
      _baseIn = IERC20Upgradeable(_baseToken).balanceOf(msg.sender);
    }
    require(_baseIn > 0, "mint zero amount");

    IJackTreasury _treasury = IJackTreasury(treasury);
    require(_treasury.totalBaseToken() == 0, "only initialize once");

    IERC20Upgradeable(_baseToken).safeTransferFrom(msg.sender, address(_treasury), _baseIn);
    (_aTokenMinted, _xTokenMinted) = _treasury.mint(
      _treasury.convertToUnwrapped(_baseIn),
      _recipient,
      IJackTreasury.MintOption.Both
    );

    require(_aTokenMinted >= _minaTokenMinted, "insufficient aToken output");
    require(_xTokenMinted >= _minXTokenMinted, "insufficient xToken output");

    emit Mint(msg.sender, _recipient, _baseIn, _aTokenMinted, _xTokenMinted, 0);
  }

  /// @inheritdoc IJackMarket
  function mintaToken(
    uint256 _baseIn,
    address _recipient,
    uint256 _minaTokenMinted
  ) external onlyGateway override nonReentrant returns (uint256 _aTokenMinted) {
    require(!mintPaused, "mint is paused");

    address _baseToken = baseToken;
    if (_baseIn == uint256(-1)) {
      _baseIn = IERC20Upgradeable(_baseToken).balanceOf(msg.sender);
    }
    require(_baseIn > 0, "mint zero amount");

    IJackTreasury _treasury = IJackTreasury(treasury);
    (uint256 _maxBaseInBeforeSystemStabilityMode, ) = _treasury.maxMintableaToken(marketConfig.stabilityRatio);
    _maxBaseInBeforeSystemStabilityMode = _treasury.convertToWrapped(_maxBaseInBeforeSystemStabilityMode);

    if (aTokenMintInSystemStabilityModePaused) {
      uint256 _collateralRatio = _treasury.collateralRatio();
      require(_collateralRatio > marketConfig.stabilityRatio, "aToken mint paused");

      // bound maximum amount of base token to mint aToken.
      if (_baseIn > _maxBaseInBeforeSystemStabilityMode) {
        _baseIn = _maxBaseInBeforeSystemStabilityMode;
      }
    }

    uint256 _amountWithoutFee = _deductaTokenMintFee(_baseIn, aTokenMintFeeRatio, _maxBaseInBeforeSystemStabilityMode);

    IERC20Upgradeable(_baseToken).safeTransferFrom(msg.sender, address(_treasury), _amountWithoutFee);
    (_aTokenMinted, ) = _treasury.mint(
      _treasury.convertToUnwrapped(_amountWithoutFee),
      _recipient,
      IJackTreasury.MintOption.aToken
    );
    require(_aTokenMinted >= _minaTokenMinted, "insufficient aToken output");

    emit Mint(msg.sender, _recipient, _baseIn, _aTokenMinted, 0, _baseIn - _amountWithoutFee);
  }

  /// @inheritdoc IJackMarket
  function mintXToken(
    uint256 _baseIn,
    address _recipient,
    uint256 _minXTokenMinted
  ) external onlyGateway override nonReentrant returns (uint256 _xTokenMinted, uint256 _bonus) {
    require(!mintPaused, "mint is paused");

    address _baseToken = baseToken;
    if (_baseIn == uint256(-1)) {
      _baseIn = IERC20Upgradeable(_baseToken).balanceOf(msg.sender);
    }
    require(_baseIn > 0, "mint zero amount");

    IJackTreasury _treasury = IJackTreasury(treasury);
    (uint256 _maxBaseInBeforeSystemStabilityMode, ) = _treasury.maxMintableXToken(marketConfig.stabilityRatio);
    _maxBaseInBeforeSystemStabilityMode = _treasury.convertToWrapped(_maxBaseInBeforeSystemStabilityMode);

    uint256 _amountWithoutFee = _deductXTokenMintFee(_baseIn, xTokenMintFeeRatio, _maxBaseInBeforeSystemStabilityMode);

    IERC20Upgradeable(_baseToken).safeTransferFrom(msg.sender, address(_treasury), _amountWithoutFee);
    (, _xTokenMinted) = _treasury.mint(
      _treasury.convertToUnwrapped(_amountWithoutFee),
      _recipient,
      IJackTreasury.MintOption.XToken
    );
    require(_xTokenMinted >= _minXTokenMinted, "insufficient xToken output");

    _bonus = 0;
    
    emit Mint(msg.sender, _recipient, _baseIn, 0, _xTokenMinted, _baseIn - _amountWithoutFee);
  }


  /// @inheritdoc IJackMarket
  function redeem(
    uint256 _aTokenIn,
    uint256 _xTokenIn,
    address _recipient,
    uint256 _minBaseOut
  ) external onlyGateway override nonReentrant returns (uint256 _baseOut, uint256 _bonus) {
    require(!redeemPaused, "redeem is paused");

    if (_aTokenIn == uint256(-1)) {
      _aTokenIn = IERC20Upgradeable(aToken).balanceOf(msg.sender);
    }
    if (_xTokenIn == uint256(-1)) {
      _xTokenIn = IERC20Upgradeable(xToken).balanceOf(msg.sender);
    }
    require(_aTokenIn > 0 || _xTokenIn > 0, "redeem zero amount");
    require(_aTokenIn == 0 || _xTokenIn == 0, "only redeem single side");

    IJackTreasury _treasury = IJackTreasury(treasury);
    MarketConfig memory _marketConfig = marketConfig;

    uint256 _feeRatio;
    uint256 _maxBaseOut;
    if (_aTokenIn > 0) {
      uint256 _maxaTokenInBeforeSystemStabilityMode;
      (_maxBaseOut, _maxaTokenInBeforeSystemStabilityMode) = _treasury.maxRedeemableaToken(
        _marketConfig.stabilityRatio
      );
      _feeRatio = _computeaTokenRedeemFeeRatio(_aTokenIn, aTokenRedeemFeeRatio, _maxaTokenInBeforeSystemStabilityMode);
    } else {
      (, uint256 _maxXTokenInBeforeSystemStabilityMode) = _treasury.maxRedeemableXToken(_marketConfig.stabilityRatio);

      if (xTokenRedeemInSystemStabilityModePaused) {
        uint256 _collateralRatio = _treasury.collateralRatio();
        require(_collateralRatio > _marketConfig.stabilityRatio, "xToken redeem paused");

        // bound maximum amount of xToken to redeem.
        if (_xTokenIn > _maxXTokenInBeforeSystemStabilityMode) {
          _xTokenIn = _maxXTokenInBeforeSystemStabilityMode;
        }
      }

      _feeRatio = _computeXTokenRedeemFeeRatio(_xTokenIn, xTokenRedeemFeeRatio, _maxXTokenInBeforeSystemStabilityMode);
    }

    _baseOut = _treasury.redeem(_aTokenIn, _xTokenIn, msg.sender);
    if (_aTokenIn > 0) {
      // give bonus when redeem aToken
      if (_baseOut < _maxBaseOut) {
        _bonus = _baseOut;
      } else {
        _bonus = _maxBaseOut;
      }
      // deduct fee
      {
        FeeRatio memory _ratio = aTokenRedeemFeeRatio;
        _bonus -= (_bonus * uint256(int256(_ratio.defaultFeeRatio) + _ratio.extraFeeRatio)) / PRECISION;
      }
      _bonus = 0;
    }

    _baseOut = _treasury.convertToWrapped(_baseOut);
    uint256 _balance = IERC20Upgradeable(baseToken).balanceOf(address(this));
    // consider possible slippage
    if (_balance < _baseOut) {
      _baseOut = _balance;
    }

    uint256 _fee = (_baseOut * _feeRatio) / PRECISION;
    if (_fee > 0) {
      IERC20Upgradeable(baseToken).safeTransfer(platform, _fee);
      _baseOut = _baseOut - _fee;
    }
    require(_baseOut >= _minBaseOut, "insufficient base output");

    IERC20Upgradeable(baseToken).safeTransfer(_recipient, _baseOut);

    emit Redeem(msg.sender, _recipient, _aTokenIn, _xTokenIn, _baseOut, _fee);
  }

  /*******************************
   * Public Restricted Functions *
   *******************************/

  /// @notice Update the fee ratio for redeeming.
  /// @param _defaultFeeRatio The new default fee ratio, multipled by 1e18.
  /// @param _extraFeeRatio The new extra fee ratio, multipled by 1e18.
  /// @param _isaToken Whether we are updating for aToken.
  function updateRedeemFeeRatio(
    uint128 _defaultFeeRatio,
    int128 _extraFeeRatio,
    bool _isaToken
  ) external onlyAdmin {
    require(_defaultFeeRatio <= PRECISION, "default fee ratio too large");
    if (_extraFeeRatio < 0) {
      require(uint128(-_extraFeeRatio) <= _defaultFeeRatio, "delta fee too small");
    } else {
      require(uint128(_extraFeeRatio) <= PRECISION - _defaultFeeRatio, "total fee too large");
    }

    if (_isaToken) {
      aTokenRedeemFeeRatio = FeeRatio(_defaultFeeRatio, _extraFeeRatio);
      emit UpdateRedeemFeeRatioaToken(_defaultFeeRatio, _extraFeeRatio);
    } else {
      xTokenRedeemFeeRatio = FeeRatio(_defaultFeeRatio, _extraFeeRatio);
      emit UpdateRedeemFeeRatioXToken(_defaultFeeRatio, _extraFeeRatio);
    }
  }

  /// @notice Update the fee ratio for minting.
  /// @param _defaultFeeRatio The new default fee ratio, multipled by 1e18.
  /// @param _extraFeeRatio The new extra fee ratio, multipled by 1e18.
  /// @param _isaToken Whether we are updating for aToken.
  function updateMintFeeRatio(
    uint128 _defaultFeeRatio,
    int128 _extraFeeRatio,
    bool _isaToken
  ) external onlyAdmin {
    require(_defaultFeeRatio <= PRECISION, "default fee ratio too large");
    if (_extraFeeRatio < 0) {
      require(uint128(-_extraFeeRatio) <= _defaultFeeRatio, "delta fee too small");
    } else {
      require(uint128(_extraFeeRatio) <= PRECISION - _defaultFeeRatio, "total fee too large");
    }

    if (_isaToken) {
      aTokenMintFeeRatio = FeeRatio(_defaultFeeRatio, _extraFeeRatio);
      emit UpdateMintFeeRatioaToken(_defaultFeeRatio, _extraFeeRatio);
    } else {
      xTokenMintFeeRatio = FeeRatio(_defaultFeeRatio, _extraFeeRatio);
      emit UpdateMintFeeRatioXToken(_defaultFeeRatio, _extraFeeRatio);
    }
  }

  /// @notice Update the market config.
  /// @param _stabilityRatio The start collateral ratio to enter system stability mode to update, multiplied by 1e18.
  /// @param _liquidationRatio The start collateral ratio to enter incentivized user liquidation mode to update, multiplied by 1e18.
  /// @param _selfLiquidationRatio The start collateral ratio to enter self liquidation mode to update, multiplied by 1e18.
  /// @param _recapRatio The start collateral ratio to enter recap mode to update, multiplied by 1e18.
  function updateMarketConfig(
    uint64 _stabilityRatio,
    uint64 _liquidationRatio,
    uint64 _selfLiquidationRatio,
    uint64 _recapRatio
  ) external onlyAdmin {
    require(_stabilityRatio > _liquidationRatio, "invalid market config");
    require(_liquidationRatio > _selfLiquidationRatio, "invalid market config");
    require(_selfLiquidationRatio > _recapRatio, "invalid market config");
    require(_recapRatio >= PRECISION, "invalid market config");

    marketConfig = MarketConfig(_stabilityRatio, _liquidationRatio, _selfLiquidationRatio, _recapRatio);

    emit UpdateMarketConfig(_stabilityRatio, _liquidationRatio, _selfLiquidationRatio, _recapRatio);
  }

  /// @notice Update the incentive config.
  /// @param _stabilityIncentiveRatio The incentive ratio for system stability mode to update, multiplied by 1e18.
  /// @param _liquidationIncentiveRatio The incentive ratio for incentivized user liquidation mode to update, multiplied by 1e18.
  /// @param _selfLiquidationIncentiveRatio The incentive ratio for self liquidation mode to update, multiplied by 1e18.
  function updateIncentiveConfig(
    uint64 _stabilityIncentiveRatio,
    uint64 _liquidationIncentiveRatio,
    uint64 _selfLiquidationIncentiveRatio
  ) external onlyAdmin {
    require(_stabilityIncentiveRatio > 0, "incentive too small");
    require(_selfLiquidationIncentiveRatio > 0, "incentive too small");
    require(_liquidationIncentiveRatio >= _selfLiquidationIncentiveRatio, "invalid incentive config");

    incentiveConfig = IncentiveConfig(
      _stabilityIncentiveRatio,
      _liquidationIncentiveRatio,
      _selfLiquidationIncentiveRatio
    );

    emit UpdateIncentiveConfig(_stabilityIncentiveRatio, _liquidationIncentiveRatio, _selfLiquidationIncentiveRatio);
  }

  /// @notice Change address of platform contract.
  /// @param _platform The new address of platform contract.
  function updatePlatform(address _platform) external onlyAdmin {
    require(_platform != address(0), "zero platform address");
    platform = _platform;

    emit UpdatePlatform(_platform);
  }

  /// @notice Change address of platform contract.
  /// @param _gateway The new address of platform contract.
  function updateGateway(address _gateway) external onlyAdmin {
    require(_gateway != address(0), "zero gateway address");
    sAVAXGateway = _gateway;

    emit UpdateGateway(_gateway);
  }

  /// @notice Change address of reserve pool contract.
  /// @param _reservePool The new address of reserve pool contract.
  function updateReservePool(address _reservePool) external onlyAdmin {
    require(_reservePool != address(0), "zero reserve pool address");
    reservePool = _reservePool;

    emit UpdateReservePool(_reservePool);
  }

  /// @notice Update the whitelist status for self liquidation account.
  /// @param _account The address of account to update.
  /// @param _status The status of the account to update.
  function updateLiquidationWhitelist(address _account, bool _status) external onlyAdmin {
    require(_account != address(0), "zero liquidation address");
    liquidationWhitelist[_account] = _status;

    emit UpdateLiquidationWhitelist(_account, _status);
  }

  /// @notice Pause mint in this contract
  /// @param _status The pause status.
  function pauseMint(bool _status) external onlyAdmin {
    mintPaused = _status;

    emit PauseMint(_status);
  }

  /// @notice Pause the functions
  /// @param _status The pause status.
  function pauseFunctions(bool _status) external onlyAdmin {
    functionsPaused = _status;

    emit PauseFunctions(_status);
  }

  /// @notice Pause redeem in this contract
  /// @param _status The pause status.
  function pauseRedeem(bool _status) external onlyAdmin {
    redeemPaused = _status;

    emit PauseRedeem(_status);
  }

  /// @notice Pause aToken mint in system stability mode.
  /// @param _status The pause status.
  function pauseaTokenMintInSystemStabilityMode(bool _status) external onlyAdmin {
    aTokenMintInSystemStabilityModePaused = _status;

    emit PauseaTokenMintInSystemStabilityMode(_status);
  }

  /// @notice Pause xToken redeem in system stability mode
  /// @param _status The pause status.
  function pauseXTokenRedeemInSystemStabilityMode(bool _status) external onlyAdmin {
    xTokenRedeemInSystemStabilityModePaused = _status;

    emit PauseXTokenRedeemInSystemStabilityMode(_status);
  }

  /**********************
   * Internal Functions *
   **********************/

  /// @dev Internal function to deduct aToken mint fee for base token.
  /// @param _baseIn The amount of base token.
  /// @param _ratio The mint fee ratio.
  /// @param _maxBaseInBeforeSystemStabilityMode The maximum amount of base token can be deposit before entering system stability mode.
  /// @return _baseInWithoutFee The amount of base token without fee.
  function _deductaTokenMintFee(
    uint256 _baseIn,
    FeeRatio memory _ratio,
    uint256 _maxBaseInBeforeSystemStabilityMode
  ) internal returns (uint256 _baseInWithoutFee) {
    // [0, _maxBaseInBeforeSystemStabilityMode) => default = fee_ratio_0
    // [_maxBaseInBeforeSystemStabilityMode, infinity) => default + extra = fee_ratio_1

    uint256 _feeRatio0 = _ratio.defaultFeeRatio;
    uint256 _feeRatio1 = uint256(int256(_ratio.defaultFeeRatio) + _ratio.extraFeeRatio);

    _baseInWithoutFee = _deductMintFee(_baseIn, _feeRatio0, _feeRatio1, _maxBaseInBeforeSystemStabilityMode);
  }

  /// @dev Internal function to deduct aToken mint fee for base token.
  /// @param _baseIn The amount of base token.
  /// @param _ratio The mint fee ratio.
  /// @param _maxBaseInBeforeSystemStabilityMode The maximum amount of base token can be deposit before entering system stability mode.
  /// @return _baseInWithoutFee The amount of base token without fee.
  function _deductXTokenMintFee(
    uint256 _baseIn,
    FeeRatio memory _ratio,
    uint256 _maxBaseInBeforeSystemStabilityMode
  ) internal returns (uint256 _baseInWithoutFee) {
    // [0, _maxBaseInBeforeSystemStabilityMode) => default + extra = fee_ratio_0
    // [_maxBaseInBeforeSystemStabilityMode, infinity) => default = fee_ratio_1

    uint256 _feeRatio0 = uint256(int256(_ratio.defaultFeeRatio) + _ratio.extraFeeRatio);
    uint256 _feeRatio1 = _ratio.defaultFeeRatio;

    _baseInWithoutFee = _deductMintFee(_baseIn, _feeRatio0, _feeRatio1, _maxBaseInBeforeSystemStabilityMode);
  }

  function _deductMintFee(
    uint256 _baseIn,
    uint256 _feeRatio0,
    uint256 _feeRatio1,
    uint256 _maxBaseInBeforeSystemStabilityMode
  ) internal returns (uint256 _baseInWithoutFee) {
    uint256 _maxBaseIn = _maxBaseInBeforeSystemStabilityMode.mul(PRECISION).div(PRECISION - _feeRatio0);

    // compute fee
    uint256 _fee;
    if (_baseIn <= _maxBaseIn) {
      _fee = _baseIn.mul(_feeRatio0).div(PRECISION);
    } else {
      _fee = _maxBaseIn.mul(_feeRatio0).div(PRECISION);
      _fee = _fee.add((_baseIn - _maxBaseIn).mul(_feeRatio1).div(PRECISION));
    }

    _baseInWithoutFee = _baseIn.sub(_fee);
    // take fee to platform
    if (_fee > 0) {
      IERC20Upgradeable(baseToken).safeTransferFrom(msg.sender, platform, _fee);
    }
  }

  /// @dev Internal function to deduct mint fee for base token.
  /// @param _amountIn The amount of aToken.
  /// @param _ratio The redeem fee ratio.
  /// @param _maxInBeforeSystemStabilityMode The maximum amount of aToken can be redeemed before leaving system stability mode.
  /// @return _feeRatio The computed fee ratio for base token redeemed.
  function _computeaTokenRedeemFeeRatio(
    uint256 _amountIn,
    FeeRatio memory _ratio,
    uint256 _maxInBeforeSystemStabilityMode
  ) internal pure returns (uint256 _feeRatio) {
    // [0, _maxBaseInBeforeSystemStabilityMode) => default + extra = fee_ratio_0
    // [_maxBaseInBeforeSystemStabilityMode, infinity) => default = fee_ratio_1

    uint256 _feeRatio0 = uint256(int256(_ratio.defaultFeeRatio) + _ratio.extraFeeRatio);
    uint256 _feeRatio1 = _ratio.defaultFeeRatio;

    _feeRatio = _computeRedeemFeeRatio(_amountIn, _feeRatio0, _feeRatio1, _maxInBeforeSystemStabilityMode);
  }

  /// @dev Internal function to deduct mint fee for base token.
  /// @param _amountIn The amount of xToken.
  /// @param _ratio The redeem fee ratio.
  /// @param _maxInBeforeSystemStabilityMode The maximum amount of xToken can be redeemed before entering system stability mode.
  /// @return _feeRatio The computed fee ratio for base token redeemed.
  function _computeXTokenRedeemFeeRatio(
    uint256 _amountIn,
    FeeRatio memory _ratio,
    uint256 _maxInBeforeSystemStabilityMode
  ) internal pure returns (uint256 _feeRatio) {
    // [0, _maxBaseInBeforeSystemStabilityMode) => default = fee_ratio_0
    // [_maxBaseInBeforeSystemStabilityMode, infinity) => default + extra = fee_ratio_1

    uint256 _feeRatio0 = _ratio.defaultFeeRatio;
    uint256 _feeRatio1 = uint256(int256(_ratio.defaultFeeRatio) + _ratio.extraFeeRatio);

    _feeRatio = _computeRedeemFeeRatio(_amountIn, _feeRatio0, _feeRatio1, _maxInBeforeSystemStabilityMode);
  }

  /// @dev Internal function to deduct mint fee for base token.
  /// @param _amountIn The amount of aToken or xToken.
  /// @param _feeRatio0 The default fee ratio.
  /// @param _feeRatio1 The second fee ratio.
  /// @param _maxInBeforeSystemStabilityMode The maximum amount of aToken/xToken can be redeemed before entering/leaving system stability mode.
  /// @return _feeRatio The computed fee ratio for base token redeemed.
  function _computeRedeemFeeRatio(
    uint256 _amountIn,
    uint256 _feeRatio0,
    uint256 _feeRatio1,
    uint256 _maxInBeforeSystemStabilityMode
  ) internal pure returns (uint256 _feeRatio) {
    if (_amountIn <= _maxInBeforeSystemStabilityMode) {
      return _feeRatio0;
    }
    uint256 _fee = _maxInBeforeSystemStabilityMode.mul(_feeRatio0);
    _fee = _fee.add((_amountIn - _maxInBeforeSystemStabilityMode).mul(_feeRatio1));
    return _fee.div(_amountIn);
  }
}
