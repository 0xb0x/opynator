/**
 * SPDX-License-Identifier: UNLICENSED
 */
pragma solidity =0.6.10;
pragma experimental ABIEncoderV2;

import {MarginVault} from "../libs/MarginVault.sol";
import {Actions} from "../libs/Actions.sol";
interface Controller {
 
    function donate(address _asset, uint256 _amount) external;

   
    function setOperator(address _operator, bool _isOperator) external ;


    function operate(Actions.ActionArgs[] memory _actions) external;

    function sync(address _owner, uint256 _vaultId) external;

    function isOperator(address _owner, address _operator) external view returns (bool);

    function getConfiguration()
        external
        view
        returns (
            address,
            address,
            address,
            address
        );

    function getProceed(address _owner, uint256 _vaultId) external view returns (uint256);
    
    function isLiquidatable(
        address _owner,
        uint256 _vaultId,
        uint256 _roundId
    )
        external
        view
        returns (
            bool,
            uint256,
            uint256
        );

    function getPayout(address _otoken, uint256 _amount) external view returns (uint256);
    
    function isSettlementAllowed(
        address _underlying,
        address _strike,
        address _collateral,
        uint256 _expiry
    ) external view returns (bool);

    
    function getAccountVaultCounter(address _accountOwner) external view returns (uint256);

    function hasExpired(address _otoken) external view returns (bool);
    
    function getVault(address _owner, uint256 _vaultId)
        external
        view
        returns (
            MarginVault.Vault memory,
            uint256,
            uint256
        );

}