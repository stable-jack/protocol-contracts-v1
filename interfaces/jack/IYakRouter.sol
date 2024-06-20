// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;

interface IYakRouter {
    struct Trade {
        uint amountIn;
        uint amountOut;
        address[] path;
        address[] adapters;
    }

    function findBestPathWithGas(
        uint256 _amountIn, 
        address _tokenIn, 
        address _tokenOut, 
        uint _maxSteps,
        uint _gasPrice
    ) external view returns (
        uint[] memory amounts,
        address[] memory adapters,
        address[] memory path,
        uint gasEstimate
    );

    function swapNoSplit(
        Trade calldata _trade,
        address _to,
        uint _fee
    ) external;

    function swapNoSplitFromAVAX(
        Trade calldata _trade,
        address _to,
        uint256 _fee
    ) external payable;
}