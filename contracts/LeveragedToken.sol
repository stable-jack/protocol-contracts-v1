// SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;

import { SafeMathUpgradeable } from "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import { IJackSyntheticToken } from "../interfaces/jack/IJackSyntheticToken.sol";
import { IJackLeveragedToken } from "../interfaces/jack/IJackLeveragedToken.sol";
import { IJackTreasury } from "../interfaces/jack/IJackTreasury.sol";

contract LeveragedToken is ERC20Upgradeable, IJackLeveragedToken {
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

  /// @notice The address of corresponding SyntheticToken.
  address public aToken;

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
    address _aToken,
    string memory _name,
    string memory _symbol
  ) external initializer {
    ERC20Upgradeable.__ERC20_init(_name, _symbol);

    treasury = _treasury;
    aToken = _aToken;
  }

  /*************************
   * Public View Functions *
   *************************/

  /// @inheritdoc IJackLeveragedToken
  function nav() external view override returns (uint256) {
    uint256 _xSupply = totalSupply();
    if (IJackTreasury(treasury).isUnderCollateral()) {
      return 0;
    } else if (_xSupply == 0) {
      return PRECISION;
    } else {
      uint256 baseNav = IJackTreasury(treasury).currentBaseTokenPrice();
      uint256 baseSupply = IJackTreasury(treasury).totalBaseToken();
      uint256 aSupply = ERC20Upgradeable(aToken).totalSupply();
      return baseNav.mul(baseSupply).sub(aSupply.mul(PRECISION)).div(_xSupply);
    }
  }

  /****************************
   * Public Mutated Functions *
   ****************************/

  /// @inheritdoc IJackLeveragedToken
  function mint(address _to, uint256 _amount) external override onlyTreasury {
    _mint(_to, _amount);
  }

  /// @inheritdoc IJackLeveragedToken
  function burn(address _from, uint256 _amount) external override onlyTreasury {
    _burn(_from, _amount);
  }
}
