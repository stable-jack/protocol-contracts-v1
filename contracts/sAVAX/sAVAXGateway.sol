// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { IJackMarket } from "../../interfaces/jack/IJackMarket.sol";
import { IYakRouter } from "../../interfaces/jack/IYakRouter.sol";
import { IButtonToken } from "../../interfaces/jack/IButtonToken.sol";
// solhint-disable contract-name-camelcase

contract sAVAXGateway is Ownable {
  using SafeERC20 for IERC20;

  /*************
   * Constants *
   *************/
  /// @dev The address of sAVAX token
  address public immutable sAVAX;
  
  /// @dev The address of wsAVAX token
  address public immutable wsAVAX;

  /// @notice The address of aUSD
  address public immutable aToken;

  /// @notice The address of xAVAX
  address public immutable xToken;

  /// @notice The address of Market.
  address public immutable market;

  /// @notice The address of Yak Router
  address public router;

  /// @notice The address of hexagate
  address public hexagate;
  
  /// @notice Accepted Tokens for swap
  mapping(address => bool) public acceptedTokens;

  bool public pauseContract;
  /************
   * Events *
   ************/
  event MintAToken(address indexed recipient, uint256 mintedAmount, bool isAVAX);
  event MintXToken(address indexed recipient, uint256 mintedAmount, bool isAVAX);
  event MintBothTokens(address indexed recipient, uint256 mintedATokenAmount, uint256 mintedXTokenAmount, bool isAVAX);
  event MintATokenWithSAVAX(address indexed recipient, uint256 mintedAmount);
  event MintXTokenWithSAVAX(address indexed recipient, uint256 mintedAmount);
  event MintBothWithSAVAX(address indexed recipient, uint256 mintedATokenAmount, uint256 mintedXTokenAmount);
  event Refund(address indexed token, address indexed recipient, uint256 amount);
  event Redeem(address indexed recipient, uint256 aTokenIn, uint256 xTokenIn, uint256 baseOut);
  event AddAcceptedToken(address indexed tokenAddress);
  event RemoveAcceptedToken(address indexed tokenAddress);
  event UpdateRouterAddress(address gateway);
  event UpdateHexagateAddress(address hexagate);
  event PauseContract(bool paused);

  constructor(
    address _market,
    address _aToken,
    address _xToken,
    address _sAVAX,
    address _wsAVAX,
    address _router,
    address _hexagate
  ) {
    market = _market;
    aToken = _aToken;
    xToken = _xToken;
    sAVAX = _sAVAX;
    wsAVAX = _wsAVAX;
    router = _router;
    hexagate = _hexagate;

    IERC20(_aToken).safeApprove(_market, uint256(-1));
    IERC20(_xToken).safeApprove(_market, uint256(-1));
    
    IERC20(_wsAVAX).safeApprove(_market, uint256(-1));
    IERC20(_sAVAX).safeApprove(_wsAVAX, uint256(-1));
    pauseContract = false;
  }

  receive() external payable {}

  modifier onlyHexagate() {
    require(msg.sender == hexagate, "Caller is not hexagate");
    _;
  }

  /****************************
   * Public Mutated Functions *
   ****************************/

  // mint aToken with USDC/USDT/AVAX
  function mintaToken(
      address[] memory path,
      uint256[] memory amounts,
      address[] memory adapters,
      uint256 _minaTokenMinted,
      bool isAVAX,
      address _recipient
  ) external payable returns (uint256 _aTokenMinted) {
      require(!pauseContract, "Contract is paused");
      uint256 wsAVAXAmount = _mintHelper(path, amounts, adapters, isAVAX);

      uint256 wsAVAXBalanceBefore = IERC20(wsAVAX).balanceOf(address(this));
      _aTokenMinted = IJackMarket(market).mintaToken(wsAVAXAmount, _recipient, _minaTokenMinted);
      uint256 wsAVAXBalanceAfter = IERC20(wsAVAX).balanceOf(address(this));

      require(wsAVAXBalanceAfter != wsAVAXBalanceBefore, "mint did not work");

      uint256 usedAmount = wsAVAXBalanceBefore - wsAVAXBalanceAfter;
      uint256 remainder = wsAVAXAmount - usedAmount;

      if (remainder > 3 && wsAVAXBalanceAfter > 0) {
        IButtonToken(wsAVAX).burnTo(_recipient, remainder);
      }

      require(_aTokenMinted >= _minaTokenMinted, "Insufficient aToken output");
      emit MintAToken(_recipient, _aTokenMinted, isAVAX);
      return _aTokenMinted;
  }
  // mint xToken with USDC/USDT/AVAX
  function mintxToken(
      address[] memory path,
      uint256[] memory amounts,
      address[] memory adapters,
      uint256 _minxTokenMinted,
      bool isAVAX,
      address _recipient
  ) external payable returns (uint256 _xTokenMinted) {
      require(!pauseContract, "Contract is paused");
      uint256 wsAVAXAmount = _mintHelper(path, amounts, adapters, isAVAX);

      uint256 wsAVAXBalanceBefore = IERC20(wsAVAX).balanceOf(address(this));
      (_xTokenMinted, ) = IJackMarket(market).mintXToken(wsAVAXAmount, _recipient, _minxTokenMinted);
      uint256 wsAVAXBalanceAfter = IERC20(wsAVAX).balanceOf(address(this));

      require(wsAVAXBalanceAfter != wsAVAXBalanceBefore, "mint did not work");

      uint256 usedAmount = wsAVAXBalanceBefore - wsAVAXBalanceAfter;
      uint256 remainder = wsAVAXAmount - usedAmount;

      if (remainder > 3 && wsAVAXBalanceAfter > 0) {
        IButtonToken(wsAVAX).burnTo(_recipient, remainder);
      }

      require(_xTokenMinted >= _minxTokenMinted, "Insufficient xToken output");

      emit MintXToken(_recipient, _xTokenMinted, isAVAX);
      return _xTokenMinted;
  }
  // mint both with USDC/USDT/AVAX
  function mintBoth(
    address[] memory path,
    uint256[] memory amounts,
    address[] memory adapters,
    uint256 _minaTokenMinted,
    uint256 _minxTokenMinted,
    bool isAVAX,
    address _recipient
  ) external payable returns (uint256 _aTokenMinted, uint256 _xTokenMinted) {
    require(!pauseContract, "Contract is paused");
    uint256 wsAVAXAmount = _mintHelper(path, amounts, adapters, isAVAX);
 
    uint256 wsAVAXBalanceBefore = IERC20(wsAVAX).balanceOf(address(this));
    (_xTokenMinted, ) = IJackMarket(market).mintXToken(wsAVAXAmount / 2, _recipient, _minxTokenMinted);
    _aTokenMinted = IJackMarket(market).mintaToken(wsAVAXAmount / 2, _recipient, _minaTokenMinted);

    uint256 wsAVAXBalanceAfter = IERC20(wsAVAX).balanceOf(address(this));
    require(wsAVAXBalanceAfter != wsAVAXBalanceBefore, "mint did not work");

    uint256 usedAmount = wsAVAXBalanceBefore - wsAVAXBalanceAfter;
    uint256 remainder = wsAVAXAmount - usedAmount;

    if (remainder > 3 && wsAVAXBalanceAfter > 0) {
      IButtonToken(wsAVAX).burnTo(_recipient, remainder);
    }
    
    emit MintBothTokens(_recipient, _aTokenMinted, _xTokenMinted, isAVAX);
    return (_aTokenMinted, _xTokenMinted);
  }

  // --------------------------- For sAVAX -------------------------------
    
  // mint aToken with sAVAX
  function mintaTokenWithSAVAX(
      uint256 _minaTokenMinted,
      uint256 amount,
      address _recipient
  ) external returns (uint256 _aTokenMinted) {
    require(!pauseContract, "Contract is paused");
    uint256 depositedAmount = _transferTokenIn(sAVAX, amount);
    uint256 wsAVAXAmount = IButtonToken(wsAVAX).deposit(depositedAmount);

    uint256 wsAVAXBalanceBefore = IERC20(wsAVAX).balanceOf(address(this)); 
    _aTokenMinted = IJackMarket(market).mintaToken(wsAVAXAmount, _recipient, _minaTokenMinted);

    uint256 wsAVAXBalanceAfter = IERC20(wsAVAX).balanceOf(address(this));
    require(wsAVAXBalanceAfter != wsAVAXBalanceBefore, "mint did not work");

    uint256 usedAmount = wsAVAXBalanceBefore - wsAVAXBalanceAfter;
    uint256 remainder = wsAVAXAmount - usedAmount;

    if (remainder > 3 && wsAVAXBalanceAfter > 0) {
      IButtonToken(wsAVAX).burnTo(_recipient, remainder);
    }

    require(_aTokenMinted >= _minaTokenMinted, "Insufficient aToken output");
    
    emit MintATokenWithSAVAX(_recipient, _aTokenMinted);
    return _aTokenMinted;
  }

  // mint xToken with sAVAX
  function mintxTokenWithSAVAX(
      uint256 _minxTokenMinted,
      uint256 amount,
      address _recipient
  ) external returns (uint256 _xTokenMinted) {
    require(!pauseContract, "Contract is paused");
    uint256 depositedAmount = _transferTokenIn(sAVAX, amount);
    uint256 wsAVAXAmount = IButtonToken(wsAVAX).deposit(depositedAmount);

    uint256 wsAVAXBalanceBefore = IERC20(wsAVAX).balanceOf(address(this));
    (_xTokenMinted, ) = IJackMarket(market).mintXToken(wsAVAXAmount, _recipient, _minxTokenMinted);

    uint256 wsAVAXBalanceAfter = IERC20(wsAVAX).balanceOf(address(this));
    require(wsAVAXBalanceAfter != wsAVAXBalanceBefore, "mint did not work");

    uint256 usedAmount = wsAVAXBalanceBefore - wsAVAXBalanceAfter;
    uint256 remainder = wsAVAXAmount - usedAmount;

    if (remainder > 3 && wsAVAXBalanceAfter > 0) {
      IButtonToken(wsAVAX).burnTo(_recipient, remainder);
    }
    require(_xTokenMinted >= _minxTokenMinted, "Insufficient xToken output");

    emit MintXTokenWithSAVAX(_recipient, _xTokenMinted);
    return _xTokenMinted;
  }

  // mint both with sAVAX
  function mintBothWithSAVAX(
    uint256 _minaTokenMinted,
    uint256 _minxTokenMinted,
    uint256 amount,
    address _recipient
  ) external returns (uint256 _aTokenMinted, uint256 _xTokenMinted) {
    require(!pauseContract, "Contract is paused");
    uint256 depositedAmount = _transferTokenIn(sAVAX, amount);
    uint256 wsAVAXAmount = IButtonToken(wsAVAX).deposit(depositedAmount);

    uint256 wsAVAXBalanceBefore = IERC20(wsAVAX).balanceOf(address(this));
    (_xTokenMinted, ) = IJackMarket(market).mintXToken(wsAVAXAmount / 2, _recipient, _minxTokenMinted);
    _aTokenMinted = IJackMarket(market).mintaToken(wsAVAXAmount / 2, _recipient, _minaTokenMinted);
     
    uint256 wsAVAXBalanceAfter = IERC20(wsAVAX).balanceOf(address(this));
    require(wsAVAXBalanceAfter != wsAVAXBalanceBefore, "mint did not work");

    uint256 usedAmount = wsAVAXBalanceBefore - wsAVAXBalanceAfter;
    uint256 remainder = wsAVAXAmount - usedAmount;

    if (remainder > 3 && wsAVAXBalanceAfter > 0) {
      IButtonToken(wsAVAX).burnTo(_recipient, remainder);
    }

    emit MintBothWithSAVAX(_recipient, _aTokenMinted, _xTokenMinted);
    return (_aTokenMinted, _xTokenMinted);
  }

  // redeem to sAVAX
  function redeem(uint256 _aTokenIn, uint256 _xTokenIn, uint256 _minBaseToken) external returns (uint256 _baseOut) {
    require(!pauseContract, "Contract is paused");
    
    if (_xTokenIn == 0) {
      _aTokenIn = _transferTokenIn(aToken, _aTokenIn);
    } else {
      _xTokenIn = _transferTokenIn(xToken, _xTokenIn);
      _aTokenIn = 0;
    }

    (_baseOut, ) = IJackMarket(market).redeem(_aTokenIn, _xTokenIn, address(this), _minBaseToken);
    IButtonToken(wsAVAX).burnTo(msg.sender, _baseOut);

    emit Redeem(msg.sender, _aTokenIn, _xTokenIn, _baseOut);
  }

  // Add supported tokens
  function addAcceptedToken(address tokenAddress) external onlyOwner {
      require(tokenAddress != address(0), "Invalid address");
      IERC20(tokenAddress).safeApprove(router, uint256(-1));
      acceptedTokens[tokenAddress] = true;

      emit AddAcceptedToken(tokenAddress);
  }

  function removeAcceptedToken(address tokenAddress) external onlyOwner {
      require(tokenAddress != address(0), "Invalid Address");
      IERC20(tokenAddress).safeApprove(router, 0);
      acceptedTokens[tokenAddress] = false;

      emit RemoveAcceptedToken(tokenAddress);
  }

  function updateRouterAddress(address _router) external onlyOwner {
    require(_router != address(0), "Invalid Address");
    router = _router;

    emit UpdateRouterAddress(_router);
  }

  function updateHexagateAddress(address _hexagate) external onlyOwner {
    require(_hexagate != address(0), "Invalid Address");
    hexagate = _hexagate;

    emit UpdateHexagateAddress(_hexagate);
  }

  function setPauseContract() external onlyHexagate {
    pauseContract = true;
    emit PauseContract(true);
  }

  function setChangePauseStatus(bool _pause) external onlyOwner {
    pauseContract = _pause;
    emit PauseContract(_pause);
  }

  // to collect dust/recover if broken
  function refund(address _token, address _recipient, uint256 _amount) external onlyOwner{
    IERC20(_token).safeTransfer(_recipient, _amount);
  }

  /**********************
   * Internal Functions *
   **********************/
  function _mintHelper(
    address[] memory path,
    uint256[] memory amounts,
    address[] memory adapters,
    bool isAVAX
  ) internal returns (uint256 wsAVAXAmount) {
    require(path.length > 0, "Invalid path length");
    require(path[0] != address(0), "Invalid start token address");
    require(acceptedTokens[path[0]] == true, "Token Not Supported");
    require(path[path.length - 1] == sAVAX, "End token must be sAVAX");
    require(amounts[0] > 0, "Input amount must be greater than 0");

    if (isAVAX) {
        require(msg.value == amounts[0], "Incorrect AVAX amount");
        _transferTokenIn(address(0), amounts[0]);
    } else {
        require(msg.value == 0, "No AVAX should be sent");
        _transferTokenIn(path[0], amounts[0]);
    }
        
    uint256 adjustedAmountOut = (amounts[amounts.length - 1] * 998) / 1000;

    // Perform the token swap directly using the provided swap data
    IYakRouter.Trade memory trade = IYakRouter.Trade({
      amountIn: amounts[0],
      amountOut: adjustedAmountOut,  // 99.9 % for better trades
      path: path,
      adapters: adapters
    });

    uint256 initialBalance = IERC20(sAVAX).balanceOf(address(this));

    if (isAVAX) {
        IYakRouter(router).swapNoSplitFromAVAX{value: amounts[0]}(trade, address(this), 0);
    } else {
        IYakRouter(router).swapNoSplit(trade, address(this), 0);
    }

    uint256 finalBalance = IERC20(sAVAX).balanceOf(address(this));
    require(finalBalance > initialBalance, "Swap did not work, no new sAVAX");

    uint256 swappedAmount = finalBalance - initialBalance;

    wsAVAXAmount = IButtonToken(wsAVAX).deposit(swappedAmount);
    return wsAVAXAmount;
  }

  function _transferTokenIn(address _token, uint256 _amount) internal returns (uint256) {
    if (_token == address(0)) {
      require(msg.value == _amount, "msg.value mismatch");
      return _amount;
    }
    if (_amount == uint256(-1)) {
      _amount = IERC20(_token).balanceOf(msg.sender);
    }
    if (_amount > 0) {
      IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
    }
    return _amount;
  }
}