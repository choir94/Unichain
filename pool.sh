#!/bin/bash

# Function to check and install Git
install_git() {
    if ! command -v git &> /dev/null; then
        echo "Installing Git..."
        sudo apt update && sudo apt install -y git || { echo "Failed to install Git"; exit 1; }
    else
        echo "Git is already installed."
    fi
}

# Function to check and install Node.js and npm
install_nodejs_npm() {
    if ! command -v node &> /dev/null; then
        echo "Installing Node.js and npm..."
        curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash - && sudo apt install -y nodejs || { echo "Failed to install Node.js"; exit 1; }
    else
        echo "Node.js is already installed."
    fi
}

# Function to install Foundry
install_foundry() {
    echo "Installing Foundry..."
    curl -L https://foundry.paradigm.xyz | bash || { echo "Failed to install Foundry"; exit 1; }
    source ~/.bashrc  # Load Foundry's environment variables to the current session
}

# Function to set up foundry.toml configuration
setup_foundry_toml() {
    echo "Setting up foundry.toml..."
    mkdir -p ~/foundry  # Create the foundry directory if it doesn't exist
    cat <<EOL > ~/foundry/foundry.toml
[rpc_endpoints]
unichain = "https://sepolia.unichain.org"
EOL
}

# Function to create a .gitignore file
create_gitignore() {
    echo "Creating .gitignore file..."
    cat <<EOL > ~/foundry/.gitignore
# Node.js dependencies
node_modules/
npm-debug.log

# Environment variables
.env

# Build artifacts
build/
out/
target/

# Foundry artifacts
foundry/

# VSCode settings
.vscode/

# Mac system files
.DS_Store

# Logs
*.log
EOL
    echo ".gitignore file created successfully."
}

# Function to install Uniswap dependencies
install_uniswap_dependencies() {
    echo "Installing Uniswap v4 dependencies..."
    cd ~/foundry || { echo "Directory ~/foundry not found"; exit 1; }
    forge install uniswap/v4-core || { echo "Failed to install Uniswap v4-core"; exit 1; }
    forge install uniswap/v4-periphery || { echo "Failed to install Uniswap v4-periphery"; exit 1; }
}

# Function to clone the Uniswap v4 template repository
clone_uniswap_template() {
    echo "Cloning Uniswap v4 template..."
    git clone https://github.com/uniswapfoundation/v4-template.git ~/foundry/uniswap-template || { echo "Failed to clone Uniswap template"; exit 1; }
    cd ~/foundry/uniswap-template || { echo "Directory ~/foundry/uniswap-template not found"; exit 1; }
}

# Function to install necessary dependencies from the cloned template
install_template_dependencies() {
    echo "Installing template dependencies..."
    npm install || { echo "Failed to install template dependencies"; exit 1; }
}

# Function to prompt for the private key
get_private_key() {
    read -sp "Please enter your private key: " PRIVATE_KEY
    echo  # Move to a new line after input
}

# Function to create a Solidity file for the Uniswap pool manager contract
create_contract() {
    echo "Creating UniswapPoolManager.sol contract..."
    cat <<EOL > ~/foundry/UniswapPoolManager.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Import necessary interfaces
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@uniswap/v4-periphery/contracts/interfaces/IPositionManager.sol";
import "@uniswap/v4-core/contracts/interfaces/IAllowanceTransfer.sol";

contract UniswapPoolManager {
    IPositionManager public positionManager;
    address public permit2;

    // Define contract addresses for Unichain
    address constant public WETH9 = 0x4200000000000000000000000000000000000006; // Wrapped Ether
    address constant public Permit2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3; // Permit2 contract
    address constant public PoolManager = 0x05deD3F8a8e84700d68A4D81cd6780c982dB13F9; // PositionManager

    constructor() {
        positionManager = IPositionManager(PoolManager);
        permit2 = Permit2;
    }

    // Function to approve tokens for Permit2 and PositionManager
    function approveTokens(address token, uint256 amount) internal {
        IERC20(token).approve(permit2, amount);
        IAllowanceTransfer(permit2).approve(
            token,
            address(positionManager),
            type(uint160).max,
            type(uint48).max
        );
    }

    // Function to create a pool and add liquidity
    function createPoolAndAddLiquidity(
        address currency0,
        address currency1,
        uint24 lpFee,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity,
        uint256 amount0Max,
        uint256 amount1Max,
        address recipient,
        bytes memory hookData,
        uint160 startingPrice,
        uint256 ethToSend
    ) external payable {
        approveTokens(currency0, type(uint256).max);
        approveTokens(currency1, type(uint256).max);

        // Define pool key
        PoolKey memory pool = PoolKey({
            currency0: currency0 < currency1 ? currency0 : currency1,
            currency1: currency0 < currency1 ? currency1 : currency0,
            fee: lpFee,
            tickSpacing: 100,
            hooks: address(0)
        });

        // Set parameters for multicall
        bytes memory params[2];
        params[0] = abi.encodeWithSelector(
            positionManager.initializePool.selector,
            pool,
            startingPrice
        );

        bytes memory actions = abi.encodePacked(uint8(Actions.MINT_POSITION), uint8(Actions.SETTLE_PAIR));
        bytes memory mintParams[2];
        mintParams[0] = abi.encode(pool, tickLower, tickUpper, liquidity, amount0Max, amount1Max, recipient, hookData);
        mintParams[1] = abi.encode(pool.currency0, pool.currency1);

        uint256 deadline = block.timestamp + 60;  // 1-minute deadline
        params[1] = abi.encodeWithSelector(
            positionManager.modifyLiquidities.selector,
            abi.encode(actions, mintParams),
            deadline
        );

        if (ethToSend > 0) {
            positionManager.multicall{value: ethToSend}(params);
        } else {
            positionManager.multicall(params);
        }
    }

    // Fallback function to accept ETH
    receive() external payable {}
}
EOL
    echo "Contract UniswapPoolManager.sol created successfully."
}

# Function to compile the contract using Foundry
compile_contract() {
    echo "Compiling the contract..."
    cd ~/foundry || { echo "Directory ~/foundry not found"; exit 1; }
    forge build || { echo "Failed to compile the contract"; exit 1; }
}

# Function to explore the deployment on Uniswap
explore_deployment() {
    # Placeholder for transaction hash display
    local tx_hash="0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"  # Example transaction hash
    echo "Your deployment transaction hash: $tx_hash"
    echo "Exploring your deployment on Uniswap: https://sepolia.uniscan.xyz/"
}

# Main script execution
main() {
    install_git
    install_nodejs_npm
    get_private_key
    install_foundry
    setup_foundry_toml
    create_gitignore
    install_uniswap_dependencies
    clone_uniswap_template
    install_template_dependencies
    create_contract
    compile_contract
    explore_deployment  # Explore the deployment
    echo "Installation and setup complete!"
}

# Execute the main function
main
