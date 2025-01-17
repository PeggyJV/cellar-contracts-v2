// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { Cellar, ERC4626, ERC20, SafeTransferLib } from "src/base/Cellar.sol";
import { CellarInitializableV2_2 } from "src/base/CellarInitializableV2_2.sol";
import { Registry, PriceRouter } from "src/base/Cellar.sol";
import { AaveV3ATokenAdaptor } from "src/modules/adaptors/Aave/V3/AaveV3ATokenAdaptor.sol";
import { AaveATokenAdaptor } from "src/modules/adaptors/Aave/AaveATokenAdaptor.sol";
import { AaveDebtTokenAdaptor } from "src/modules/adaptors/Aave/AaveDebtTokenAdaptor.sol";
import { AaveV2EnableAssetAsCollateralAdaptor } from "src/modules/adaptors/Aave/AaveV2EnableAssetAsCollateralAdaptor.sol";
import { SwapWithUniswapAdaptor } from "src/modules/adaptors/Uniswap/SwapWithUniswapAdaptor.sol";
import { IPool } from "src/interfaces/external/IPool.sol";
import { CellarFactory } from "src/CellarFactory.sol";
import { Registry, PriceRouter } from "src/base/Cellar.sol";
import { SwapRouter, IUniswapV2Router, IUniswapV3Router } from "src/modules/swap-router/SwapRouter.sol";
import { IEuler, IEulerMarkets, IEulerExec, IEulerEToken, IEulerDToken } from "src/interfaces/external/IEuler.sol";

import { FeesAndReserves } from "src/modules/FeesAndReserves.sol";
import { UniswapV3PositionTracker } from "src/modules/adaptors/Uniswap/UniswapV3PositionTracker.sol";

// Import adaptors.
import { FeesAndReservesAdaptor } from "src/modules/adaptors/FeesAndReserves/FeesAndReservesAdaptor.sol";
import { CellarAdaptor } from "src/modules/adaptors/Sommelier/CellarAdaptor.sol";
import { AaveATokenAdaptor } from "src/modules/adaptors/Aave/AaveATokenAdaptor.sol";
import { AaveDebtTokenAdaptor } from "src/modules/adaptors/Aave/AaveDebtTokenAdaptor.sol";
import { AaveV3ATokenAdaptor } from "src/modules/adaptors/Aave/V3/AaveV3ATokenAdaptor.sol";
import { AaveV3DebtTokenAdaptor } from "src/modules/adaptors/Aave/V3/AaveV3DebtTokenAdaptor.sol";
import { UniswapV3Adaptor } from "src/modules/adaptors/Uniswap/UniswapV3Adaptor.sol";
import { ZeroXAdaptor } from "src/modules/adaptors/ZeroX/ZeroXAdaptor.sol";
import { OneInchAdaptor } from "src/modules/adaptors/OneInch/OneInchAdaptor.sol";
import { BaseAdaptor } from "src/modules/adaptors/BaseAdaptor.sol";
import { ERC20Adaptor } from "src/modules/adaptors/ERC20Adaptor.sol";

// Import adaptors.
import { INonfungiblePositionManager } from "@uniswapV3P/interfaces/INonfungiblePositionManager.sol";

// Import Chainlink helpers.
import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";

import { Test, console } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

contract RealYeildGovTest is Test {
    using Math for uint256;

    ERC20 public WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 public dV2WETH = ERC20(0xF63B34710400CAd3e044cFfDcAb00a0f32E33eCf);
    ERC20 public dV3WETH = ERC20(0xeA51d7853EEFb32b6ee06b1C12E6dcCA88Be0fFE);

    ERC20 public LINK = ERC20(0x514910771AF9Ca656af840dff83E8264EcF986CA);
    ERC20 public aV3LINK = ERC20(0x5E8C8A7243651DB1384C0dDfDbE39761E8e7E51a);
    ERC20 public aV2LINK = ERC20(0xa06bC25B5805d5F8d82847D191Cb4Af5A3e873E0);

    address private gravityBridge = 0x69592e6f9d21989a043646fE8225da2600e5A0f7;
    CellarInitializableV2_2 private rye = CellarInitializableV2_2(0xb5b29320d2Dde5BA5BAFA1EbcD270052070483ec);
    address private devOwner = 0x552acA1343A6383aF32ce1B7c7B1b47959F7ad90;
    address private strategist = 0xeeF7b7205CAF2Bcd71437D9acDE3874C3388c138;

    // Define Adaptors.
    CellarAdaptor private cellarAdaptor;

    AaveV3ATokenAdaptor private aaveV3ATokenAdaptor = AaveV3ATokenAdaptor(0x3184CBEa47eD519FA04A23c4207cD15b7545F1A6);
    AaveV3DebtTokenAdaptor private aaveV3DebtTokenAdaptor =
        AaveV3DebtTokenAdaptor(0x6DEd49176a69bEBf8dC1a4Ea357faa555df188f7);
    AaveATokenAdaptor private aaveATokenAdaptor = AaveATokenAdaptor(0xe3A3b8AbbF3276AD99366811eDf64A0a4b30fDa2);
    AaveDebtTokenAdaptor private aaveDebtTokenAdaptor =
        AaveDebtTokenAdaptor(0xeC86ac06767e911f5FdE7cba5D97f082C0139C01);
    ERC20Adaptor private erc20Adaptor = ERC20Adaptor(0xB1d08c5a1A67A34d9dC6E9F2C5fAb797BA4cbbaE);
    OneInchAdaptor private oneInchAdaptor = OneInchAdaptor(0xB8952ce4010CFF3C74586d712a4402285A3a3AFb);
    ZeroXAdaptor private zeroXAdaptor = ZeroXAdaptor(0x1039a9b61DFF6A3fb8dbF4e924AA749E5cFE35ef);

    PriceRouter private priceRouter = PriceRouter(0x138a6d8c49428D4c71dD7596571fbd4699C7D3DA);
    SwapRouter private swapRouter = SwapRouter(0x070f43E613B33aD3EFC6B2928f3C01d58D032020);

    Registry private registry;
    CellarFactory private factory;

    address private implementation = 0x3A763A9db61f4C8B57d033aC11d74e5c9fB3314f;

    CellarInitializableV2_2 private cellar;

    modifier checkBlockNumber() {
        if (block.number < 17297048) {
            console.log("INVALID BLOCK NUMBER: Contracts not deployed yet use 17297048.");
            return;
        }
        _;
    }

    function setUp() external checkBlockNumber {
        registry = new Registry(gravityBridge, address(swapRouter), address(priceRouter));
        factory = new CellarFactory();

        cellarAdaptor = new CellarAdaptor();

        factory.adjustIsDeployer(address(this), true);

        factory.addImplementation(implementation, 2, 2);

        registry.trustAdaptor(address(erc20Adaptor));
        registry.trustAdaptor(address(aaveATokenAdaptor));
        registry.trustAdaptor(address(aaveDebtTokenAdaptor));
        registry.trustAdaptor(address(aaveV3ATokenAdaptor));
        registry.trustAdaptor(address(aaveV3DebtTokenAdaptor));
        registry.trustAdaptor(address(oneInchAdaptor));
        registry.trustAdaptor(address(zeroXAdaptor));
        registry.trustAdaptor(address(cellarAdaptor));

        uint32[] memory positionIds = new uint32[](7);
        positionIds[0] = registry.trustPosition(address(erc20Adaptor), abi.encode(address(WETH)));
        positionIds[1] = registry.trustPosition(address(erc20Adaptor), abi.encode(address(LINK)));
        positionIds[2] = registry.trustPosition(address(aaveATokenAdaptor), abi.encode(address(aV2LINK)));
        positionIds[3] = registry.trustPosition(address(aaveV3ATokenAdaptor), abi.encode(address(aV3LINK)));
        positionIds[4] = registry.trustPosition(address(aaveDebtTokenAdaptor), abi.encode(address(dV2WETH)));
        positionIds[5] = registry.trustPosition(address(aaveV3DebtTokenAdaptor), abi.encode(address(dV3WETH)));
        positionIds[6] = registry.trustPosition(address(cellarAdaptor), abi.encode(address(rye)));

        // Deploy cellar using factory.
        bytes memory initializeCallData = abi.encode(
            address(this),
            registry,
            LINK,
            "Test RYGOV",
            "TRYGOV",
            positionIds[3],
            abi.encode(1.10e18),
            strategist
        );
        address imp = factory.getImplementation(2, 2);
        require(imp != address(0), "Invalid implementation");

        address clone = factory.deploy(2, 2, initializeCallData, LINK, 0, keccak256(abi.encode(block.timestamp)));
        cellar = CellarInitializableV2_2(clone);

        cellar.addAdaptorToCatalogue(address(aaveATokenAdaptor));
        cellar.addAdaptorToCatalogue(address(aaveDebtTokenAdaptor));
        cellar.addAdaptorToCatalogue(address(aaveV3ATokenAdaptor));
        cellar.addAdaptorToCatalogue(address(aaveV3DebtTokenAdaptor));
        cellar.addAdaptorToCatalogue(address(oneInchAdaptor));
        cellar.addAdaptorToCatalogue(address(zeroXAdaptor));
        cellar.addAdaptorToCatalogue(address(cellarAdaptor));

        for (uint32 i; i < positionIds.length; ++i) cellar.addPositionToCatalogue(positionIds[i]);

        cellar.addPosition(1, positionIds[0], abi.encode(0), false);
        cellar.addPosition(2, positionIds[1], abi.encode(0), false);
        cellar.addPosition(3, positionIds[6], abi.encode(0), false);

        cellar.addPosition(0, positionIds[5], abi.encode(0), true);

        cellar.setShareLockPeriod(300);

        // cellar.transferOwnership(strategist);
    }

    function testLinkRealYieldGov() external checkBlockNumber {
        uint256 assets = 10_000e18;
        deal(address(LINK), address(this), assets);
        LINK.approve(address(cellar), assets);
        cellar.deposit(assets, address(this));

        // Rebalance Cellar into RYE.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](2);
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            uint256 amountToBorrow = priceRouter.getValue(LINK, assets / 2, WETH);
            adaptorCalls[0] = _createBytesDataToBorrow(dV3WETH, amountToBorrow);
            data[0] = Cellar.AdaptorCall({ adaptor: address(aaveV3DebtTokenAdaptor), callData: adaptorCalls });
        }
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToDepositIntoCellar(rye, type(uint256).max);
            data[1] = Cellar.AdaptorCall({ adaptor: address(cellarAdaptor), callData: adaptorCalls });
        }

        cellar.callOnAdaptor(data);

        vm.warp(block.timestamp + 1 days / 2);

        uint256 assetsToWithdraw = cellar.maxWithdraw(address(this));
        cellar.withdraw(assetsToWithdraw, address(this), address(this));
        console.log("WETH", WETH.balanceOf(address(this)));
    }

    // ========================================= HELPER FUNCTIONS =========================================

    function _createBytesDataToBorrow(ERC20 debtToken, uint256 amountToBorrow) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(AaveV3DebtTokenAdaptor.borrowFromAave.selector, debtToken, amountToBorrow);
    }

    function _createBytesDataToDepositIntoCellar(Cellar target, uint256 amount) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(CellarAdaptor.depositToCellar.selector, target, amount);
    }

    function _createBytesDataForSwap(ERC20 from, ERC20 to, uint256 fromAmount) internal pure returns (bytes memory) {
        address[] memory path = new address[](2);
        path[0] = address(from);
        path[1] = address(to);
        return abi.encodeWithSelector(SwapWithUniswapAdaptor.swapWithUniV2.selector, path, fromAmount, 0);
    }

    function _createBytesDataToLend(ERC20 tokenToLend, uint256 amountToLend) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(AaveATokenAdaptor.depositToAave.selector, tokenToLend, amountToLend);
    }

    function _createBytesDataToWithdrawFromAaveV3(
        ERC20 tokenToWithdraw,
        uint256 amountToWithdraw
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(AaveV3ATokenAdaptor.withdrawFromAave.selector, tokenToWithdraw, amountToWithdraw);
    }
}
