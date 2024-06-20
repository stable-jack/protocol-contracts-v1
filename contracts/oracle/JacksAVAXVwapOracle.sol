// SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;

import { Math } from "@openzeppelin/contracts/math/Math.sol";
import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { IJackPriceOracle } from "../../interfaces/jack/IJackPriceOracle.sol";
import { ITwapOracle } from "../../price-oracle/interfaces/ITwapOracle.sol";
import { IStakedAvax } from "../../interfaces/IStakedAVAX.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import "../../price-oracle/interfaces/AggregatorV3Interface.sol";
import "../../price-oracle/ChainlinkPriceOracle.sol";

// solhint-disable var-name-mixedcase

contract JacksAVAXVwapOracle is IJackPriceOracle, Ownable {
  using SafeMath for uint256;

  /*************
   * Constants *
   *************/

  /// @dev The precision used in calculation.
  uint256 private constant PRECISION = 1e18;
  uint256 public constant PRICE_DECIMALS = 18;

  /// @notice The address of chainlink sAVAX/USD twap oracle.
  address public immutable chainlinkVwapSavax;
  address public immutable chainlinkVwapAvax;

  bool public hexagateStatus;
  address public hexagateAddress;

  // The address of the BENQI Staked AVAX contract
  IStakedAvax public immutable sAVAX;

  // Custom Chainlink Price Oracle
  address public immutable priceOracle;

  /***********
   * Structs *
   ***********/

  struct CachedPrice {
    uint256 sAVAX_USDPrice;
    uint256 AVAX_USDPrice;
  }
  
  /***********************
   * Modifier Functions *
  ***********************/

  modifier onlyHexagate() {
      require(hexagateAddress == msg.sender, "Only Hexagate");
      _;
  }

  /***************
   * Constructor *
   ***************/

  constructor(
    address _chainlinkVwapSavax,
    address _chainlinkVwapAvax,
    address _priceOracle,
    IStakedAvax _sAVAX,
    address _hexagate
  ) { 
    chainlinkVwapSavax = _chainlinkVwapSavax;
    chainlinkVwapAvax = _chainlinkVwapAvax;
    priceOracle = _priceOracle;
    sAVAX = _sAVAX;
    hexagateAddress = _hexagate;
    hexagateStatus = true;
  }

  /*************************
   * Public View Functions *
   *************************/

  /// @inheritdoc IJackPriceOracle
  function getPrice()
    external
    view
    override
    returns (
      bool _isValid,
      uint256 _safePrice
    )
  {
    CachedPrice memory _cached = _fetchPrice();
    _isValid = _isPriceValid(_cached);
    _safePrice = _cached.AVAX_USDPrice;
  }

  function setHexagateStatus(bool _status) external onlyOwner {
      hexagateStatus = _status;
  }

  function disableHexagate() external onlyHexagate {
      hexagateStatus = false;
  }

  function setHexagateAddress(address _newHexagate) external onlyOwner {
      hexagateAddress = _newHexagate;
  }

  /**********************
   * Internal Functions *
   **********************/

  function _fetchPrice() internal view returns (CachedPrice memory _cached) {
    _cached.sAVAX_USDPrice = IPriceOracle(priceOracle).price(chainlinkVwapSavax);
    _cached.AVAX_USDPrice = IPriceOracle(priceOracle).price(chainlinkVwapAvax); 
  }

  function _isPriceValid(CachedPrice memory _cached) internal view returns (bool) {
    // Set the price difference threshold to 2% (0.02)
    uint256 percentageThreshold = 2 * 10**16; // 0.02 as 18-decimal fixed point
    
    // Compute sAVAX pooled AVAX equivalent for the given price decimals
    uint256 pooledAvaxPrice = (sAVAX.getPooledAvaxByShares(10**PRICE_DECIMALS));
    
    // Compute sAVAX/AVAX price ratio using cached USD prices
    uint256 avaxRatio = _cached.sAVAX_USDPrice * 10**PRICE_DECIMALS / _cached.AVAX_USDPrice;
    
    // Calculate absolute price difference as a percentage
    uint256 priceDiff = pooledAvaxPrice > avaxRatio
        ? ((pooledAvaxPrice - avaxRatio) * 10**18 / pooledAvaxPrice)
        : ((avaxRatio - pooledAvaxPrice) * 10**18 / avaxRatio);
    
    // If the price difference is greater than the threshold, it's not valid
    if (priceDiff > percentageThreshold) {
        return false;
    }

    // If hexagate detects malicious activity, very high volatility, wrong oracles
    if(!hexagateStatus) {
      return false;
    }
    
    // Otherwise, it's within the acceptable range
    return true;
  }
}
