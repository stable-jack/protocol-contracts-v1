// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.7.6;
interface IButtonToken {
    function initialize(
        address underlying_,
        string memory name_,
        string memory symbol_,
        address oracle_
    ) external;

    function mint(uint256 amount) external returns (uint256);

    function mintFor(address to, uint256 amount) external returns (uint256);

    function burn(uint256 amount) external returns (uint256);

    function burnTo(address to, uint256 amount) external returns (uint256);
    
    /// @notice Transfers underlying tokens from {msg.sender} to the contract and
    ///         mints wrapper tokens to the specified beneficiary.
    /// @param uAmount The amount of underlying tokens to deposit.
    /// @return The amount of wrapper tokens mint.
    function deposit(uint256 uAmount) external returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);   
}