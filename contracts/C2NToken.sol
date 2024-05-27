pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract C2NToken is ERC20 {
    constructor()
        ERC20("C2N", "C2N")

    {}

    function mint(address to, uint256 amount) public  {
        _mint(to, amount);
    }
}