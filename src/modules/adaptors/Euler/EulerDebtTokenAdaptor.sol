// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { BaseAdaptor, ERC20, SafeTransferLib, Cellar, SwapRouter, Registry, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { IEuler, IEulerMarkets, IEulerExec, IEulerDToken, IEulerEToken, IEulerEulDistributor, EUL } from "src/interfaces/external/IEuler.sol";
import { EulerBaseAdaptor } from "src/modules/adaptors/Euler/EulerBaseAdaptor.sol";

/**
 * @title Euler debtToken Adaptor
 * @notice Allows Cellars to interact with Euler debtToken positions.
 * @author crispymangoes
 */
contract EulerDebtTokenAdaptor is BaseAdaptor, EulerBaseAdaptor {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    //==================== Adaptor Data Specification ====================
    // adaptorData = abi.encode(IEulerDToken dToken, uint256 subAccountId)
    // Where:
    // `dToken` is the Euler debt token address position this adaptor is working with
    // `subAccountId` is the sub account id the position uses
    //================= Configuration Data Specification =================
    // NOT USED
    //====================================================================

    /**
     @notice Attempted borrow would lower Cellar health factor too low.
     */
    error EulerDebtTokenAdaptor__HealthFactorTooLow();

    /**
     * @notice Attempted to use an invalid subAccountId.
     */
    error EulerDebtTokenAdaptor__InvalidSubAccountId();

    /**
     * @notice Strategist attempted to open an untracked Euler loan.
     * @param untrackedDebtPosition the address of the untracked loan
     */
    error EulerDebtTokenAdaptor__DebtPositionsMustBeTracked(address untrackedDebtPosition);

    //============================================ Global Functions ===========================================
    /**
     * @dev Identifier unique to this adaptor for a shared registry.
     * Normally the identifier would just be the address of this contract, but this
     * Identifier is needed during Cellar Delegate Call Operations, so getting the address
     * of the adaptor is more difficult.
     */
    function identifier() public pure override returns (bytes32) {
        return keccak256(abi.encode("Euler debtToken Adaptor V 1.0"));
    }

    /**
     * @notice The Euler EUL distributor contract on Ethereum Mainnet.
     */
    function distributor() internal pure returns (IEulerEulDistributor) {
        return IEulerEulDistributor(0xd524E29E3BAF5BB085403Ca5665301E94387A7e2);
    }

    /**
     * @notice The EUL token contract address on Ethereum Mainnet.
     */
    function eul() internal pure returns (EUL) {
        return EUL(0xd9Fcd98c322942075A5C3860693e9f4f03AAE07b);
    }

    /**
     * @notice Minimum HF enforced after self borrows.
     * @dev A low `HFMIN` is required for strategist to run leveraged strategies,
     *      where the collateral and borrow token are the same.
     *      This does pose a risk of strategists intentionally making their Cellar vulnerable to liquidation
     *      but this is mitigated because of the following
     *      - Euler liquidations are gradual, and increase in size as the position becomes worse, so even if
     *        a Cellar's health factor is slightly below 1, the value lost from liquidation is much less
     *        compared to an Aave or Compound liquidiation
     *      - Given that the MEV liquidation space is so competitive it is extremely unlikely that a strategist
     *        would be able to consistently be the one liquidating the Cellar.
     *      - If a Cellar is constantly being liquidated because of a malicious strategist intentionally lowering the HF,
     *        users will leave the Cellar, and the strategist will lose future recurring income.
     */
    function HFMINSelfBorrow() internal pure returns (uint256) {
        return 1.01e18;
    }

    //============================================ Implement Base Functions ===========================================

    /**
     * @notice User deposits are NOT allowed into this position.
     */
    function deposit(uint256, bytes memory, bytes memory) public pure override {
        revert BaseAdaptor__UserDepositsNotAllowed();
    }

    /**
     * @notice User withdraws are NOT allowed from this position.
     */
    function withdraw(uint256, address, bytes memory, bytes memory) public pure override {
        revert BaseAdaptor__UserWithdrawsNotAllowed();
    }

    /**
     * @notice This position is a debt position, and user withdraws are not allowed so
     *         this position must return 0 for withdrawableFrom.
     */
    function withdrawableFrom(bytes memory, bytes memory) public pure override returns (uint256) {
        return 0;
    }

    /**
     * @notice Returns the cellars balance in terms of the debt tokens underlying asset.
     */
    function balanceOf(bytes memory adaptorData) public view override returns (uint256) {
        (IEulerDToken dToken, uint256 subAccountId) = abi.decode(adaptorData, (IEulerDToken, uint256));
        return dToken.balanceOf(_getSubAccount(msg.sender, subAccountId));
    }

    /**
     * @notice Returns the positions debtToken underlying asset.
     */
    function assetOf(bytes memory adaptorData) public view override returns (ERC20) {
        IEulerDToken dToken = abi.decode(adaptorData, (IEulerDToken));
        return ERC20(dToken.underlyingAsset());
    }

    /**
     * @notice This adaptor reports values in terms of debt.
     */
    function isDebt() public pure override returns (bool) {
        return true;
    }

    //============================================ Strategist Functions ===========================================

    /**
     * @notice Allows strategist to borrow assets from Euler.
     * @param underlying the token to borrow from Euler
     * @param subAccountId the sub account id to borrow assets on
     * @param amountToBorrow the amount of `underlying` on Euler
     */
    function borrowFromEuler(ERC20 underlying, uint256 subAccountId, uint256 amountToBorrow) public {
        // Grab dToken from Euler markets, and verify there is a valid market.
        address dToken = markets().underlyingToDToken(address(underlying));
        if (dToken == address(0)) revert EulerBaseAdaptor__UnderlyingNotSupported(address(underlying));

        // Check that debt position is properly set up to be tracked in the Cellar.
        bytes32 positionHash = keccak256(abi.encode(identifier(), true, abi.encode(dToken, subAccountId)));
        uint32 positionId = Cellar(address(this)).registry().getPositionHashToPositionId(positionHash);
        if (!Cellar(address(this)).isPositionUsed(positionId))
            revert EulerDebtTokenAdaptor__DebtPositionsMustBeTracked(dToken);

        IEulerDToken(dToken).borrow(subAccountId, amountToBorrow);

        // Check that health factor is above adaptor minimum.
        uint256 healthFactor = _calculateHF(_getSubAccount(address(this), subAccountId));
        if (healthFactor < HFMIN()) revert EulerDebtTokenAdaptor__HealthFactorTooLow();
    }

    /**
     * @notice Allows strategists to repay Euler debt.
     * @dev `amountToRepay` can be type(uint256).max to repay all debt.
     * @param underlying the token to repay on Euler
     * @param subAccountId the sub account id to repay debt for
     * @param amountToRepay the amount of debt to repay
     */
    function repayEulerDebt(ERC20 underlying, uint256 subAccountId, uint256 amountToRepay) public {
        // Grab dToken from Euler markets, and verify there is a valid market.
        address dToken = markets().underlyingToDToken(address(underlying));
        if (dToken == address(0)) revert EulerBaseAdaptor__UnderlyingNotSupported(address(underlying));

        underlying.safeApprove(euler(), amountToRepay);
        IEulerDToken(dToken).repay(subAccountId, amountToRepay);

        // Zero out approvals if necessary.
        _revokeExternalApproval(underlying, address(euler()));
    }

    // /**
    //  * @notice Allows strategists to swap assets and repay loans in one call.
    //  * @dev see `repayEulerDebt`, and BaseAdaptor.sol `swap`
    //  */
    // function swapAndRepay(
    //     ERC20 tokenIn,
    //     uint256 subAccountId,
    //     ERC20 underlying,
    //     uint256 amountIn,
    //     SwapRouter.Exchange exchange,
    //     bytes memory params
    // ) public {
    //     uint256 amountToRepay = swap(tokenIn, underlying, amountIn, exchange, params);
    //     repayEulerDebt(underlying, subAccountId, amountToRepay);
    // }

    /**
     * @notice Allows strategist to enter leveraged positions where the collateral and debt are the same token.
     * @param underlying the address of the ERC20 to mint
     * @param subAccountId the subAccount to use
     * @param amount the amount of eTokens, and debtTokens to mint
     */
    function selfBorrow(address underlying, uint256 subAccountId, uint256 amount) public {
        // Check that debt position is properly set up to be tracked in the Cellar.
        address debtToken = markets().underlyingToDToken(underlying);
        bytes32 positionHash = keccak256(abi.encode(identifier(), true, abi.encode(debtToken, subAccountId)));
        uint32 positionId = Cellar(address(this)).registry().getPositionHashToPositionId(positionHash);
        if (!Cellar(address(this)).isPositionUsed(positionId))
            revert EulerDebtTokenAdaptor__DebtPositionsMustBeTracked(debtToken);

        IEulerEToken eToken = IEulerEToken(markets().underlyingToEToken(underlying));
        eToken.mint(subAccountId, amount);

        // Check that health factor is above adaptor minimum.
        uint256 healthFactor = _calculateHF(_getSubAccount(address(this), subAccountId));
        if (healthFactor < HFMINSelfBorrow()) revert EulerDebtTokenAdaptor__HealthFactorTooLow();
    }

    /**
     * @notice Allows strategist to exit leveraged positions where the collateral and debt are the same token.
     * @param underlying the address of the ERC20 to burn
     * @param subAccountId the subAccount to use
     * @param amount the amount of eTokens, and debtTokens to burn
     */
    function selfRepay(address underlying, uint256 subAccountId, uint256 amount) public {
        IEulerEToken eToken = IEulerEToken(markets().underlyingToEToken(underlying));
        eToken.burn(subAccountId, amount);
        // No need to check HF since burn will raise it.
    }

    /**
     * @dev Allows strategists to claim pending EUL rewards earned from borrowing.
     */
    function claim(address token, uint256 claimable, bytes32[] calldata proof) public {
        distributor().claim(address(this), token, claimable, proof, address(0));
    }

    /**
     * @notice Allows strategist to delegate EUL voting power to `delegatee`.
     */
    function delegate(address delegatee) public {
        eul().delegate(delegatee);
    }
}
