// SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;

import { SafeMathUpgradeable } from "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import { IJackSyntheticToken } from "../interfaces/jack/IJackSyntheticToken.sol";
import { IJackTreasury } from "../interfaces/jack/IJackTreasury.sol";

contract SyntheticToken is ERC20Upgradeable, IJackSyntheticToken {
  using SafeMathUpgradeable for uint256;

  /*************
   * Constants *
   *************/

  /// @dev The precision used to compute nav.
  uint256 private constant PRECISION = 1e18;

  /*************
   * Variables *
   *************/

  /// @notice The address of Treasury contract.
  address public treasury;


  /*************
   * Modifiers *
   *************/

  modifier onlyTreasury() {
    require(msg.sender == treasury, "Only treasury");
    _;
  }

  /***************
   * Constructor *
   ***************/

  function initialize(
    address _treasury,
    string memory _name,
    string memory _symbol
  ) external initializer {
    ERC20Upgradeable.__ERC20_init(_name, _symbol);

    treasury = _treasury;
  }

  /****************************
   * Public View Functions *
   ****************************/

  /// @inheritdoc IJackSyntheticToken
  function nav() external view override returns (uint256) {
    uint256 _aSupply = totalSupply();
    if (_aSupply > 0 && IJackTreasury(treasury).isUnderCollateral()) {
      // under collateral
      uint256 baseNav = IJackTreasury(treasury).currentBaseTokenPrice();
      uint256 baseSupply = IJackTreasury(treasury).totalBaseToken();
      return (baseNav.mul(baseSupply)).div(_aSupply);
    } else {
      return PRECISION;
    }
  }

  /****************************
   * Public Mutated Functions *
   ****************************/

  /// @inheritdoc IJackSyntheticToken
  function mint(address _to, uint256 _amount) external override onlyTreasury {
    _mint(_to, _amount);
  }

  /// @inheritdoc IJackSyntheticToken
  function burn(address _from, uint256 _amount) external override onlyTreasury {
    _burn(_from, _amount);
  }
}
