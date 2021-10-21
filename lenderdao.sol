// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;


import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/math/SafeMath.sol";

// abstract implementation of TetherToken - USDT contract
abstract contract TetherToken {
     function transfer(address _to, uint _value) public virtual;
}

contract Lender {
    
    using SafeMath for uint256;
    
    address private owner; 
    TetherToken Coin;
    

    constructor(
        address _stablecoin_address
        ) {
        owner = msg.sender;
        Coin = TetherToken(_stablecoin_address);
    }
    
    enum RequestState {
        PENDING,
        FILLED,
        CLOSED
    }

    enum LoanState {
        ACTIVE,
        CLOSED,
        OVERDUE,
        OVERDUECLOSED
    }
    
    struct Request {
        address payable borrower;
        address[] lenders;
        mapping (address => uint) lenderPledges;
        mapping (address => uint) lenderInterests;
        uint timestamp;
        uint amount;
        uint tenor;
        uint interest;
        uint pledge;
        RequestState currentRequestState;
    }
    
    struct Loan {
        address payable borrower;
        address[] lenders;
        mapping (address => uint) lenderPledges;
        mapping (address => uint) lenderInterests;
        mapping (address => uint) lenderOverdueFees;
        uint amount;
        uint tenor;
        uint interest;
        uint overdueFee;
        uint start;
        uint end;
        LoanState currentLoanState;
    }
    
    mapping (address => Request) public requests;
    mapping (uint => Loan) public loans;
    mapping (address => uint[]) public loansMap;
    mapping (address => bool) borrowerExists;
    mapping (address => bool) lenderExists;
    uint[] loanKeys;
    address[] borrowerKeys;
    address[] lenderKeys;
    uint oneDay = 600; //use 86400 seconds for 24 hours
    mapping (address => uint) public activeOverdueLoan;

    function viewLoans() view public returns(uint[] memory) {
        return loanKeys;
    }
    
    function viewBorrowers() view public returns(address[] memory) {
        return borrowerKeys;
    }
    
    function viewLenders() view public returns(address[] memory) {
        return lenderKeys;
    }
    
    function viewRequestLenders(address payable _borrower) view public returns(address[] memory) {
        return requests[_borrower].lenders;
    }

    function viewRequestPledges(address payable _borrower, address payable _lender) view public returns(uint) {
        return requests[_borrower].lenderPledges[_lender];
    }

    function viewRequestInterests(address payable _borrower, address payable _lender) view public returns(uint) {
        return requests[_borrower].lenderInterests[_lender];
    }

    function viewLoanLenders(uint _loanId) view public returns(address[] memory) {
        return loans[_loanId].lenders;
    }

    function viewLoanPledges(uint _loanId, address payable _lender) view public returns(uint) {
        return loans[_loanId].lenderPledges[_lender];
    }

    function viewLoanInterests(uint _loanId, address payable _lender) view public returns(uint) {
        return loans[_loanId].lenderInterests[_lender];
    }
    
    function viewLoanOverdueFees(uint _loanId, address payable _lender) view public returns(uint) {
        return loans[_loanId].lenderOverdueFees[_lender];
    }
    
    function viewLoansMap(address payable _address) view public returns(uint[] memory) {
        return loansMap[_address];
    }
    
    function newBorrower(address payable _borrower) external {
        require(msg.sender == owner, 'only owner can create new borrower');
        require(borrowerExists[_borrower] == false, 'borrower already exists'); 
        borrowerExists[_borrower] = true;
        borrowerKeys.push(_borrower);
    }
    
    function borrowerActiveOverdue(address payable _borrower) internal {
        for(uint  i; i < loansMap[_borrower].length; i++) {
            if(loans[loansMap[_borrower][i]].currentLoanState == LoanState.ACTIVE || loans[loansMap[_borrower][i]].currentLoanState == LoanState.OVERDUE) {
                activeOverdueLoan[_borrower] = loansMap[_borrower][i];
            } else {
                activeOverdueLoan[_borrower] = 0;
            }
        }
    }

    function newRequest(address payable _borrower, uint _amount, uint _tenor, uint _interest) external {
        borrowerActiveOverdue(_borrower);
        require(activeOverdueLoan[_borrower] == 0, 'borrower already has an active or overdue loan');
        require(msg.sender == _borrower, 'only borrower can create new request');
        Request storage _request = requests[_borrower];
        _request.borrower = _borrower;
        _request.lenders = new address[](0);
        _request.timestamp = block.timestamp;
        _request.amount = _amount;
        _request.tenor = _tenor;
        _request.interest = _interest;
        _request.pledge = 0;
        _request.currentRequestState = RequestState.PENDING;
    }
    
    event newPledgeMade(address payable _borrower, address _lender, uint _acceptedPledge, bool _requestFilled);
    
    function newPledge(address payable _borrower, uint _increment) external {
        require(requests[_borrower].currentRequestState == RequestState.PENDING, 'can only pledge to pending requests');
        require(borrowerExists[_borrower] == true, 'borrower does not exists'); 
        require(_increment > 0, 'must pledge a positive amount');
        
        Request storage _request = requests[_borrower];
        uint _gap = _request.amount.sub(_request.pledge);
        address _lender = msg.sender;

        if(_gap > _increment) {
            emit newPledgeMade(_borrower, _lender, _increment, false);
        } else {
            _transitionToRequestState(RequestState.FILLED, _borrower);
            emit newPledgeMade(_borrower, _lender, _gap, true);
        }
    }
    
    // lender must transfer the pledge amount to lender contract before calling this function - check with etherscan
    function verifyLenderTx(bool _verification, address payable _borrower, address payable _lender, uint _increment) external {
        require(msg.sender == owner, 'only owner can verify borrower or lender transactions');
        require(_verification == true, 'transaction has not been verified');
        Request storage _request = requests[_borrower];
        _request.pledge = _request.pledge.add(_increment);
        _request.lenders.push(_lender);
        _request.lenderPledges[_lender] = _increment;
        _request.lenderInterests[_lender] =  _increment.mul(100).div(_request.amount).mul(_request.interest).div(100); //*100 and /100 because solidity only has integers
        if(!lenderExists[_lender]){
            lenderKeys.push(_lender);
            lenderExists[_lender] = true;
        }
        if(_request.currentRequestState == RequestState.FILLED) {
            newLoan(_borrower);
        }
    }

    function newLoan(address payable _borrower) internal {
        require(msg.sender == owner, 'only owner can verify borrower or lender transactions');
        require(activeOverdueLoan[_borrower] == 0, 'borrower already has an active or overdue loan');
        uint _index = loanKeys.length+1; //+1 because 0 stands for null in solidity and loan with id 0 would not 'exist'
        loanKeys.push(_index);
        loansMap[_borrower].push(_index);
        Request storage _request = requests[_borrower];
        Loan storage _loan = loans[_index];
        _loan.borrower = _request.borrower;
        _loan.lenders = _request.lenders;
        for(uint  i; i < _request.lenders.length; i++) {
            _loan.lenderPledges[_request.lenders[i]] = _request.lenderPledges[_request.lenders[i]];
            _loan.lenderInterests[_request.lenders[i]] = _request.lenderInterests[_request.lenders[i]];
            loansMap[_request.lenders[i]].push(_index);
        }
        _loan.amount = _request.amount;
        _loan.tenor = _request.tenor;
        _loan.interest = _request.interest;
        _loan.overdueFee = 0;
        _loan.start = block.timestamp;
        _loan.end = block.timestamp + _request.tenor;
        _loan.currentLoanState = LoanState.ACTIVE;
        Coin.transfer(_borrower, _request.amount);
        borrowerActiveOverdue(_borrower);
    }
    
    function closeRequest(address payable _borrower) external {
        require(msg.sender == _borrower || msg.sender == owner, 'only borrower or owner can close pledges');
        Request storage _request = requests[_borrower];
        if(_request.lenders.length > 0){
            for(uint  i; i < _request.lenders.length; i++) {
                Coin.transfer(_request.lenders[i], _request.lenderPledges[_request.lenders[i]]);
            }
        }
        _transitionToRequestState(RequestState.CLOSED, _borrower);
    }
    
    function _transitionToRequestState(RequestState to, address payable _borrower) internal {
        Request storage _request = requests[_borrower];
        if(to == RequestState.FILLED) {
            require(_request.currentRequestState == RequestState.PENDING, 'can only go to filled from pending');
            _request.currentRequestState = RequestState.FILLED;
        } else if (to == RequestState.CLOSED) {
            _request.currentRequestState = RequestState.CLOSED;
        }
    }
        
    // this is the only way to transition to overdue and update overdue fees - should be called at regular intervals to keep fees updated
    function overdues() public {
        for(uint i; i < loanKeys.length; i++) {
            if(loans[loanKeys[i]].currentLoanState == LoanState.ACTIVE && loans[loanKeys[i]].end.add(oneDay) < block.timestamp) {
                _transitionToLoanState(LoanState.OVERDUE, loans[loanKeys[i]].borrower, 0);
            } else if(loans[loanKeys[i]].currentLoanState == LoanState.OVERDUE) {
                Loan storage _loan =  loans[loanKeys[i]];
                uint overdueDays = (block.timestamp.sub(_loan.end).sub(oneDay)).div(oneDay);
                uint overdueFee = _loan.amount.mul(overdueDays).div(100); //overdue fee is defined as 1 percent of loan amount per overdue day
                _loan.overdueFee = overdueFee;
                for(uint  j; j < _loan.lenders.length; j++) {
                    uint lenderOverdueFee = _loan.lenderPledges[_loan.lenders[j]].mul(100).div(_loan.amount).mul(_loan.overdueFee).div(100); //*100 and /100 because solidity only has integers
                    _loan.lenderOverdueFees[_loan.lenders[j]] = lenderOverdueFee;
                }
            }
        }
    }

    event repaymentMade(address _borrower, uint _repayment, uint _gap);
    
    function repayLoan(uint _repayment) external {
        address _borrower = msg.sender;
        require(activeOverdueLoan[_borrower] != 0, 'borrower does not have an active or overdue loan');
        require(block.timestamp > loans[activeOverdueLoan[_borrower]].end, 'not in repayment period');
        Loan storage _loan = loans[activeOverdueLoan[_borrower]];
        uint _check = _loan.amount.add(_loan.interest).add(_loan.overdueFee);
        uint _gap = _repayment.sub(_check);
        emit repaymentMade(_borrower, _repayment, _gap);
    }
    
    // borrower must transfer the repayment amount to this contract before caling this function - check with etherscan
    function verifyBorrowerTx(bool _verification, address payable _borrower, uint _repayment) external {
        require(msg.sender == owner, 'only owner can verify borrower or lender transactions');
        require(_verification == true, 'transaction has not been verified');
        overdues();
        if(loans[activeOverdueLoan[_borrower]].currentLoanState == LoanState.ACTIVE){
            _transitionToLoanState(LoanState.CLOSED, _borrower, _repayment);
        } else if(loans[activeOverdueLoan[_borrower]].currentLoanState == LoanState.OVERDUE){
            _transitionToLoanState(LoanState.OVERDUECLOSED, _borrower, _repayment);
        }
    }
    
    function _transitionToLoanState(LoanState to, address payable _borrower, uint _repayment) internal {
        if(to == LoanState.CLOSED){
            Loan storage _loan = loans[activeOverdueLoan[_borrower]];
            require(_loan.currentLoanState == LoanState.ACTIVE, 'can only go to closed from active');
            require(_loan.amount.add(_loan.interest).add(_loan.overdueFee) <= _repayment, 'repayment not enough');
            for(uint  i; i < _loan.lenders.length; i++) {
                uint lenderRepayment = _loan.lenderPledges[_loan.lenders[i]].add(_loan.lenderInterests[_loan.lenders[i]]);
                Coin.transfer(_loan.lenders[i], lenderRepayment);
            }
            _loan.currentLoanState = LoanState.CLOSED;
            borrowerActiveOverdue(_borrower);
            _transitionToRequestState(RequestState.CLOSED, _borrower);
        } else if(to == LoanState.OVERDUE){
            Loan storage _loan = loans[activeOverdueLoan[_borrower]];
            require(_loan.currentLoanState == LoanState.ACTIVE, 'can only go to overdue from active');
            uint overdueDays = ((block.timestamp.sub(_loan.end).sub(oneDay)).div(oneDay)).add(1); //+1 because overdue of less than one day is 0 for solidity
            uint overdueFee = _loan.amount.mul(overdueDays).div(100); //overdue fee is defined as 1 percent of loan amount per overdue day
            _loan.overdueFee = overdueFee;
            for(uint  i; i < _loan.lenders.length; i++) {
                uint lenderOverdueFee = _loan.lenderPledges[_loan.lenders[i]].mul(100).div(_loan.amount).mul(_loan.overdueFee).div(100); //*100 and /100 because solidity only has integers
                _loan.lenderOverdueFees[_loan.lenders[i]] = lenderOverdueFee;
            }
            _loan.currentLoanState = LoanState.OVERDUE;
            borrowerActiveOverdue(_borrower);
        } else if(to == LoanState.OVERDUECLOSED){
            Loan storage _loan = loans[activeOverdueLoan[_borrower]];
            require(_loan.currentLoanState == LoanState.OVERDUE, 'can only go to overdueclosed from overdue');
            require(_loan.amount.add(_loan.interest).add(_loan.overdueFee) <= _repayment, 'repayment not enough');
            for(uint  i; i < _loan.lenders.length; i++) {
                uint lenderRepayment = _loan.lenderPledges[_loan.lenders[i]].add(_loan.lenderInterests[_loan.lenders[i]]).add(_loan.lenderOverdueFees[_loan.lenders[i]]);
                Coin.transfer(_loan.lenders[i], lenderRepayment);
            }
            _loan.currentLoanState = LoanState.OVERDUECLOSED;
            borrowerActiveOverdue(_borrower);
            _transitionToRequestState(RequestState.CLOSED, _borrower);
        }
    }
}
