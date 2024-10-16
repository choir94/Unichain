#!/bin/bash

# Define the foundry path
FOUNDRY_PATH=~/foundry

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
    if ! command -v forge &> /dev/null; then
        echo "Foundry is not installed. Installing now..."
        source <(wget -O - https://raw.githubusercontent.com/choir94/Airdropguide/refs/heads/main/Foundry.sh)
    else
        echo "Foundry is already installed."
    fi
}

# Function to check if Forge is installed
check_forge() {
    if ! command -v forge &> /dev/null; then
        echo "Forge is not installed. Please make sure Foundry is installed correctly."
        exit 1
    fi
}

# Function to set up foundry.toml configuration
setup_foundry_toml() {
    if [ ! -f "$FOUNDRY_PATH/foundry.toml" ]; then  # Check if foundry.toml already exists
        echo "Setting up foundry.toml..."
        mkdir -p "$FOUNDRY_PATH"  # Create the foundry directory if it doesn't exist
        cat <<EOL > "$FOUNDRY_PATH/foundry.toml"
[rpc_endpoints]
unichain = "https://sepolia.unichain.org"
EOL
        echo "foundry.toml setup complete."
    else
        echo "foundry.toml already exists."
    fi
}

# Function to install Uniswap dependencies
install_uniswap_dependencies() {
    echo "Installing Uniswap v4 dependencies..."
    cd "$FOUNDRY_PATH" || { echo "Directory $FOUNDRY_PATH not found"; exit 1; }

    # Check if the directory is a Git repository
    if [ ! -d ".git" ]; then
        echo "Initializing a Git repository..."
        git init || { echo "Failed to initialize Git repository"; exit 1; }
    fi

    # Check if Uniswap v4-core is already installed
    if [ ! -d "lib/v4-core" ]; then
        forge install uniswap/v4-core || { echo "Failed to install Uniswap v4-core"; exit 1; }
    else
        echo "Uniswap v4-core is already installed."
    fi

    # Check if Uniswap v4-periphery is already installed
    if [ ! -d "lib/v4-periphery" ]; then
        forge install uniswap/v4-periphery || { echo "Failed to install Uniswap v4-periphery"; exit 1; }
    else
        echo "Uniswap v4-periphery is already installed."
    fi
}

# Function to install necessary dependencies from the cloned template
install_template_dependencies() {
    echo "Installing template dependencies..."
    if [ -f "$FOUNDRY_PATH/package.json" ]; then  # Check if package.json exists before running npm install
        npm install || { echo "Failed to install template dependencies"; exit 1; }
    else
        echo "No package.json found. Skipping template dependencies installation."
    fi
}

# Function to prompt for the private key
get_private_key() {
    read -sp "Please enter your private key: " PRIVATE_KEY
    echo  # Move to a new line after input
}

# Function to create a Solidity file for the Uniswap pool manager contract
create_contract() {
    if [ ! -f "$FOUNDRY_PATH/UniswapPoolManager.sol" ]; then  # Check if the contract already exists
        echo "Creating UniswapPoolManager.sol contract..."
        cat <<EOL > "$FOUNDRY_PATH/UniswapPoolManager.sol"
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
    else
        echo "Contract UniswapPoolManager.sol already exists."
    fi
}

# Function to compile the contract using Foundry
compile_contract() {
    echo "Compiling the contract..."
    cd "$FOUNDRY_PATH" || { echo "Directory $FOUNDRY_PATH not found"; exit 1; }
    forge build || { echo "Failed to compile the contract"; exit 1; }
}

# Function to explore the deployment on Uniswap
explore_deployment() {
    local tx_hash="0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"  # Placeholder transaction hash
    echo "Your deployment transaction hash: $tx_hash"
    echo "Exploring your deployment on Uniswap: https://sepolia.uniscan.xyz/"
}

# Main script execution
main() {
    install_nodejs_npm
    get_private_key
    install_foundry
    check_forge
    setup_foundry_toml
    install_uniswap_dependencies
    install_template_dependencies
    create_contract
    compile_contract
}

main
