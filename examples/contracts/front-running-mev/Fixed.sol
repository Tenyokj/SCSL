// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.28;

/// @title SafeFrontRunToken
/// @author Solidity Security Lab
/// @notice Minimal ERC20-like token used by the fixed front-running module.
contract SafeFrontRunToken {
    string public constant name = "Safe FrontRun Token";
    string public constant symbol = "SFR";
    uint8 public constant decimals = 18;

    uint256 public totalSupply;

    mapping(address account => uint256 amount) public balanceOf;
    mapping(address owner => mapping(address spender => uint256 amount)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function mint(address to, uint256 amount) external {
        require(to != address(0), "Mint to zero");
        require(amount > 0, "Mint amount zero");

        totalSupply += amount;
        balanceOf[to] += amount;

        emit Transfer(address(0), to, amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowedAmount = allowance[from][msg.sender];
        require(allowedAmount >= amount, "Allowance exceeded");

        allowance[from][msg.sender] = allowedAmount - amount;
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(to != address(0), "Transfer to zero");
        require(balanceOf[from] >= amount, "Insufficient balance");

        balanceOf[from] -= amount;
        balanceOf[to] += amount;

        emit Transfer(from, to, amount);
    }
}

/// @title SlippageProtectedETHToTokenAMM
/// @author Solidity Security Lab
/// @notice Safer AMM that requires the user to specify minimum output and deadline.
contract SlippageProtectedETHToTokenAMM {
    SafeFrontRunToken public immutable token;

    event LiquidityAdded(address indexed provider, uint256 ethAmount, uint256 tokenAmount);
    event EthToTokenSwap(address indexed buyer, uint256 ethIn, uint256 tokensOut);

    constructor(address tokenAddress) {
        require(tokenAddress != address(0), "Token cannot be zero");
        token = SafeFrontRunToken(tokenAddress);
    }

    function addLiquidity(uint256 tokenAmount) external payable {
        require(msg.value > 0, "ETH amount zero");
        require(tokenAmount > 0, "Token amount zero");

        require(token.transferFrom(msg.sender, address(this), tokenAmount), "Token transfer failed");
        emit LiquidityAdded(msg.sender, msg.value, tokenAmount);
    }

    function getTokenAmountOut(uint256 ethIn) public view returns (uint256) {
        require(ethIn > 0, "ETH amount zero");

        uint256 ethReserveBefore = address(this).balance;
        uint256 tokenReserveAmount = token.balanceOf(address(this));
        require(ethReserveBefore > 0, "Insufficient ETH reserve");
        require(tokenReserveAmount > 0, "Insufficient token reserve");

        return (ethIn * tokenReserveAmount) / (ethReserveBefore + ethIn);
    }

    /// @notice Swaps ETH for tokens only if execution still meets user-defined slippage and timing bounds.
    function swapExactETHForTokens(uint256 minTokensOut, uint256 deadline)
        external
        payable
        returns (uint256 tokensOut)
    {
        require(msg.value > 0, "ETH amount zero");
        require(block.timestamp <= deadline, "Swap expired");

        uint256 ethReserveBefore = address(this).balance - msg.value;
        uint256 tokenReserveAmount = token.balanceOf(address(this));
        tokensOut = (msg.value * tokenReserveAmount) / (ethReserveBefore + msg.value);
        require(tokensOut >= minTokensOut, "Slippage exceeded");
        require(token.transfer(msg.sender, tokensOut), "Token transfer failed");

        emit EthToTokenSwap(msg.sender, msg.value, tokensOut);
    }

    function tokenReserve() external view returns (uint256) {
        return token.balanceOf(address(this));
    }

    function ethReserve() external view returns (uint256) {
        return address(this).balance;
    }
}
