// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.15;

import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { IUniswapV2Router02 as IUniswapV2Router } from "../interfaces/IUniswapV2Router02.sol";
import { IUniswapV3Router } from "../interfaces/IUniswapV3Router.sol";

contract SwapRouter {
    using SafeTransferLib for ERC20;

    enum Exchanges {
        UNIV2,
        UNIV3
    }
    /** @notice Planned additions
        BALANCERV2,
        CURVE,
        ONEINCH
    */
    mapping(Exchanges => bytes4) public idToSelector;

    // ========================================== CONSTRUCTOR ==========================================

    /**
     * @notice Uniswap V2 swap router contract. Used for swapping if pool fees are not specified.
     */
    IUniswapV2Router public immutable uniswapV2Router; // 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D

    /**
     * @notice Uniswap V3 swap router contract. Used for swapping if pool fees are specified.
     */
    IUniswapV3Router public immutable uniswapV3Router; // 0xE592427A0AEce92De3Edee1F18E0157C05861564

    /**
     *
     */
    constructor(IUniswapV2Router _uniswapV2Router, IUniswapV3Router _uniswapV3Router) {
        //set up all exchanges
        uniswapV2Router = _uniswapV2Router;
        uniswapV3Router = _uniswapV3Router;

        //set up mapping between ids and selectors
        idToSelector[Exchanges.UNIV2] = SwapRouter(this).swapWithUniV2.selector;
        idToSelector[Exchanges.UNIV3] = SwapRouter(this).swapWithUniV3.selector;
    }

    // ======================================= SWAP OPERATIONS =======================================

    function swapExactAssets(Exchanges id, bytes memory swapData) external returns (uint256 swapOutAmount) {
        (bool success, bytes memory result) = address(this).delegatecall(
            abi.encodeWithSelector(idToSelector[id], swapData)
        );

        if (!success) {
            // If there is return data, the call reverted with a reason or a custom error.
            if (result.length > 0) {
                assembly {
                    let returndata_size := mload(result)
                    revert(add(32, result), returndata_size)
                }
            } else {
                revert("Execution reverted.");
            }
        }

        swapOutAmount = abi.decode(result, (uint256));
    }

    function swapForExactAssets(Exchanges id, bytes memory swapData) external returns (uint256 swapInAmount) {}

    function swapWithUniV2(bytes memory swapData) public returns (uint256 swapOutAmount) {
        (address[] memory path, uint256 assets, uint256 assetsOutMin, address recipient) = abi.decode(
            swapData,
            (address[], uint256, uint256, address)
        );

        ERC20 assetIn = ERC20(path[0]);
        assetIn.safeTransferFrom(msg.sender, address(this), assets);

        // Approve assets to be swapped through the router.
        assetIn.safeApprove(address(uniswapV2Router), assets);

        // Execute the swap.
        uint256[] memory amountsOut = uniswapV2Router.swapExactTokensForTokens(
            assets,
            assetsOutMin,
            path,
            recipient,
            block.timestamp + 60
        );

        swapOutAmount = amountsOut[amountsOut.length - 1];
    }

    function swapWithUniV3(bytes memory swapData) public returns (uint256 swapOutAmount) {
        (address[] memory path, uint24[] memory poolFees, uint256 assets, uint256 assetsOutMin, address recipient) = abi
            .decode(swapData, (address[], uint24[], uint256, uint256, address));

        ERC20 assetIn = ERC20(path[0]);
        assetIn.safeTransferFrom(msg.sender, address(this), assets);

        // Approve assets to be swapped through the router.
        assetIn.safeApprove(address(uniswapV3Router), assets);

        // Encode swap parameters.
        bytes memory encodePackedPath = abi.encodePacked(address(assetIn));
        for (uint256 i = 1; i < path.length; i++)
            encodePackedPath = abi.encodePacked(encodePackedPath, poolFees[i - 1], path[i]);

        // Execute the swap.
        swapOutAmount = uniswapV3Router.exactInput(
            IUniswapV3Router.ExactInputParams({
                path: encodePackedPath,
                recipient: recipient,
                deadline: block.timestamp + 60,
                amountIn: assets,
                amountOutMinimum: assetsOutMin
            })
        );
    }
}
