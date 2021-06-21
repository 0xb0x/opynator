pragma solidity ^0.6.0;

import "../interfaces/IController.sol";
import {IUniswapv2Router01} from "../interfaces/IuniswapV2Router"

contract opynator {

    IController public controller = IController(0x4ccc2339F87F6c59c6893E1A678c2266cA58dC72);

    function delegate() external {
        controller.setOperator(address(this), true);
    }

    function redeemPutBuyEth(){}

    function closePosition(){}
}