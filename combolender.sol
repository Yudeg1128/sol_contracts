// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

// abstract implementation of TetherToken - USDT contract
abstract contract StableToken {
    uint public decimals;
    function transfer(address _to, uint _value) public virtual;
    function balanceOf(address who) public virtual returns (uint);
}

abstract contract StablecoinLender {
    address public stablecoin_address;
}

contract ComboLender {
        
    address private owner; 

    constructor(
        ) {
        owner = msg.sender;
    }

    StableToken stablecoin;

    StablecoinLender stablecoinLender;
    
    enum State {
        PENDING,
        ACTIVE,
        OVERDUE,
        CLOSED,
        INACTIVECLOSED,
        OVERDUECLOSED
    }
        
    struct Loan {
        uint id;
        bool stablecoinTx;
        uint borrowerId;
        uint[] lenderIds;
        mapping (uint => uint[]) lenderData; // lender id => [lenderPledges;lenderInterests;lenderPlatformFees;lenderOverdueFees;] 
        uint amount;
        uint tenor; //seconds
        uint interest;
        uint overdueFee;
        uint pledge;
        uint[2] platformFees; // [borrowerPlatformFee, lenderPlatformFee] to aviod StackTooDeep
        uint[4] dates; // [createDate; start; end; closed] to aviod StackTooDeep
        State currentState;
    }

    struct Borrower {
        uint id;
        uint date;
        uint[] loans;
        bytes32[] accounts;
        address borrowerAddress;
    }

    struct Lender {
        uint id;
        uint date;
        uint[] loans;
        bytes32[] accounts;
        address lenderAddress;
    }
    
    // map structs to their unique ids - ids must start from 1 not 0!!!
    mapping (uint => Loan) public loans; // key is NOT borrowerId, it's its own ID!
    mapping (uint => Borrower) public borrowers;
    mapping (uint => Lender) public lenders;

    // track overdue loans
    uint[] overdueLoans;

    // track the last ids
    uint public loanIds;
    uint public borrowerIds;
    uint public lenderIds;

    // track all existing accounts and addresses to ids
    mapping (bytes32 => uint) public borrowerAccounts;
    mapping (bytes32 => uint) public lenderAccounts;
    mapping (address => uint) public borrowerAddresses;
    mapping (address => uint) public lenderAddresses;

    // helpful variables
    uint public piggybankFiat = 0; //tracking all fiat fees
    uint public piggybankCoin = 0; //tracking all stablecoin fees
    uint oneDay = 600; //use 86400 seconds for 24 hours
    uint public overdueFeePerDay = 1; //pct per day
    uint public borrowerPlatformFee = 1; // parts per platformFeeBase
    uint public lenderPlatformFee = 1; // parts per platformFeeBase
    uint public platformFeeBase = 200; // from the added value i.e. interest
    uint public minPlatformFee = 1; // has to be an int

    // define a list of approved stablecoin lender addresses
    mapping (address => bool) public approvedStablecoinLenders;

    function addStablecoinLender(address _address) external {
        require(msg.sender == owner, "only owner can add stablecoin lender");
        approvedStablecoinLenders[_address] = true;
    }

    // check if an account or address has been used by a borrower
    function borrowerExists(bytes32[] memory _accounts, address _borrowerAddress) view public returns(uint) {
        uint checkPlaceholder = 0;
        for(uint  i; i < _accounts.length; i++) {
            bytes32 _account = _accounts[i];
            checkPlaceholder += borrowerAccounts[_account];
        }
        checkPlaceholder += borrowerAddresses[_borrowerAddress];

        return checkPlaceholder;
    }

    // check if an account or address has been used by a lender
    function lenderExists(bytes32[] memory _accounts, address _lenderAddress) view public returns(uint) {
        uint checkPlaceholder = 0;
        for(uint  i; i < _accounts.length; i++) {
            bytes32 _account = _accounts[i];
            checkPlaceholder += lenderAccounts[_account];
        }
        checkPlaceholder += lenderAddresses[_lenderAddress];

        return checkPlaceholder;
    }

    // create a new borrower struct
    function createBorrower(bytes32[] memory _accounts, address _borrowerAddress) external returns(uint) {
        require(msg.sender == owner || approvedStablecoinLenders[msg.sender], "only owner or approved stablecoin lender contracts can create borrowers");
        require(borrowerExists(_accounts, _borrowerAddress) == 0, "borrower already exists");
        borrowerIds += 1;
        Borrower storage _borrower = borrowers[borrowerIds];
        _borrower.id = borrowerIds;
        _borrower.date = block.timestamp;
        _borrower.accounts = _accounts;

        for(uint i; i < _accounts.length; i++) {
            borrowerAccounts[_accounts[i]] = borrowerIds;
        }

        _borrower.borrowerAddress = _borrowerAddress;
        borrowerAddresses[_borrowerAddress] = borrowerIds;

        return borrowerIds;
    }

    // if existing borrower uses a new account, add it to the Borrower struct
    function addBorrowerAccount(uint _borrowerId, bytes32 _account) external {
        require(msg.sender == owner, "only owner can add borrower accounts");
        Borrower storage _borrower = borrowers[_borrowerId];
        _borrower.accounts.push(_account);
    }

    // if existing borrower uses a new account, add it to the Borrower struct
    function addLenderAccount(uint _lenderId, bytes32 _account) external {
        require(msg.sender == owner, "only owner can add borrower accounts");
        Lender storage _lender = lenders[_lenderId];
        _lender.accounts.push(_account);
    }

    // check if borrower already has an active or overdue loan outstanding
    function checkActiveOverdue(uint _borrowerId) view internal returns(bool) {
        uint checkPlaceholder = 0;
        Borrower storage _borrower = borrowers[_borrowerId];
        uint[] memory _loans = _borrower.loans;
        for(uint i; i < _loans.length; i++) {
            uint _loanId = _loans[i];
            Loan storage _loan = loans[_loanId];
            if(_loan.currentState == State.ACTIVE || _loan.currentState == State.OVERDUE) {
                checkPlaceholder++;
            }
        }
        if(checkPlaceholder == 0) {
            return false;
        } else {
            return true;
        }

    }

    // create a new loan
    function createLoan(uint _borrowerId, uint _amount, uint _tenor, uint _interest) external {
        require(msg.sender == owner || approvedStablecoinLenders[msg.sender], "only owner or approved stablecoin lender contracts can create borrowers");
        require(checkActiveOverdue(_borrowerId) == false, "borrower already has an active or overdue loan");
        loanIds += 1;        
        Loan storage _loan = loans[loanIds];
        _loan.id = loanIds;
        if(approvedStablecoinLenders[msg.sender]) {
            _loan.stablecoinTx = true;
        }
        _loan.borrowerId = _borrowerId;
        _loan.dates[0] = block.timestamp;
        _loan.amount = _amount;
        _loan.tenor = _tenor;
        _loan.interest = _interest;
        uint _borrowerPlatformFeeRaw = borrowerPlatformFee * _interest / platformFeeBase;
        if(_borrowerPlatformFeeRaw > minPlatformFee) {
            _loan.platformFees[0] = _borrowerPlatformFeeRaw; 
        } else {
            _loan.platformFees[0] = minPlatformFee; 
        }
        _loan.currentState = State.PENDING;

        Borrower storage _borrower = borrowers[_borrowerId];
        _borrower.loans.push(loanIds);

    }

    //call if in alotted time loan was not pledged fully
    function inactivateLoan(uint _loanId) external {
        require(msg.sender == owner, "only owner can inactivate loans");
        Loan storage _loan = loans[_loanId];
        require(_loan.currentState == State.PENDING, "loan can inactivate only form pending");
        stateMachine(State.PENDING, State.INACTIVECLOSED, _loanId);
    }

    // check accepted amount of pledge made by a lender
    function checkAcceptedPledge(uint _loanId, uint _pledgeAmount) view external returns(uint) {
        require(msg.sender == owner, "only owner can check pledges");
        require(_pledgeAmount > 0, "pledge must be larger than 0");
        Loan storage _loan = loans[_loanId];
        require(_loan.currentState == State.PENDING, "can pledge only to pending loans");
        if(_loan.amount >= (_loan.pledge + _pledgeAmount)) {
            return _pledgeAmount;
        } else {
            return (_loan.pledge + _pledgeAmount) - _loan.amount; // this uint will always be different than _pledgeAmount
        }
    }

    // a lender makes a pledge with an accepted amount - frontend must first check pledge amount was wired inter-bank or on etherscan!
    function createPledge(bytes32[] memory _accounts, address _lenderAddress, uint _loanId, uint _acceptedPledge) external returns(bool) {
        require(msg.sender == owner || approvedStablecoinLenders[msg.sender], "only owner or approved stablecoin lender contracts can create borrowers");
        Loan storage _loan = loans[_loanId];
        require(_loan.currentState == State.PENDING, "can pledge only to pending loans");
        require((_acceptedPledge + _loan.pledge) <= _loan.amount, "pledge cannot exceed amount");
        lenderIds += 1;
        _loan.lenderIds.push(lenderIds);
        _loan.lenderData[lenderIds][0] = _acceptedPledge;
        uint _lenderInterest = (_loan.interest * _acceptedPledge) / _loan.amount;
        _loan.lenderData[lenderIds][1] = _lenderInterest;
        uint _lenderPlatformFee = lenderPlatformFee * _lenderInterest / platformFeeBase;
        if(_lenderPlatformFee > minPlatformFee) {
            _loan.lenderData[lenderIds][2] = _lenderPlatformFee;
            _loan.platformFees[1] += _lenderPlatformFee;
        } else {
            _loan.lenderData[lenderIds][2] = minPlatformFee;
            _loan.platformFees[1] += minPlatformFee;
        }
        _loan.pledge += _acceptedPledge;

        Lender storage _lender = lenders[lenderIds];
        _lender.loans.push(_loanId);

        if(lenderExists(_accounts, _lenderAddress) == 0) {
            _lender.id = lenderIds;
            _lender.date = block.timestamp;
            _lender.accounts = _accounts;
            for(uint i; i < _accounts.length; i++) {
                lenderAccounts[_accounts[i]] = lenderIds;
            }
            _lender.lenderAddress = _lenderAddress;           
        }

        if(_loan.pledge == _loan.amount) {
            if(_loan.stablecoinTx) {
                stablecoinLender = StablecoinLender(msg.sender);
                stablecoin = StableToken(stablecoinLender.stablecoin_address());
                require(stablecoin.balanceOf(address(this)) - piggybankCoin >= _loan.amount, "lender contract balance not enough");
                stablecoin.transfer(borrowers[_loan.borrowerId].borrowerAddress, _loan.amount);
            }
            stateMachine(State.PENDING, State.ACTIVE, _loanId);
            return true;
        } else {
            return false;
        }
    }

    // scan for overdue loans
    function scanOverdueLoans() public {
        for(uint i=1; i <= loanIds; i++) {
            Loan storage _loan = loans[i];
            if(block.timestamp > (_loan.dates[2] + oneDay)) {
                if(_loan.currentState == State.ACTIVE || _loan.currentState == State.OVERDUE)  {
                    uint overdueSeconds = block.timestamp - (_loan.dates[2] + oneDay);
                    uint _overdueFee = ((overdueSeconds / oneDay + 1) * overdueFeePerDay) * (_loan.amount / 100);
                    _loan.overdueFee = _overdueFee;
                    for(uint j; j < _loan.lenderIds.length; j++) {
                        uint _lenderId = _loan.lenderIds[j];
                        _loan.lenderData[_lenderId][3] = (((_loan.lenderData[_lenderId][0] * 100) / _loan.amount) * _overdueFee) / 100;
                    }

                    if(_loan.currentState == State.ACTIVE) {
                        stateMachine(State.ACTIVE, State.OVERDUE, i);
                    }
                }
            }        
        }
    }

    // repay an active or overdue loan - frontend must check if borrower has wired or transferred the amount!
    function repayLoan(uint _loanId, uint _repayAmount) external {
        require(msg.sender == owner || approvedStablecoinLenders[msg.sender], "only owner or approved stablecoin lender contracts can repay loan");
        Loan storage _loan = loans[_loanId];
        require(_loan.dates[2] < block.timestamp, "loan not due yet");
        require(_loan.currentState == State.ACTIVE || _loan.currentState == State.OVERDUE, "not an active or overdue loan");
        uint loanRepayAmount = _loan.amount + _loan.interest + _loan.overdueFee + _loan.platformFees[0];
        require(_repayAmount >= loanRepayAmount, "not enough funds to repay loan");
        if(_loan.stablecoinTx) {
            stablecoinLender = StablecoinLender(msg.sender);
            stablecoin = StableToken(stablecoinLender.stablecoin_address());
            require(loanRepayAmount <= stablecoin.balanceOf(address(this)) - piggybankCoin, "lender contract balance not enough");
            for(uint  i; i < _loan.lenderIds.length; i++) {
                uint _lenderId = _loan.lenderIds[i];
                uint _lenderRepayment = _loan.lenderData[_lenderId][0] + _loan.lenderData[_lenderId][1] + _loan.lenderData[_lenderId][3] - _loan.lenderData[_lenderId][2];
                stablecoin.transfer(lenders[_lenderId].lenderAddress, _lenderRepayment);
            }
        }
        if(_loan.currentState == State.ACTIVE) {
            stateMachine(State.ACTIVE, State.CLOSED, _loanId);
        } else if(_loan.currentState == State.OVERDUE) {
            stateMachine(State.OVERDUE, State.OVERDUECLOSED, _loanId);
        }
    }

    // loan state StateMachine
    function stateMachine(State _from, State _to, uint _loanId) internal {
        Loan storage _loan = loans[_loanId];

        if(_from == State.PENDING && _to == State.INACTIVECLOSED) {
            require(_loan.currentState == State.PENDING, "can transition to inactiveclosed only from pending");
            _loan.dates[3] = block.timestamp;
            _loan.currentState = State.INACTIVECLOSED;
        } else if (_from == State.PENDING && _to == State.ACTIVE) {
            require(_loan.currentState == State.PENDING, "can transition to active only from pending");
            _loan.dates[1] = block.timestamp;
            _loan.dates[2] = block.timestamp + _loan.tenor;
            _loan.currentState = State.ACTIVE;            
        } else if(_from == State.ACTIVE && _to == State.CLOSED) {
            require(_loan.currentState == State.ACTIVE, "can transition to closed only from active");
            _loan.dates[3] = block.timestamp;
            _loan.currentState = State.CLOSED;
            if(_loan.stablecoinTx) {
                piggybankCoin += (_loan.platformFees[0] + _loan.platformFees[1]);
            } else if(!_loan.stablecoinTx) {
                piggybankFiat += (_loan.platformFees[0] + _loan.platformFees[1]);
            }
        } else if(_from == State.ACTIVE && _to == State.OVERDUE) {
            require(_loan.currentState == State.ACTIVE, "can transition to overdue only from active");
            overdueLoans.push(_loanId);
            _loan.currentState = State.OVERDUE;
        } else if(_from == State.OVERDUE && _to == State.OVERDUECLOSED) {
            require(_loan.currentState == State.OVERDUE, "can transition to closed only from active");
            _loan.dates[3] = block.timestamp;
            _loan.currentState = State.OVERDUECLOSED;
            if(_loan.stablecoinTx) {
                piggybankCoin += (_loan.platformFees[0] + _loan.platformFees[1]);
            } else if(!_loan.stablecoinTx) {
                piggybankFiat += (_loan.platformFees[0] + _loan.platformFees[1]);
            }
        }
    }
    
    function viewLoanLenders(uint _loanId) view public returns(uint[] memory) {
        return loans[_loanId].lenderIds;
    }

    function viewLoanLenderData(uint _loanId, uint _lenderId) view public returns(uint[] memory) {
        return loans[_loanId].lenderData[_lenderId];
    }

    function viewLoanPlatformFees(uint _loanId) view public returns(uint[2] memory) {
        return loans[_loanId].platformFees;
    }

    function viewLoanDates(uint _loanId) view public returns(uint[4] memory) {
        return loans[_loanId].dates;
    }

    function viewBorrowerLoans(uint _borrowerId) view public returns(uint[] memory) {
        Borrower storage _borrower = borrowers[_borrowerId];
        return _borrower.loans;
    }

    function viewBorrowerAccounts(uint _borrowerId) view public returns(bytes32[] memory) {
        Borrower storage _borrower = borrowers[_borrowerId];
        return _borrower.accounts;
    }

    function viewLenderLoans(uint _lenderId) view public returns(uint[] memory) {
        Lender storage _lender = lenders[_lenderId];
        return _lender.loans;
    }

    function viewLenderAccounts(uint _lenderId) view public returns(bytes32[] memory) {
        Lender storage _lender = lenders[_lenderId];
        return _lender.accounts;
    }

    function viewOverdueLoans() view public returns(uint[] memory) {
        return overdueLoans;
    }

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

    function createBorrower(address _borrowerAddress) external returns(uint) {
        require(msg.sender == owner, "only owner");
        bytes32[] memory _accounts;
        return lenderContract.createBorrower(_accounts, _borrowerAddress);
    }

    function createLoan(uint _borrowerId, uint _amount, uint _tenor, uint _interest) external {
        require(msg.sender == owner, "only owner");
        lenderContract.createLoan(_borrowerId, _amount, _tenor, _interest);
    }

    function createPledge(address _lenderAddress, uint _loanId, uint _acceptedPledge) external returns(bool) {
        require(msg.sender == owner, "only owner");
        bytes32[] memory _accounts;
        return lenderContract.createPledge(_accounts, _lenderAddress, _loanId, _acceptedPledge);
    }

    function repayLoan(uint _loanId, uint _repayAmount) external {
        require(msg.sender == owner, "only owner");
        lenderContract.repayLoan(_loanId, _repayAmount);        
    }

}
