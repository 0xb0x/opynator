// SPDX-License-Identifier: MIT

pragma solidity 0.6.10;
pragma experimental ABIEncoderV2;

import {Controller} from "./interfaces/IController.sol";
import {IUniswapV2Router01} from "./interfaces/IUniswapV2Router.sol";
import "./interfaces/OtokenInterface.sol";
import {ERC20Interface} from"./interfaces/IERC20.sol";
import {SafeMath} from "./libs/SafeMath.sol";
import {PriceOracle} from "./oracle/Oracle.sol";
import {Actions} from "./libs/Actions.sol";

contract Opynator {
    using SafeMath for uint256;

    Controller public controller;
    IUniswapV2Router01 public router;
    // ERC20Interface public ERC20Interface;
    address public USDC = 0x27415c30d8c87437BeCbd4f98474f26E712047f4;

    PriceOracle public oracle;

    
    mapping(address => Position[]) positions;

    struct Position {
        uint itm;
        address user;
        uint userBalance;
        bool exercised;
    }

    event OptionsPositionDelegated(address user, address asset, bool isPut);
    event PutRedeemedForEth(uint assetAmountRedeemed);

    constructor( address _controller, address _uniRouter) public {
        controller = Controller(_controller);
        router = IUniswapV2Router01(_uniRouter);
    }
  
    function delegate() external {
        require(!controller.isOperator(msg.sender, address(this)));
        controller.setOperator(address(this), true);
    }

    /**
     *  @notice delegate options position to this smart contract
     *  @param asset - address off the asset (oTokens) representing the users position to deposit
     *  @param amount - amount of oTokens to deposit
     *  @param _itm - percent in the moneyness of the options at which it should be exercised
     */
    function delegatePosition(address asset, uint256 amount, uint _itm) external {
        require(!controller.hasExpired(asset));
        OtokenInterface otoken = OtokenInterface(asset);
        (,,,,, bool _isPut) = otoken.getOtokenDetails();
        // require(isPut);
        ERC20Interface(asset).approve(address(this), amount);
        bool success = ERC20Interface(asset).transferFrom(msg.sender, address(this), amount);
        require(success);

        for(uint i = 0; i < positions[asset].length; i++ ){
            if(msg.sender == positions[asset][i].user){
                uint userBal = positions[asset][i].userBalance;
                positions[asset][i].userBalance = userBal.add(amount);
                positions[asset][i].itm = _itm;
            }else{
                positions[asset].push(
                    Position({
                        itm: _itm,
                        user: msg.sender,
                        userBalance: amount,
                        exercised: false
                    })
                );
            }
        }

        emit OptionsPositionDelegated(msg.sender, asset, _isPut);
    }

    /**
     *  @notice redeem put option for eth
     *  @dev redeem put option for usdc and _swapUSDCToETH() - swap to eth
     *  @param asset - oTokens address to redeem
     */
    function redeemPutBuyEthPerExp(address asset) external {
        
        require(controller.hasExpired(asset));
        (,address underlyingAsset,,uint256 strikePrice,,bool _isPut) = OtokenInterface(asset).getOtokenDetails();
        require(_isPut, 'NOT_PUT_OPTION');
        (,int256 underlyingAssPrice,,,) = oracle.getLatestPrice();
        uint256 underlyingAssetPrice = uint256(underlyingAssPrice);
        bool itm = strikePrice > underlyingAssetPrice;
        require(itm, 'OPTION_NOT_IN_THE_MONEY');
        
        uint balance = _exercise(asset, underlyingAssetPrice, strikePrice);

        Actions.ActionArgs[] memory args = parseRedeemArgs(asset, address(this), balance);
        uint256 potentialPayOut = controller.getPayout(asset, balance);
        controller.operate(args);

        // @todo implement swap and get min amount of eth swapped to(x)
        // used fixed point math to calculate payout
        // currently using uniswap to swap tokens can use balancer or swap aggregator or even 
        // integrate flashbot to prevent frontrunning and sandwich attacks
        // slippage currently set to 5%
        uint minSwapAmount = uint(95).div(100);
        uint minPotentialPayout = potentialPayOut.div(underlyingAssetPrice).mul(minSwapAmount);
        uint x = _swapUSDCToETH(potentialPayOut, minPotentialPayout);

        _calculateShareDistEth(asset, x, balance);

        emit PutRedeemedForEth(balance);

    }

    function _exercise(address asset, uint uap, uint strike_price) internal returns(uint){
        uint itmness = calculateITM(uap, strike_price);
        uint balance = 0;

        for(uint i = 0; i < positions[asset].length; i++ ){
            if(positions[asset][i].itm == 0 || positions[asset][i].itm == itmness || positions[asset][i].itm < itmness ){
                positions[asset][i].exercised = true;
            }
            if(positions[asset][i].exercised){
                balance += positions[asset][i].userBalance;
            }
        }

        return balance;
    }
    function _calculateShareDistEth(address asset, uint x, uint balance ) internal {
        for(uint i = 0; i < positions[asset].length; i++ ){
            if(positions[asset][i].exercised){
                // 😥 shity math        50IQ brain
                //             :handshake:         
                uint percentage = ((positions[asset][i].userBalance).div(balance));
                uint share = (x.mul(percentage));
                (bool success, ) = positions[asset][i].user.call{value: share}('');
                require(success);
            }
        }
    }

    /**
     *  @param underlyingAssetPrice - price of underlying asset(eth)
     *  @param strikePrice - strike price of put option
     */
    function calculateITM(uint256 underlyingAssetPrice, uint256 strikePrice) public view returns(uint){
        uint256 intrinsic = strikePrice.sub(underlyingAssetPrice);
        uint res = intrinsic.div(underlyingAssetPrice);
        return res.mul(100);
    }

    function _swapUSDCToETH(uint amount, uint amountOutMin) internal returns(uint) {
        address[] memory path = new address[](2);
        path[0] = USDC;
        path[1] = router.WETH();
        
        ERC20Interface(USDC).approve(address(router), amount);
        uint deadline = block.timestamp + (15 * 60);
        // uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline
        uint[] memory res = router.swapExactTokensForETH(amount, amountOutMin, path, address(this), deadline);
        return res[res.length.sub(1)];
    }

    function parseRedeemArgs(address oToken, address receiver, uint256 _amount) public view returns(Actions.ActionArgs[] memory){
        Actions.ActionArgs[] memory actions = new Actions.ActionArgs[](1); 
        actions[0] = Actions.ActionArgs({
            actionType: Actions.ActionType.Redeem,
            owner: address(0),
            secondAddress: receiver,
            asset: oToken,
            vaultId: 0,
            amount: _amount,
            index: 0,
            data: ''
            });
        return actions;
    }

    /**
     * @notice - withdraw amount from asset balance
     * @param asset - address of asset
     * @param amount - amount of asset
     */
    function exit(address asset, uint amount) external {
        for(uint i = 0; i < positions[asset].length; i++ ){
            if(msg.sender == positions[asset][i].user){
                uint userBal = positions[asset][i].userBalance;
                require( userBal > 0, 'ZERO_BALANCE');
                positions[asset][i].userBalance = userBal.sub(amount);
            }else{
                revert("NO_POSITION_FOUND");
            }
        }
        bool success = ERC20Interface(asset).transferFrom(address(this), msg.sender, amount);        
        require(success);
    }

    // function rollover(){}
}