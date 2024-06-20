// SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;

interface IJackPriceOracle {
  /// @notice Return the oracle price with 18 decimal places.
  /// @return isValid Whether the oracle is valid.
  /// @return safePrice The safe oracle price when the oracle is valid.
  function getPrice()
    external
    view
    returns (
      bool isValid,
      uint256 safePrice
    );
}
