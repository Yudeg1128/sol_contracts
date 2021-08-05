// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./stablecoin.sol";

contract Lender {
    
    address private owner; 
    AICoin private AIC;
    uint private _overdue_fee;
    uint private _nowTime;
    uint private _nowThisBalance;

    constructor(
        AICoin _stablecoin_address
        ) {
        owner = msg.sender; 
        AIC = _stablecoin_address;
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
        address borrower;
        State currentState;
    }
    
    Loan _loan;
    uint CurrentLoanIndex;
    Loan[] overdue_loans;
    
    mapping (address => Loan[]) internal loans;
    address[] internal borrowerAccounts;
    
    function nowTime() internal {
        _nowTime = block.timestamp;
    }
    
    function nowThisBalance() internal {
        _nowThisBalance = AIC.balanceOf(address(this));
    }
    
    function borrowerIsNew(address _borrower) view internal returns(bool) {
        for(uint i = 0; i < borrowerAccounts.length; i++){
            if(borrowerAccounts[i] == _borrower){
                return false;}
        } 
        return true;
    }
    //change all 300 to 86400 in production
    function checkOverdue() public {
        require(msg.sender == owner, 'only owner can check overdue loans');
        for(uint i = 0; i < borrowerAccounts.length; i++){
            for (uint j = 0; j < loans[borrowerAccounts[i]].length; j++){
                if(block.timestamp > loans[borrowerAccounts[i]][j].end + 300 && loans[borrowerAccounts[i]][j].currentState == State.ACTIVE){
                    _loan = loans[borrowerAccounts[i]][j];
                    CurrentLoanIndex = _loan.id;
                    _transitionTo(State.OVERDUE);
                }
            }
        }
    }

    function createBorrower(address _borrower) public {
        require(msg.sender == owner, 'only owner can create new borrower');
        require(borrowerIsNew(_borrower) == true, 'borrower already exists');            
        borrowerAccounts.push(_borrower);
    }

    function createLoan(uint _amount, uint _interest, uint _duration, address _borrower) public {
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

    function selectLoan(address _borrower, uint _id) public {
        require(msg.sender == owner || msg.sender == _borrower, 'only owner or borrower can select current loan');
        require(borrowerIsNew(_borrower) == false, 'borrower does not exists');
        _loan = loans[_borrower][_id];
        CurrentLoanIndex = _loan.id;
    }

    function viewBorrowers() view public returns(address[] memory) {
        if(msg.sender == owner){
            return borrowerAccounts;
        }
        else{}
    }

    function viewLoans(address payable _borrower) view public returns(Loan[] memory) {
        if(msg.sender == owner && borrowerIsNew(_borrower) == false){
            return loans[_borrower];
        }
        else{}
    }

    function checkCurrentLoan() view public returns (Loan memory) {
        if(msg.sender == owner){
            return _loan;
        }
        else{}
    }
    
    function viewOverdueLoans() view public returns (Loan[] memory) {
        if(msg.sender == owner){
            return overdue_loans;
        }
        else{}
    }
    
    function fund() payable external {
        nowThisBalance();
        require(msg.sender == owner, 'only owner can lend from contract');
        require(_nowThisBalance >= _loan.amount, 'lender contract account balance not enough');
        _transitionTo(State.ACTIVE);
        AIC.transfer(_loan.borrower, _loan.amount);
    }
    //change all 300 to 86400 in production
    function reimburse() payable external {
        nowTime();
        nowThisBalance();
        require(msg.sender == owner, 'only owner can reimburse');
        require(_nowTime > _loan.end, 'loan has not matured yet');
        if(_nowTime >= _loan.end + 300) { 
            _overdue_fee = _loan.amount * 1/100 * (_nowTime - _loan.end - 300) / 300;
            require(_nowThisBalance >= _loan.amount + _loan.interest + _overdue_fee, 'contract balance less than reimburse amount and overdue');
            _transitionTo(State.OVERDUECLOSED);
            AIC.transfer(owner, _loan.amount + _loan.interest + _overdue_fee);
        }
        else if(_nowTime < _loan.end + 300) {
            require(_nowThisBalance >= _loan.amount + _loan.interest, 'contract balance less than reimburse amount and int');
            _transitionTo(State.CLOSED);
            AIC.transfer(owner, _loan.amount + _loan.interest);
        }
    }
    //change all 3 to 86400 in production
    function _transitionTo(State to) internal {
      require(to != State.PENDING, 'cannot go back to pending');
      require(to != _loan.currentState, 'cannot transition to same state');
      if(to == State.ACTIVE) {
        require(_loan.currentState == State.PENDING, 'can only go to active from pending');
        loans[_loan.borrower][CurrentLoanIndex].currentState = State.ACTIVE;
        loans[_loan.borrower][CurrentLoanIndex].start = block.timestamp;
        loans[_loan.borrower][CurrentLoanIndex].end = block.timestamp + (_loan.duration * 3);
        selectLoan(_loan.borrower, CurrentLoanIndex);
      }
      else if(to == State.CLOSED) {
        require(_loan.currentState == State.ACTIVE, 'can only go to closed from active or overdue');
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
