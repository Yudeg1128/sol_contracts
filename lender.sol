// SPDX-License-Identifier: MIT

pragma solidity ^0.6.8;
pragma experimental ABIEncoderV2;

import "https://github.com/Yudeg1128/sol_contracts/blob/master/stablecoin.sol";

contract Lender {
    
    address private owner; 
    MidasCoin private MDC;
    uint private overdue_fee;

    constructor(
        MidasCoin _stablecoin_address
        ) public {
        owner=msg.sender; 
        MDC = _stablecoin_address;
    }

    enum State {
        PENDING,
        ACTIVE,
        CLOSED,
        OVERDUE,
        OVERDUECLOSED
    }

    struct Loan{
        uint id;
        uint timestamp;
        uint amount;
        uint interest;
        uint duration;
        uint start;
        uint end;
        uint paid;
        address payable borrower;
        State currentState;
    }
    
    Loan _loan;
    uint CurrentLoanIndex;
    Loan[] overdue_loans;
    
    mapping (address => Loan[]) internal loans;
    address[] internal borrowerAccounts;
    
    function borrowerIsNew(address payable _borrower) view internal returns(bool) {
        for(uint i = 0; i < borrowerAccounts.length; i++){
            if(borrowerAccounts[i] == _borrower){
                return false;}
        } 
        return true;
    }
    
    function createBorrower(address payable _borrower) public {
        require(msg.sender == owner, 'only owner can create new borrower');
        require(borrowerIsNew(_borrower) == true, 'borrower already exists');            
        borrowerAccounts.push(_borrower);
    }

    function viewBorrowers() view public returns(address[] memory) {
        require(msg.sender == owner, 'only owner can create view borrowers');
        return borrowerAccounts;
    }

    function createLoan(uint _amount, uint _interest, uint _duration, address payable _borrower) public {
        require(msg.sender == owner, 'only owner can create new loans');
        require(borrowerIsNew(_borrower) == false, 'borrower does not exists');
        uint _start = 0;
        uint _end = 0;
        uint _paid = 0;
        uint _index = loans[_borrower].length;
        _loan = Loan(_index, block.timestamp, _amount, _interest, _duration, _start, _end, _paid, _borrower, State.PENDING);
        loans[_borrower].push(_loan);
        CurrentLoanIndex = _loan.id;
    }

    function viewLoans(address payable _borrower) view public returns(Loan[] memory) {
        require(msg.sender == owner, 'only owner can view loans');
        require(borrowerIsNew(_borrower) == false, 'borrower does not exists');
        return loans[_borrower];
    }
    
    function selectLoan(address payable _borrower, uint _id) public {
        require(msg.sender == owner || msg.sender == _borrower, 'only owner or borrower can select current loan');
        require(borrowerIsNew(_borrower) == false, 'borrower does not exists');
        _loan = loans[_borrower][_id];
        CurrentLoanIndex = _loan.id;
    }
    
    function checkCurrentLoan() view public returns (Loan memory){
        require(msg.sender == owner, 'only owner can check current loan');
        return _loan;
    }
    
    function viewOverdueLoans() view public returns (Loan[] memory) {
        return overdue_loans;
    }
    
    function fund() payable external {
        uint funding_amount = _loan.amount;
        address payable _borrower = _loan.borrower;
        require(msg.sender == owner, 'only owner can lend');
        require(MDC.balanceOf(owner) >= funding_amount, 'lender account balance not enough');
        _transitionTo(State.ACTIVE);
        MDC.transferFrom(owner, _borrower, funding_amount);
    }
        
    function reimburse() payable external {
        require(msg.sender == _loan.borrower, 'only borrower can reimburse');
        require(MDC.balanceOf(_loan.borrower) >= _loan.amount + _loan.interest, 'borrower balance less than amount + interest');
        _transitionTo(State.CLOSED);
        MDC.transferFrom(_loan.borrower, owner, _loan.amount + _loan.interest);
    }
    
    function check_overdue() payable external {
        require(msg.sender == owner, 'only owner can check overdue loans');
        for(uint i = 0; i < borrowerAccounts.length; i++){
            for (uint j = 0; j < loans[borrowerAccounts[i]].length; j++){
                if(block.timestamp > (loans[borrowerAccounts[i]][j].end + 8) && loans[borrowerAccounts[i]][j].currentState == State.ACTIVE){
                    _loan = loans[borrowerAccounts[i]][j];
                    CurrentLoanIndex = _loan.id;
                    _transitionTo(State.OVERDUE);
                }
            }
        }
    }
    
    function reimburse_overdue() payable external {
        overdue_fee = _loan.amount * 1/100 * (block.timestamp - _loan.end) / 86400;
        require(msg.sender == _loan.borrower, 'only borrower can reimburse');
        require(MDC.balanceOf(_loan.borrower) >= _loan.amount + _loan.interest + overdue_fee, 'borrower balance less than amount + interest + overdue_fee');
        _transitionTo(State.OVERDUECLOSED);
        MDC.transferFrom(_loan.borrower, owner, _loan.amount + _loan.interest + overdue_fee);
    }

    function _transitionTo(State to) internal {
      require(to != State.PENDING, 'cannot go back to pending');
      require(to != _loan.currentState, 'cannot transition to same state');
      if(to == State.ACTIVE) {
        require(_loan.currentState == State.PENDING, 'can only go to active from pending');
        loans[_loan.borrower][CurrentLoanIndex].currentState = State.ACTIVE;
        loans[_loan.borrower][CurrentLoanIndex].start = block.timestamp;
        loans[_loan.borrower][CurrentLoanIndex].end = block.timestamp + (_loan.duration * 86400);
        selectLoan(_loan.borrower, CurrentLoanIndex);
      }
      else if(to == State.CLOSED) {
        require(_loan.currentState == State.ACTIVE, 'can only go to closed from active or overdue');
        require(block.timestamp >= _loan.end, 'loan hasnt matured yet');
        loans[_loan.borrower][CurrentLoanIndex].paid = block.timestamp;
        loans[_loan.borrower][CurrentLoanIndex].currentState = State.CLOSED;
        selectLoan(_loan.borrower, CurrentLoanIndex);
      }
      else if(to == State.OVERDUE) {
        require(_loan.currentState == State.ACTIVE, 'can only go to overdue from active');
        loans[_loan.borrower][CurrentLoanIndex].currentState = State.OVERDUE;
        overdue_loans.push(loans[_loan.borrower][CurrentLoanIndex]);
        selectLoan(_loan.borrower, CurrentLoanIndex);
      }
      else if(to == State.OVERDUECLOSED) {
        require(_loan.currentState == State.OVERDUE, 'can only go to overdueclosed from overdue');
        loans[_loan.borrower][CurrentLoanIndex].paid = block.timestamp;
        loans[_loan.borrower][CurrentLoanIndex].currentState = State.OVERDUECLOSED;
        selectLoan(_loan.borrower, CurrentLoanIndex);
        for(uint i = 0; i < overdue_loans.length; i++){
            if(overdue_loans[i].id == _loan.id){
                delete overdue_loans[i];}
        }
      }
    }
}