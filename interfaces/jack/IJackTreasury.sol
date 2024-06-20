// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0 || ^0.8.0;

interface IJackTreasury {
  /**********
   * Events *
   **********/

  /// @notice Emitted when the net asset value is updated.
  /// @param price The new price of base token.
  /// @param aNav The new net asset value of aToken.
  event ProtocolSettle(uint256 price, uint256 aNav);

  /*********
   * Enums *
   *********/

  enum MintOption {
    Both,
    aToken,
    XToken
  }

  /*************************
   * Public View Functions *
   *************************/

  /// @notice Return the address of base token.
  function baseToken() external view returns (address);

  /// @notice Return the address fractional base token.
  function aToken() external view returns (address);

  /// @notice Return the address leveraged base token.
  function xToken() external view returns (address);

  /// @notice The last updated permissioned base token price.
  function lastPermissionedPrice() external view returns (uint256);

  /// @notice The current base token price.
  function currentBaseTokenPrice() external view returns (uint256);

  /// @notice Return whether the price is valid.
  function isBaseTokenPriceValid() external view returns (bool);

  /// @notice Return the total amount of base token deposited.
  function totalBaseToken() external view returns (uint256);

  /// @notice Return the current collateral ratio of aToken, multipled by 1e18.
  function collateralRatio() external view returns (uint256);

  /// @notice Return whether the system is under collateral.
  function isUnderCollateral() external view returns (bool);

  /// @notice Returns xAVAX leverage.
  function xAVAXLeverageRatio() external view returns (uint256);

  /// @notice Internal function to convert unwrapped token amount to wrapped token amount.
  /// @param amount The unwrapped token amount.
  function convertToWrapped(uint256 amount) external view returns (uint256);

  /// @notice Internal function to convert wrapped token amount to unwrapped token amount.
  /// @param amount The wrapped token amount.
  function convertToUnwrapped(uint256 amount) external view returns (uint256);

  /// @notice Return current nav for base token, aToken and xToken.
  /// @return baseNav The nav for base token.
  /// @return aNav The nav for aToken.
  /// @return xNav The nav for xToken.
  function getCurrentNav()
    external
    view
    returns (
      uint256 baseNav,
      uint256 aNav,
      uint256 xNav
    );

  /// @notice Compute the amount of base token needed to reach the new collateral ratio.
  /// @param newCollateralRatio The target collateral ratio, multipled by 1e18.
  /// @return maxBaseIn The amount of base token needed.
  /// @return maxaTokenMintable The amount of aToken can be minted.
  function maxMintableaToken(uint256 newCollateralRatio)
    external
    view
    returns (uint256 maxBaseIn, uint256 maxaTokenMintable);

  /// @notice Compute the amount of base token needed to reach the new collateral ratio.
  /// @param newCollateralRatio The target collateral ratio, multipled by 1e18.
  /// @return maxBaseIn The amount of base token needed.
  /// @return maxXTokenMintable The amount of xToken can be minted.
  function maxMintableXToken(uint256 newCollateralRatio)
    external
    view
    returns (uint256 maxBaseIn, uint256 maxXTokenMintable);

  /// @notice Compute the amount of base token needed to reach the new collateral ratio, with incentive.
  /// @param newCollateralRatio The target collateral ratio, multipled by 1e18.
  /// @param incentiveRatio The extra incentive ratio, multipled by 1e18.
  /// @return maxBaseIn The amount of base token needed.
  /// @return maxXTokenMintable The amount of xToken can be minted.
  function maxMintableXTokenWithIncentive(uint256 newCollateralRatio, uint256 incentiveRatio)
    external
    view
    returns (uint256 maxBaseIn, uint256 maxXTokenMintable);

  /// @notice Compute the amount of aToken needed to reach the new collateral ratio.
  /// @param newCollateralRatio The target collateral ratio, multipled by 1e18.
  /// @return maxBaseOut The amount of base token redeemed.
  /// @return maxaTokenRedeemable The amount of aToken needed.
  function maxRedeemableaToken(uint256 newCollateralRatio)
    external
    view
    returns (uint256 maxBaseOut, uint256 maxaTokenRedeemable);

  /// @notice Compute the amount of xToken needed to reach the new collateral ratio.
  /// @param newCollateralRatio The target collateral ratio, multipled by 1e18.
  /// @return maxBaseOut The amount of base token redeemed.
  /// @return maxXTokenRedeemable The amount of xToken needed.
  function maxRedeemableXToken(uint256 newCollateralRatio)
    external
    view
    returns (uint256 maxBaseOut, uint256 maxXTokenRedeemable);

  /// @notice Compute the maximum amount of aToken can be liquidated.
  /// @param newCollateralRatio The target collateral ratio, multipled by 1e18.
  /// @param incentiveRatio The extra incentive ratio, multipled by 1e18.
  /// @return maxBaseOut The maximum amount of base token can liquidate, without incentive.
  /// @return maxaTokenLiquidatable The maximum amount of aToken can be liquidated.
  function maxLiquidatable(uint256 newCollateralRatio, uint256 incentiveRatio)
    external
    view
    returns (uint256 maxBaseOut, uint256 maxaTokenLiquidatable);

  /// @notice Return the exponential moving average of the leverage ratio.
  function leverageRatio() external view returns (uint256);

  /****************************
   * Public Mutated Functions *
   ****************************/

  /// @notice Mint aToken and xToken with some base token.
  /// @param baseIn The amount of base token deposited.
  /// @param recipient The address of receiver.
  /// @param option The mint option, xToken or aToken or both.
  /// @return aTokenOut The amount of aToken minted.
  /// @return xTokenOut The amount of xToken minted.
  function mint(
    uint256 baseIn,
    address recipient,
    MintOption option
  ) external returns (uint256 aTokenOut, uint256 xTokenOut);

  /// @notice Redeem aToken and xToken to base tokne.
  /// @param aTokenIn The amount of aToken to redeem.
  /// @param xTokenIn The amount of xToken to redeem.
  /// @param owner The owner of the aToken or xToken.
  /// @param baseOut The amount of base token redeemed.
  function redeem(
    uint256 aTokenIn,
    uint256 xTokenIn,
    address owner
  ) external returns (uint256 baseOut);
}
