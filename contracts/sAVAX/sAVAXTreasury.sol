// SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;

import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";

import { IJackRebalancePool } from "../../interfaces/jack/IJackRebalancePool.sol";
import { HarvestableTreasury } from "../HarvestableTreasury.sol";

// solhint-disable const-name-snakecase
// solhint-disable contract-name-camelcase

contract sAVAXTreasury is HarvestableTreasury {
  using SafeERC20Upgradeable for IERC20Upgradeable;

  /***************
   * Constructor *
   ***************/

  constructor(uint256 _initialMintRatio) HarvestableTreasury(_initialMintRatio) {}

  /**********************
   * Internal Functions *
   **********************/

  /// @inheritdoc HarvestableTreasury
  function _distributeRebalancePoolRewards(address _token, uint256 _amount) internal override {
    require(_token == baseToken, "base token not sAVAX"); 
    address _rebalancePool = rebalancePool;
    
    _approve(_token, _rebalancePool, _amount);
    
    IJackRebalancePool(_rebalancePool).depositReward(_token, _amount); // deposit rewards to rebalance pool
  }
}