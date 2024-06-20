// SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;

interface IJackMarket {
  /**********
   * Events *
   **********/

  /// @notice Emitted when aToken or xToken is minted.
  /// @param owner The address of base token owner.
  /// @param recipient The address of receiver for aToken or xToken.
  /// @param baseTokenIn The amount of base token deposited.
  /// @param aTokenOut The amount of aToken minted.
  /// @param xTokenOut The amount of xToken minted.
  /// @param mintFee The amount of mint fee charged.
  event Mint(
    address indexed owner,
    address indexed recipient,
    uint256 baseTokenIn,
    uint256 aTokenOut,
    uint256 xTokenOut,
    uint256 mintFee
  );

  /// @notice Emitted when someone redeem base token with aToken or xToken.
  /// @param owner The address of aToken and xToken owner.
  /// @param recipient The address of receiver for base token.
  /// @param aTokenBurned The amount of aToken burned.
  /// @param xTokenBurned The amount of xToken burned.
  /// @param baseTokenOut The amount of base token redeemed.
  /// @param redeemFee The amount of redeem fee charged.
  event Redeem(
    address indexed owner,
    address indexed recipient,
    uint256 aTokenBurned,
    uint256 xTokenBurned,
    uint256 baseTokenOut,
    uint256 redeemFee
  );

  /// @notice Emitted when someone add more base token.
  /// @param owner The address of base token owner.
  /// @param recipient The address of receiver for aToken or xToken.
  /// @param baseTokenIn The amount of base token deposited.
  /// @param xTokenMinted The amount of xToken minted.
  event AddCollateral(address indexed owner, address indexed recipient, uint256 baseTokenIn, uint256 xTokenMinted);

  /// @notice Emitted when someone liquidate with aToken.
  /// @param owner The address of aToken and xToken owner.
  /// @param recipient The address of receiver for base token.
  /// @param aTokenBurned The amount of aToken burned.
  /// @param baseTokenOut The amount of base token redeemed.
  event UserLiquidate(address indexed owner, address indexed recipient, uint256 aTokenBurned, uint256 baseTokenOut);

  /// @notice Emitted when self liquidate with aToken.
  /// @param caller The address of caller.
  /// @param baseSwapAmt The amount of base token used to swap.
  /// @param baseTokenOut The amount of base token redeemed.
  /// @param aTokenBurned The amount of aToken liquidated.
  event SelfLiquidate(address indexed caller, uint256 baseSwapAmt, uint256 baseTokenOut, uint256 aTokenBurned);

  /// @notice Emitted when the gateway contract is changed.
  /// @param gateway The address of new gateway.
  event UpdateGateway(address gateway);
  
  /****************************
   * Public Mutated Functions *
   ****************************/

  /// @notice Mint both aToken and xToken with some base token.
  /// @param baseIn The amount of base token supplied.
  /// @param recipient The address of receiver for aToken and xToken.
  /// @param minaTokenMinted The minimum amount of aToken should be received.
  /// @param minXTokenMinted The minimum amount of xToken should be received.
  /// @return aTokenMinted The amount of aToken should be received.
  /// @return xTokenMinted The amount of xToken should be received.
  function mint(
    uint256 baseIn,
    address recipient,
    uint256 minaTokenMinted,
    uint256 minXTokenMinted
  ) external returns (uint256 aTokenMinted, uint256 xTokenMinted);

  /// @notice Mint some aToken with some base token.
  /// @param baseIn The amount of base token supplied, use `uint256(-1)` to supply all base token.
  /// @param recipient The address of receiver for aToken.
  /// @param minaTokenMinted The minimum amount of aToken should be received.
  /// @return aTokenMinted The amount of aToken should be received.
  function mintaToken(
    uint256 baseIn,
    address recipient,
    uint256 minaTokenMinted
  ) external returns (uint256 aTokenMinted);

  /// @notice Mint some xToken with some base token.
  /// @param baseIn The amount of base token supplied, use `uint256(-1)` to supply all base token.
  /// @param recipient The address of receiver for xToken.
  /// @param minXTokenMinted The minimum amount of xToken should be received.
  /// @return xTokenMinted The amount of xToken should be received.
  /// @return bonus The amount of base token as bonus.
  function mintXToken(
    uint256 baseIn,
    address recipient,
    uint256 minXTokenMinted
  ) external returns (uint256 xTokenMinted, uint256 bonus);

  /// @notice Redeem base token with aToken and xToken.
  /// @param aTokenIn the amount of aToken to redeem, use `uint256(-1)` to redeem all aToken.
  /// @param xTokenIn the amount of xToken to redeem, use `uint256(-1)` to redeem all xToken.
  /// @param recipient The address of receiver for base token.
  /// @param minBaseOut The minimum amount of base token should be received.
  /// @return baseOut The amount of base token should be received.
  /// @return bonus The amount of base token as bonus.
  function redeem(
    uint256 aTokenIn,
    uint256 xTokenIn,
    address recipient,
    uint256 minBaseOut
  ) external returns (uint256 baseOut, uint256 bonus);
}
