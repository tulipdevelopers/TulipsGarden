pragma solidity ^0.5.16;

import "./contracts/token/ERC20/ERC20.sol";
import "./contracts/ownership/MultOwnable.sol";

contract TulipToken is MultOwnable, ERC20{
    constructor (string memory name, string memory symbol) public ERC20(name, symbol) MultOwnable(){
    }

    function contractMint(address account, uint256 amount) external isAnOwner{
        _mint(account, amount);
    }

    function contractBurn(address account, uint256 amount) external isAnOwner{
        _burn(account, amount);
    }


     /* ========== RESTRICTED FUNCTIONS ========== */
    function addOwner(address _newOwner) external isAnOwner {
        addOwnerShip(_newOwner);
    }

    function getOwner() external view isAnOwner{
        getOwners();
    }

    function renounceOwner() external isAnOwner {
        renounceOwnership();
    }
}