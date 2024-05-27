pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MyToken is ERC20 {
    constructor()
        ERC20("MyTokenLP", "MTK")

    {}

    function mint(address to, uint256 amount) public  {
        _mint(to, amount);
    }
}