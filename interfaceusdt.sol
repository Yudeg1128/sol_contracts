// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

abstract contract ComboLender {
    uint public decimals;
    function createBorrower(bytes32[] memory _account, address[] memory _borrowerAddress) external virtual returns(uint);
    function createLoan(uint _borrowerId, uint _amount, uint _tenor, uint _interest) external virtual;
    function createPledge(bytes32[] memory _account, address[] memory _lenderAddress, uint _loanId, uint _acceptedPledge) external virtual returns(bool);
    function repayLoan(uint _loanId, uint _repayAmount) external virtual;
}

contract InterfaceUSDT {
        
    address owner; 
    address public stablecoin_address; 

    ComboLender lenderContract;

    constructor(
        address _USDT_address,
        address _lender_address
        ) {
        owner = msg.sender;
        stablecoin_address = _USDT_address;
        lenderContract = ComboLender(_lender_address);
    }

    function createBorrower(address[] memory _borrowerAddress) external returns(uint) {
        require(msg.sender == owner, "only owner");
        bytes32[] memory _account;
        return lenderContract.createBorrower(_account, _borrowerAddress);
    }

    function createLoan(uint _borrowerId, uint _amount, uint _tenor, uint _interest) external {
        require(msg.sender == owner, "only owner");
        lenderContract.createLoan(_borrowerId, _amount, _tenor, _interest);
    }

    function createPledge(address[] memory _lenderAddress, uint _loanId, uint _acceptedPledge) external returns(bool) {
        require(msg.sender == owner, "only owner");
        bytes32[] memory _account;
        return lenderContract.createPledge(_account, _lenderAddress, _loanId, _acceptedPledge);
    }

    function repayLoan(uint _loanId, uint _repayAmount) external {
        require(msg.sender == owner, "only owner");
        lenderContract.repayLoan(_loanId, _repayAmount);        
    }

}
