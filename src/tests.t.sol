// SPDX-License-Identifier: AGPL-3.0-only
pragma experimental ABIEncoderV2;
pragma solidity ^0.7.6;

import {DSTest} from "ds-test/test.sol";
import {Math} from "tinlake-math/math.sol";
import {Dai} from "dss/dai.sol";
import {TinlakeRoot} from "tinlake/root.sol";
import {LenderDeployer} from "tinlake/lender/deployer.sol";
import {BorrowerDeployer} from "tinlake/borrower/deployer.sol";
import {TinlakeManager} from "tinlake-maker-lib/mgr.sol";

import {TrancheFab, Tranche} from "tinlake/lender/fabs/tranche.sol";
import {MemberlistFab, Memberlist} from "tinlake/lender/fabs/memberlist.sol";
import {RestrictedTokenFab} from "tinlake/lender/fabs/restrictedtoken.sol";
import {ReserveFab, Reserve} from "tinlake/lender/fabs/reserve.sol";
import {AssessorFab, Assessor} from "tinlake/lender/fabs/assessor.sol";
import {CoordinatorFab, EpochCoordinator} from "tinlake/lender/fabs/coordinator.sol";
import {OperatorFab} from "tinlake/lender/fabs/operator.sol";
import {ClerkFab, Clerk} from "tinlake/lender/adapters/mkr/fabs/clerk.sol";
import {PoolAdminFab} from "tinlake/lender/fabs/pooladmin.sol";
import {MKRLenderDeployer} from "tinlake/lender/adapters/mkr/deployer.sol";

import {TitleFab, Title} from "tinlake/borrower/fabs/title.sol";
import {ShelfFab} from "tinlake/borrower/fabs/shelf.sol";
import {PileFab, Pile} from "tinlake/borrower/fabs/pile.sol";
import {CollectorFab} from "tinlake/borrower/fabs/collector.sol";
import {NAVFeedFab, NAVFeed} from "tinlake/borrower/fabs/navfeed.sol";

import {Vat} from "dss/vat.sol";

import {Borrower} from "tinlake/test/system/users/borrower.sol";
import {Investor} from "tinlake/test/system/users/investor.sol";

import {
    DssDeploy,
    VatFab,
    JugFab,
    VowFab,
    CatFab,
    DogFab,
    DaiFab,
    DaiJoinFab,
    FlapFab,
    FlopFab,
    FlipFab,
    ClipFab,
    SpotFab,
    PotFab,
    EndFab,
    ESMFab,
    PauseFab
} from "dss-deploy/DssDeploy.sol";
import {MockGuard} from "dss-deploy/DssDeploy.t.base.sol";
import {GovActions} from "dss-deploy/govActions.sol";
import {DSPause} from "ds-pause/pause.sol";

import {AuthGemJoin} from "dss-gem-joins/join-auth.sol";
import {RwaToken} from "rwa-example/RwaToken.sol";
import {RwaLiquidationOracle} from "rwa-example/RwaLiquidationOracle.sol";
import {RwaUrn} from "rwa-example/RwaUrn.sol";

import {Spotter} from "dss/spot.sol";

interface Hevm {
    function warp(uint256) external;
    function roll(uint256) external;
    function store(address,bytes32,bytes32) external;
    function sign(uint,bytes32) external returns (uint8,bytes32,bytes32);
    function addr(uint) external returns (address);
    function ffi(string[] calldata) external returns (bytes memory);
}

// helpers to deal with ds-pause related beaurocracy
contract ProxyActions {
    DSPause pause;
    GovActions govActions;

    function rely(address from, address to) external {
        address      usr = address(govActions);
        bytes32      tag;  assembly { tag := extcodehash(usr) }
        bytes memory fax = abi.encodeWithSignature("rely(address,address)", from, to);
        uint         eta = block.timestamp;

        pause.plot(usr, tag, fax, eta);
        pause.exec(usr, tag, fax, eta);
    }

    function file(address who, bytes32 ilk, bytes32 what, uint256 data) external {
        address      usr = address(govActions);
        bytes32      tag;  assembly { tag := extcodehash(usr) }
        bytes memory fax = abi.encodeWithSignature("file(address,bytes32,bytes32,uint256)", who, ilk, what, data);
        uint         eta = block.timestamp;

        pause.plot(usr, tag, fax, eta);
        pause.exec(usr, tag, fax, eta);
    }

    function file(address who, bytes32 ilk, bytes32 what, address data) external {
        address      usr = address(govActions);
        bytes32      tag;  assembly { tag := extcodehash(usr) }
        bytes memory fax = abi.encodeWithSignature("file(address,bytes32,bytes32,address)", who, ilk, what, data);
        uint         eta = block.timestamp;

        pause.plot(usr, tag, fax, eta);
        pause.exec(usr, tag, fax, eta);
    }
}

contract Test is DSTest, Math, ProxyActions {
    TinlakeRoot root;
    MKRLenderDeployer lenderDeployer;
    BorrowerDeployer borrowerDeployer;
    DssDeploy dssDeploy;
    RwaLiquidationOracle oracle;
    AuthGemJoin gemJoin;
    TinlakeManager mgr;
    RwaUrn urn;
    MockGuard authority;

    Hevm public hevm = Hevm(HEVM_ADDRESS);

    address dai;
    Dai drop;
    Dai tin;
    Clerk clerk;

    Title public collateralNFT = new Title("Collateral NFT", "collateralNFT");

    uint constant public DEFAULT_NFT_PRICE = 100000000 ether;
    uint constant public DEFAULT_RISK_GROUP_TEST_LOANS = 3;
    uint constant public DEFAULT_SENIOR_RATIO = 82 * 10**25;
    uint constant public DEFAULT_JUNIOR_RATIO = 18 * 10**25;
    uint loan;
    uint tokenId;
    bytes32 lookupId;

    // users
    Borrower borrower;
    Investor seniorInvestorA;
    Investor seniorInvestorB;
    Investor juniorInvestorA;
    Investor juniorInvestorB;

    Memberlist srMemberList;
    Memberlist jrMemberList;
    NAVFeed feed;
    Pile pile;
    Reserve reserve;
    Assessor assessor;
    EpochCoordinator coordinator;

    bytes32 constant ilk = bytes32("DROP-A");

    uint constant WAD = 10 ** 18;
    uint constant RAY = 10 ** 27;

    address[] targetContracts_;

    function targetContracts() public returns (address[] memory) {
      return targetContracts_;
    }

    function setUp() public virtual {

        // -- deploy mcd --

        uint chainId = 1;
        uint pauseDelay = 0;
        uint esmThreshold = 0;
        address gov = address(this);

        authority = new MockGuard();
        dssDeploy = new DssDeploy();
        dssDeploy.addFabs1(
            new VatFab(),
            new JugFab(),
            new VowFab(),
            new CatFab(),
            new DogFab(),
            new DaiFab(),
            new DaiJoinFab()
        );
        dssDeploy.addFabs2(
            new FlapFab(),
            new FlopFab(),
            new FlipFab(),
            new ClipFab(),
            new SpotFab(),
            new PotFab(),
            new EndFab(),
            new ESMFab(),
            new PauseFab()
        );

        dssDeploy.deployVat();
        dssDeploy.deployDai(chainId);
        dssDeploy.deployTaxation();
        dssDeploy.deployAuctions(gov);
        dssDeploy.deployLiquidator();
        dssDeploy.deployEnd();
        dssDeploy.deployPause(pauseDelay, address(authority));
        dssDeploy.deployESM(gov, esmThreshold);
        dssDeploy.releaseAuth();

        // make the test contract a ward of dai.
        hevm.store(
            address(dssDeploy.dai()),
            keccak256(abi.encode(address(this), uint256(0))),
            bytes32(uint(1))
        );

        // make the test contract a ward of vat.
        hevm.store(
            address(dssDeploy.vat()),
            keccak256(abi.encode(address(this), uint256(0))),
            bytes32(uint(1))
        );

        // make the test contract a ward of jug.
        hevm.store(
            address(dssDeploy.jug()),
            keccak256(abi.encode(address(this), uint256(0))),
            bytes32(uint(1))
        );

        // -- prepare the proxy actions (see DssDeploy.base.t.sol) --

        pause = dssDeploy.pause();
        govActions = new GovActions();
        authority.permit(address(this), address(pause), bytes4(keccak256("plot(address,bytes32,bytes,uint256)")));

        // -- prepare rwa asset infra --

        // deploy rwa token
        RwaToken rwa = new RwaToken();

        // deploy rwa oracle
        string memory doc = "acab";
        uint48 remediationPeriod = 1 days;
        // TODO: what does this mean?
        uint value = DEFAULT_NFT_PRICE;

        oracle = new RwaLiquidationOracle(
            address(dssDeploy.vat()),
            address(dssDeploy.vow())
        );
        oracle.init(
            ilk,
            value,
            doc,
            remediationPeriod
        );
        this.rely(address(dssDeploy.vat()), address(oracle));
        (,address pip,,) = oracle.ilks(ilk);

        dssDeploy.vat().init(ilk);
        dssDeploy.vat().file("Line", type(uint).max);
        dssDeploy.vat().file(ilk, "line", type(uint).max);
        dssDeploy.jug().init(ilk);
        dssDeploy.jug().file("base", 0);
        dssDeploy.jug().file(ilk, "duty", ONE); // no interest rn

        // integrate rwa oracle with dss spotter
        // TODO: why?
        Spotter spotter = dssDeploy.spotter();
        this.file(address(spotter), ilk, "mat", RAY);
        this.file(address(spotter), ilk, "pip", pip);
        spotter.poke(ilk);

        // create rwatoken gemjoin
        gemJoin = new AuthGemJoin(address(dssDeploy.vat()), ilk, address(rwa));
        this.rely(address(dssDeploy.vat()), address(gemJoin));

        // -- deploy tinlake --

        root = new TinlakeRoot(address(this), address(this));

        lenderDeployer = new MKRLenderDeployer(
            address(root),
            address(dssDeploy.dai()),
            address(new TrancheFab()),
            address(new MemberlistFab()),
            address(new RestrictedTokenFab()),
            address(new ReserveFab()),
            address(new AssessorFab()),
            address(new CoordinatorFab()),
            address(new OperatorFab()),
            address(new PoolAdminFab()),
            address(new ClerkFab()),
            address(this)
        );

        // values set according to config.sol
        lenderDeployer.init(
            0.75 *10**27,  // minSeniorRatio
            0.85 *10**27,  // maxSeniorRatio
            1000000 ether, // maxReserve
            1 hours,       // challengeTime
            uint(1000000229200000000000000000), // seniorInterestRate (2% / day)
            "Drop",        // seniorName
            "DRP",         // seniorSymbol
            "Tin",         // juniorName
            "TIN"          // juniorSymbol
        );

        lenderDeployer.deployJunior();
        lenderDeployer.deploySenior();
        lenderDeployer.deployReserve();
        lenderDeployer.deployAssessor();
        lenderDeployer.deployPoolAdmin();
        lenderDeployer.deployCoordinator();
        lenderDeployer.deployClerk();

        clerk = Clerk(lenderDeployer.clerk());

        // create tinlake manager
        mgr = new TinlakeManager(
            address(dssDeploy.dai()),
            address(dssDeploy.daiJoin()),
            lenderDeployer.seniorToken(),
            lenderDeployer.seniorOperator(),
            lenderDeployer.seniorTranche(),
            address(dssDeploy.end()),
            address(dssDeploy.vat()),
            address(dssDeploy.vow())
        );

        // create rwa urn
        urn = new RwaUrn(
            address(dssDeploy.vat()),
            address(dssDeploy.jug()),
            address(gemJoin),
            address(dssDeploy.daiJoin()),
            address(mgr)
        );
        gemJoin.rely(address(urn));
        urn.hope(address(mgr));

        mgr.file("urn", address(urn));
        mgr.file("liq", address(oracle));
        rwa.transfer(address(mgr), 1 ether);
        mgr.lock(1 ether);

        lenderDeployer.initMKR(
            address(mgr),
            address(dssDeploy.spotter()),
            address(dssDeploy.vat()),
            address(dssDeploy.jug())
        );
        lenderDeployer.deploy();

        dai = address(dssDeploy.dai());
        coordinator = EpochCoordinator(lenderDeployer.coordinator());
        reserve = Reserve(lenderDeployer.reserve());
        assessor = Assessor(lenderDeployer.assessor());

        borrowerDeployer = new BorrowerDeployer(
            address(root),
            address(new TitleFab()),
            address(new ShelfFab()),
            address(new PileFab()),
            address(new CollectorFab()),
            address(new NAVFeedFab()),
            dai,
            "title",
            "TTL",
            // discountRate 3% per day
            uint(1000000342100000000000000000)
        );

        borrowerDeployer.deployTitle();
        borrowerDeployer.deployPile();
        borrowerDeployer.deployFeed();
        borrowerDeployer.deployShelf();
        borrowerDeployer.deployCollector();
        borrowerDeployer.deploy();

        pile = Pile(borrowerDeployer.pile());

        address[] memory poolAdmins = new address[](1);
        poolAdmins[0] = address(this);
        root.prepare(
            address(lenderDeployer),
            address(borrowerDeployer),
            address(this),
            poolAdmins
        );
        root.deploy();

        root.relyContract(address(reserve), address(this));
        root.relyContract(address(clerk),   address(this));
        mgr.rely(address(clerk));
        // -- create borrower user --

        borrower = new Borrower(borrowerDeployer.shelf(),
                                address(reserve),
                                borrowerDeployer.currency(),
                                borrowerDeployer.pile());

        // set up and price the nft collateral
        tokenId = collateralNFT.issue(address(borrower));
        feed = NAVFeed(borrowerDeployer.feed());

        // new risk type with sane NAV value
        feed.file("riskGroup",
            5,
            8*10**26,
            10*10**26,
            uint(1000000315936290433356735830),
            ONE
        );

        priceNFTandSetRisk(tokenId, DEFAULT_NFT_PRICE, DEFAULT_RISK_GROUP_TEST_LOANS);

        // enable it for loans
        borrower.approveNFT(collateralNFT, borrowerDeployer.shelf());
        loan = borrower.issue(address(collateralNFT), tokenId);


        // -- create new investor users
        drop = Dai(lenderDeployer.seniorToken());
        tin  = Dai(lenderDeployer.juniorToken());
        seniorInvestorA = new Investor(lenderDeployer.seniorOperator(),
                                       lenderDeployer.seniorTranche(),
                                       address(dai),
                                       address(drop));

        seniorInvestorB = new Investor(lenderDeployer.seniorOperator(),
                                       lenderDeployer.seniorTranche(),
                                       address(dai),
                                       address(drop));

        juniorInvestorA = new Investor(lenderDeployer.juniorOperator(),
                                       lenderDeployer.juniorTranche(),
                                       address(dai),
                                       address(tin));

        juniorInvestorB = new Investor(lenderDeployer.juniorOperator(),
                                       lenderDeployer.juniorTranche(),
                                       address(dai),
                                       address(tin));

        // -- authorize this contract on the whitelist contracts
        srMemberList = Memberlist(lenderDeployer.seniorMemberlist());
        jrMemberList = Memberlist(lenderDeployer.juniorMemberlist());
        root.relyContract(address(srMemberList), address(this));
        root.relyContract(address(jrMemberList), address(this));
        KYC(address(seniorInvestorA));
        KYC(address(seniorInvestorB));
        KYC(address(juniorInvestorA));
        /* targetContracts_.push(address(seniorInvestorA)); */
        /* targetContracts_.push(address(juniorInvestorA)); */
    }


    // will BAIL because the 600 day warp overflows the solver
    function testDefaultNoPayback() public {
        uint amount = 5 ether;
        investBothTranchesProportionally(amount);

        // borrow as much as we can
        borrower.borrowAction(loan, amount);
        uint srDebt = assessor.seniorDebt();
        uint srBal = assessor.seniorBalance();

        // accumulate debt
        // loan expires / enters default
        // change uint maturityDate = 20 days;
        // in base_system.sol to see 0 amounts recieved 
        // and warp 20 days
        hevm.warp(block.timestamp + 600 days);

        // interest is 5% a DAY!
        uint debt = pile.debt(loan);
        pile.accrue(loan);

        // don't repay anything

        // investors redeem
        seniorInvestorA.redeemOrder(drop.balanceOf(address(seniorInvestorA)));
        juniorInvestorA.redeemOrder(tin.balanceOf(address(juniorInvestorA)));

        hevm.warp(block.timestamp + 1 days);

        coordinator.closeEpoch();
        // solve + execute the epoch
        solveEpoch();
        hevm.warp(coordinator.minChallengePeriodEnd());
        uint pre = coordinator.lastEpochExecuted();
        coordinator.executeEpoch();

        seniorInvestorA.disburse();
        juniorInvestorA.disburse();

        log_named_uint("we took out a loan of",  amount);
        log_named_uint("leading to a NAV of  ",  feed.currentNAV());
        log_named_uint("sr debt is ",  srDebt);
        log_named_uint("reserve bal", reserve.totalBalance());
        log_named_uint("jrRat is ",  assessor.calcJuniorRatio());
        log_named_uint("srRat is ",  assessor.seniorRatio());
        log_named_uint("repaid: ",  debt);

        // senior investor returns
        uint got = Dai(dai).balanceOf(address(seniorInvestorA));
        log_named_uint("amount received:        ", got);

        // junior investor returns
        uint jrgot = Dai(dai).balanceOf(address(juniorInvestorA));
        log_named_uint("amount received:        ", jrgot);
    }

    // this test has a loan that expires, but eventually half gets repaid
    function testDefaultLoanMaturityPaybackHalf() public {
        uint amount = 5 ether;
        investBothTranchesProportionally(amount);

        // borrow as much as we can
        borrower.borrowAction(loan, amount);
        uint srBal = assessor.seniorBalance();

        // accumulate debt
        // loan expires / enters default
        hevm.warp(block.timestamp + 600 days);

        // interest is 5% a DAY!
        // need to accrue
        pile.accrue(loan);
        uint debt = pile.debt(loan);

        uint payback = debt / 2;

        // give borrower the dai they need to repay the loan
        Dai(dai).mint(address(borrower), payback);
        borrower.doApproveCurrency(borrowerDeployer.shelf(), type(uint).max);

        // difference between repayAction and repay?
        borrower.repay(loan, payback);
        reserve.balance();

        hevm.warp(block.timestamp + 1 days);
        coordinator.closeEpoch();

        // investors redeem
        seniorInvestorA.redeemOrder(drop.balanceOf(address(seniorInvestorA)));
        juniorInvestorA.redeemOrder(tin.balanceOf(address(juniorInvestorA)));

        hevm.warp(block.timestamp + 1 days);

        coordinator.closeEpoch();

        seniorInvestorA.disburse();
        juniorInvestorA.disburse();

        log_named_uint("took out a loan of",  amount);
        log_named_uint("leading to a NAV of  ",  feed.currentNAV());
        log_named_uint("sr debt is ",  assessor.seniorDebt());
        log_named_uint("reserve bal", reserve.totalBalance());
        log_named_uint("jrRat is ",  assessor.calcJuniorRatio());
        log_named_uint("srRat is ",  assessor.seniorRatio());

        // senior investor returns
        uint got = Dai(dai).balanceOf(address(seniorInvestorA));
        log_named_uint("sr amount received:        ", got);

        // junior investor returns
        uint jrgot = Dai(dai).balanceOf(address(juniorInvestorA));
        log_named_uint("jr amount received:        ", jrgot);
    }

    // this test has a loan that expires
    // gets written off,
    // but eventually gets repaid
    function testDefaultThenPayback() public {
        uint amount = 5 ether;
        investBothTranchesProportionally(amount);

        // borrow as much as we can
        borrower.borrowAction(loan, amount);
        uint srBal = assessor.seniorBalance();

        // loan expires
        hevm.warp(block.timestamp + 600 days);

        // interest is 5% a DAY!
        // need to accrue debt
        pile.accrue(loan);
        uint debt = pile.debt(loan);

        // give borrower the dai they need to repay the loan
        Dai(dai).mint(address(borrower), debt);
        borrower.doApproveCurrency(borrowerDeployer.shelf(), type(uint).max);

        // difference between repayAction and repay?
        borrower.repay(loan, debt);
        reserve.balance();

        hevm.warp(block.timestamp + 1 days);

        coordinator.closeEpoch();

        // investors redeem
        seniorInvestorA.redeemOrder(drop.balanceOf(address(seniorInvestorA)));
        juniorInvestorA.redeemOrder(tin.balanceOf(address(juniorInvestorA)));

        hevm.warp(block.timestamp + 1 days);

        coordinator.closeEpoch();

        seniorInvestorA.disburse();
        juniorInvestorA.disburse();

        log_named_uint("took out a loan of",  amount);
        log_named_uint("leading to a NAV of  ",  feed.currentNAV());
        log_named_uint("sr debt is ",  assessor.seniorDebt());
        log_named_uint("reserve bal", reserve.totalBalance());
        log_named_uint("jrRat is ",  assessor.calcJuniorRatio());
        log_named_uint("srRat is ",  assessor.seniorRatio());

        // senior investor returns
        uint got = Dai(dai).balanceOf(address(seniorInvestorA));
        log_named_uint("sr amount received:        ", got);

        // junior investor returns
        uint jrgot = Dai(dai).balanceOf(address(juniorInvestorA));
        log_named_uint("jr amount received:        ", jrgot);
    }

    function testInvestmentsReturnsNormal(uint amount) public {
        amount *= 1 ether;
        uint loanAmt  = amount;
        if (amount == 0) return;
        if (amount > assessor.maxReserve()) return;
        investBothTranchesProportionally(amount);
        // borrow as much as we can
        borrower.borrowAction(loan, amount);
        uint srDebt = assessor.seniorDebt();
        uint srBal = assessor.seniorBalance();
        // accumulate debt
        hevm.warp(block.timestamp + 1 days);
        // interest is 5% a DAY!
        uint debt = pile.debt(loan);

        uint nav = feed.currentNAV();
        log_named_uint("we took out a loan of",  loanAmt);
        log_named_uint("leading to a NAV of  ",  assessor.getNAV());
        log_named_uint("sr debt is ",  srDebt);
        assessor.dripSeniorDebt();
        // give borrower some dai if they need some
        Dai(dai).mint(address(borrower), debt - loanAmt);
        borrower.doApproveCurrency(borrowerDeployer.shelf(), type(uint).max);

        borrower.repay(loan, debt);
        reserve.balance();

        // Due to rounding errors the investors cannot redeem completely
        seniorInvestorA.redeemOrder(99999999 * drop.balanceOf(address(seniorInvestorA)) / 100000000);
        juniorInvestorA.redeemOrder(99999999 *  tin.balanceOf(address(juniorInvestorA)) / 100000000);

        hevm.warp(block.timestamp + 1 days);

        coordinator.closeEpoch();
        assertTrue(!coordinator.submissionPeriod());

        seniorInvestorA.disburse();

        juniorInvestorA.disburse();

        // senior investor returns
        uint got = Dai(dai).balanceOf(address(seniorInvestorA));
        log_named_uint("sr investor A put in    ", rmul(amount, DEFAULT_SENIOR_RATIO));
        uint expected = srDebt * 102 / 100 + srBal;
        log_named_uint("with 2% interest, expect", expected);
        log_named_uint("amount received:        ", got);

        // junior investor returns
        uint jrgot = Dai(dai).balanceOf(address(juniorInvestorA));
        log_named_uint("jr investor A put in    ", rmul(amount, DEFAULT_JUNIOR_RATIO));
        uint expectedjr = debt - loanAmt - (got - rmul(amount, DEFAULT_SENIOR_RATIO)) + rmul(amount, DEFAULT_JUNIOR_RATIO);
        log_named_uint("remainder after drop payout", expectedjr);
        log_named_uint("amount received:        ", jrgot);

        // diffs
        uint srDiff = got > expected ? got - expected : expected - got;
        uint jrDiff = jrgot > expectedjr ? jrgot - expectedjr : expectedjr - jrgot;
        assertLe(srDiff, 1 ether);
        assertLe(jrDiff, 1 ether);
    }


    function testDraw() public {
        uint amount = 10 ether;
        investBothTranchesProportionally(10 ether);
        clerk.raise(1 ether);
        borrower.lock(loan);
        borrower.borrow(loan, 0.001 ether);
        uint srPricePre = assessor.calcSeniorTokenPrice();
        clerk.draw(1 ether);
        uint srPricePost = assessor.calcSeniorTokenPrice();
        assertEq(srPricePre, srPricePost);
    }


    function testInvestmentsReturnsWithClerk() public {
        uint amount = 10;
        if (amount == 0) return;
        if (amount * 1 ether > assessor.maxReserve()) return;
        // install mkr adapters
        reserve.depend("lending", address(clerk));

        investBothTranchesProportionally(amount * 1 ether);
        assessor.dripSeniorDebt();

        uint srdebt = assessor.seniorDebt();
        log_named_uint("sr debt after investment", srdebt);
        uint srbal  = assessor.seniorBalance();
        log_named_uint("sr bal after investment ", srbal);
        log_named_uint("sr price after investment", assessor.calcSeniorTokenPrice());

        uint availablePre = reserve.currencyAvailable();

        // increase the ceiling
        uint allowedIncrease = rmul(feed.currentNAV() + reserve.totalBalance(), 0.13 *10**27);
        clerk.raise(allowedIncrease);
        log_named_uint("raise by                ", allowedIncrease);
        log_named_uint("sr ratio is             ", assessor.seniorRatio());

        srdebt = assessor.seniorDebt();
        log_named_uint("sr debt post clerk.raise", srdebt);
        srbal  = assessor.seniorBalance();
        log_named_uint("sr bal  post clerk.raise", srbal);

        log_named_uint("sr price post clerk.raise", assessor.calcSeniorTokenPrice());


        assessor.dripSeniorDebt();

        uint availablePost = reserve.currencyAvailable();


        assertLe(availablePre, availablePost);
        assertEq(availablePost - availablePre, allowedIncrease);

        // borrow everything available
        borrower.borrowAction(loan, availablePost);

        log_named_uint("loan of                 ", availablePost);
        log_named_uint("leading to a NAV of     ", assessor.getNAV());
        log_named_uint("sr ratio is             ", assessor.seniorRatio());
        assertEq(assessor.seniorRatio(), DEFAULT_SENIOR_RATIO); // the loan shouldn't change the sr ratio
        srdebt = assessor.seniorDebt();
        log_named_uint("srdebt after loan       ", srdebt);
        srbal  = assessor.seniorBalance();
        log_named_uint("sr bal after loan       ", srdebt);
        log_named_uint("sr price after loan     ", assessor.calcSeniorTokenPrice());
        // accumulate debt
        hevm.warp(block.timestamp + 1 days);
        // interest is 5% a DAY!
        uint debt = pile.debt(loan);

        // give borrower some dai so they can repay
        Dai(dai).mint(address(borrower), debt - availablePost);
        borrower.doApproveCurrency(borrowerDeployer.shelf(), type(uint).max);
        borrower.repayAction(loan, debt);

        // now we can unwind mkr position
        log_named_uint("remainingCredit after repayment", clerk.remainingCredit());
        clerk.sink(allowedIncrease);

        srdebt = assessor.seniorDebt();
        log_named_uint("srdebt after repayment  ", srdebt);
        srbal  = assessor.seniorBalance();
        log_named_uint("sr bal after repayment  ", srbal);

        // canont redeem completely due to rounding errors
        seniorInvestorA.redeemOrder(99999999 * drop.balanceOf(address(seniorInvestorA)) / 100000000);
        juniorInvestorA.redeemOrder(99999999 *  tin.balanceOf(address(juniorInvestorA)) / 100000000);

        hevm.warp(block.timestamp + 1 days);
        coordinator.closeEpoch();
        assertTrue(!coordinator.submissionPeriod());

        seniorInvestorA.disburse();
        juniorInvestorA.disburse();

        // senior investor returns
        uint got = Dai(dai).balanceOf(address(seniorInvestorA));
        log_named_uint("sr investor A put in    ", rmul(amount * 1 ether, DEFAULT_SENIOR_RATIO));
        uint expected = rmul(amount * 1 ether, DEFAULT_SENIOR_RATIO) * 102 / 100;
        log_named_uint("with 2% interest, expect", expected);
        log_named_uint("amount received:        ", got);

        // junior investor returns
        uint jrgot = Dai(dai).balanceOf(address(juniorInvestorA));
        log_named_uint("jr investor A put in       ", rmul(amount * 1 ether, DEFAULT_JUNIOR_RATIO));
        uint expectedjr = debt - got - allowedIncrease;
        log_named_uint("remainder after drop payout", expectedjr);
        log_named_uint("amount received:           ", jrgot);

        assertLe(got - expected, 1 ether);
        assertLe(expectedjr - jrgot, 1 ether);
    }

    function testSolver() public {
        string memory dropInvest    = uint2str(6000000000000000000);
        string memory dropRedeem    = uint2str(0);
        string memory tinInvest     = uint2str(6000000000000000000);
        string memory tinRedeem     = uint2str(0);
        string memory netAssetValue = uint2str(990000000000000000000);
        string memory reserve       = uint2str(10000000000000000000);
        string memory seniorAsset   = uint2str(800000000000000000000);
        string memory minDropRatio  = uint2str(700000000000000000000000000);
        string memory maxDropRatio  = uint2str(850000000000000000000000000);
        string memory maxReserve    = uint2str(20000000000000000000);

        string[] memory inputs = new string[](12);
        inputs[0] = "node";
        inputs[1] = "lib/solver/index.js";
        inputs[2] = dropInvest;
        inputs[3] = dropRedeem;
        inputs[4] = tinInvest;
        inputs[5] = tinRedeem;
        inputs[6] = netAssetValue;
        inputs[7] = reserve;
        inputs[8] = seniorAsset;
        inputs[9] = minDropRatio;
        inputs[10] = maxDropRatio;
        inputs[11] = maxReserve;

        bytes memory ret = hevm.ffi(inputs);
        (bool isFeasible, uint dropInvest_, uint dropRedeem_, uint tinInvest_, uint tinRedeem_) = abi.decode(ret, (bool,uint,uint,uint,uint));
        assertTrue(isFeasible);
        assertEq(dropInvest_, 4000000000000000000);
        assertEq(dropRedeem_, 0);
        assertEq(tinInvest_, 6000000000000000000);
        assertEq(tinRedeem_, 0);
    }

    function testTokenPriceRoundingConcrete() public {
        testTokenPriceRounding(100);
    }

    // it is a lemma that as long as the pool has not been liquidated by maker:
    //   (drop.totalSupply() * dropPrice) + (tin.totalSupply * tinPrice) <= reserve.totalBalance() + NAV + juniorStake
    //
    // where:
    //   dropPrice == seniorAssets / drop.tokenSupply()
    //   tinPrice == (total assets - seniorAssets + junior stake) / tin.totalSupply()
    //   seniorAssets = senior debt + senior balance
    //
    // here we attempt to break the above lemma by finding cases where rdiv rounds up during token price calculation.
    function testTokenPriceRounding(uint128 supplyAmt) public {
        if (supplyAmt > assessor.maxReserve()) return;

        uint supplyAmt = 1000000 ether;
        uint loanAmt = rmul(supplyAmt, 0.9 ether * (10 ^ 9));
        log_named_uint("supplyAmt", supplyAmt);
        log_named_uint("loan", loanAmt);

        // supply some monies
        uint amountSenior = rmul(supplyAmt, DEFAULT_SENIOR_RATIO);
        uint amountSeniorA = amountSenior / 2;
        uint amountSeniorB = amountSenior - amountSeniorA;
        uint amountJunior = supplyAmt - amountSenior;

        Dai(dai).mint(address(seniorInvestorA), amountSeniorA);
        Dai(dai).mint(address(seniorInvestorB), amountSeniorB);
        Dai(dai).mint(address(juniorInvestorA), amountJunior);

        seniorInvestorA.supplyOrder(amountSeniorA);
        seniorInvestorB.supplyOrder(amountSeniorB);
        juniorInvestorA.supplyOrder(amountJunior);

        // close epoch and disburse
        hevm.warp(block.timestamp + 1 days);
        coordinator.closeEpoch();

        seniorInvestorA.disburse();
        seniorInvestorB.disburse();
        juniorInvestorA.disburse();

        // borrow some monies
        borrower.borrowAction(loan, loanAmt);

        // accumulate some interest
        hevm.warp(block.timestamp + 100 days);

        // seniorTokenPrice should be:
        // seniorDebt + seniorBalance / totalSupply
        uint srDebt = assessor.seniorDebt();
        uint srBal = assessor.seniorBalance();
        uint dropSupply = Tranche(lenderDeployer.seniorTranche()).tokenSupply();

        uint downPrice = safeMul(safeAdd(srDebt, srBal), ONE) / dropSupply;
        uint rdivPrice = assessor.calcSeniorTokenPrice();

        log_named_uint("seniorDebt", srDebt);
        log_named_uint("seniorBalance", srBal);
        log_named_uint("DROP Supply", dropSupply);

        log_named_uint("rounded down", downPrice);
        log_named_uint("with rdiv", rdivPrice);

        // repay the loan
        uint debt = pile.debt(loan);
        Dai(dai).mint(address(borrower), debt);
        borrower.doApproveCurrency(borrowerDeployer.shelf(), type(uint).max);
        borrower.repayAction(loan, debt);

        uint aExpects = rmul(drop.balanceOf(address(seniorInvestorA)), rdivPrice);
        uint bExpects = rmul(drop.balanceOf(address(seniorInvestorB)), rdivPrice);
        uint jrExpects = rmul(tin.balanceOf(address(juniorInvestorA)), assessor.calcJuniorTokenPrice());

        log_named_uint("investor A expects", aExpects);
        log_named_uint("investor B expects", bExpects);
        log_named_uint("jr investor expects", jrExpects);
        log_named_uint("required for all", aExpects + bExpects + jrExpects);
        log_named_uint("reserve balance", reserve.totalBalance());
        log_named_uint("required for all sr", aExpects + bExpects);
        log_named_uint("seniorBalancePost", assessor.seniorBalance());

        assertGe(reserve.totalBalance(), aExpects + bExpects + jrExpects, "not enough Dai for senior investors");
    }

    // what happens to a normal DROP investor when the maker integration is active?
    // can they still redeem?
    function testRedeemDropWhenMakerIsActive() public {
        // install mkr adapter
        reserve.depend("lending", address(clerk));

        // allow an all TIN pool
        root.relyContract(address(assessor), address(this));
        assessor.file("minSeniorRatio", 0);

        // invest TIN
        uint amountJunior = 100;
        Dai(dai).mint(address(juniorInvestorA), amountJunior);
        juniorInvestorA.supplyOrder(amountJunior);
        hevm.warp(block.timestamp + 1 days);
        coordinator.closeEpoch();
        juniorInvestorA.disburse();

        // increase maker credtline
        clerk.raise(150);

        log_named_uint("preloan: reserve.totalBalance()", reserve.totalBalance());
        log_named_uint("preloan: reserve.currencyAvailable()", reserve.currencyAvailable());
        log_named_uint("preloan: reserve.totalBalanceAvailable()", reserve.currencyAvailable());

        // borrow
        borrower.borrowAction(loan, 250);

        log_named_uint("postloan: reserve.totalBalance()", reserve.totalBalance());
        log_named_uint("postloan: reserve.currencyAvailable()", reserve.currencyAvailable());
        log_named_uint("postloan: reserve.totalBalanceAvailable()", reserve.totalBalanceAvailable());

        // supply via DROP
        uint amountSenior = 10;
        Dai(dai).mint(address(seniorInvestorA), amountSenior);
        seniorInvestorA.supplyOrder(amountSenior);
        hevm.warp(block.timestamp + 1 days);
        coordinator.closeEpoch();
        seniorInvestorA.disburse();

        log_named_uint("postsupply: reserve.totalBalance()", reserve.totalBalance());
        log_named_uint("postsupply: reserve.currencyAvailable()", reserve.currencyAvailable());
        log_named_uint("postsupply: reserve.totalBalanceAvailable()", reserve.totalBalanceAvailable());

        // borrow some more
        uint borrowAmt = 10;
        borrower.borrow(loan, borrowAmt);
        borrower.withdraw(loan, borrowAmt, address(borrower));

        // pay some back
        borrower.doApproveCurrency(borrowerDeployer.shelf(), type(uint).max);
        borrower.repay(loan, 100);

        log_named_uint("postrepay: reserve.totalBalance()", reserve.totalBalance());
        log_named_uint("postrepay: reserve.currencyAvailable()", reserve.currencyAvailable());
        log_named_uint("postrepay: reserve.totalBalanceAvailable()", reserve.totalBalanceAvailable());

        uint prebal = Dai(dai).balanceOf(address(seniorInvestorA));
        log_named_uint("prebal", prebal);
        assertEq(prebal, 0);

        // now attempt to redeem as a DROP investor
        seniorInvestorA.redeemOrder(drop.balanceOf(address(seniorInvestorA)));
        hevm.warp(block.timestamp + 1 days);
        coordinator.closeEpoch();
        seniorInvestorA.disburse();

        uint postbal = Dai(dai).balanceOf(address(seniorInvestorA));
        log_named_uint("postbal", postbal);
        // -1 because of rounding
        assertGe(postbal, amountSenior - 1);

        log_named_uint("postredeem: reserve.totalBalance()", reserve.totalBalance());
        log_named_uint("postredeem: reserve.currencyAvailable()", reserve.currencyAvailable());
        log_named_uint("postredeem: reserve.totalBalanceAvailable()", reserve.totalBalanceAvailable());
    }

    // what happens when maker decides to liquidate the pool?
    // function testMakerLiquidation(uint128 amountJunior, uint128 clerkAmount, uint128 borrow) public {
    //     if(    amountJunior + clerkAmount < borrow
    //         || amountJunior > assessor.maxReserve()
    //         || clerkAmount > assessor.maxReserve()
    //         || borrow > assessor.maxReserve()
    //       ) {
    //         return;
    //     }
    // fishy stuff
    function testMakerLiquidation() public {
        uint128 amountJunior =    811719427047073844116;
        uint128 clerkAmount  = 123619540332250687542738;
        uint128 borrow       =  45208525611983979667313;
        log_named_uint("amountJunior", amountJunior);
        log_named_uint("clerkAmount ", clerkAmount);
        log_named_uint("borrow      ", borrow);
        // install mkr adapter
        reserve.depend("lending", address(clerk));

        // allow an all TIN pool
        root.relyContract(address(assessor), address(this));
        assessor.file("minSeniorRatio", 0);

        // invest TIN
        // uint amountJunior = 100 - 1;
        Dai(dai).mint(address(juniorInvestorA), amountJunior);
        juniorInvestorA.supplyOrder(amountJunior);
        hevm.warp(block.timestamp + 1 days);
        coordinator.closeEpoch();
        juniorInvestorA.disburse();

        log_named_uint("nftprice         ", DEFAULT_NFT_PRICE);
        log_named_uint("calcOvercolAmount", clerk.calcOvercollAmount(clerkAmount));
        log_named_uint("protectionDAI    ", safeSub(clerk.calcOvercollAmount(clerkAmount), clerkAmount));
        log_named_int ("validate         ", clerk.validate( 0
                                                 , safeSub(clerk.calcOvercollAmount(clerkAmount), clerkAmount)
                                                 , clerk.calcOvercollAmount(clerkAmount)
                                                 , 0
                                                 ));
        log_named_uint("nav", assessor.getNAV());
        log_named_uint("assessor.totalBalance", assessor.totalBalance());
        log_named_uint("assessor.totalBalance", reserve.totalBalance());
        log_named_uint("remainingCredit", assessor.remainingCredit());

        uint seniorSupplyDAI = clerk.calcOvercollAmount(clerkAmount);
        uint juniorRedeemDAI = safeSub(clerk.calcOvercollAmount(clerkAmount), clerkAmount);

        uint newAssets = safeSub(safeSub(safeAdd(safeAdd(safeAdd(assessor.totalBalance(), assessor.getNAV()), seniorSupplyDAI),
            0), juniorRedeemDAI), 0);
        uint expectedSeniorAsset = assessor.calcExpectedSeniorAsset(0, seniorSupplyDAI,
            assessor.seniorBalance(), assessor.seniorDebt());
        log_named_uint("newAssets", newAssets);
        log_named_uint("expectedSeniorAsset", expectedSeniorAsset);


        // increase maker credtline
        clerk.raise(clerkAmount);
        log_named_uint("remainingCredit    ", clerk.remainingCredit());

        // borrow
        borrower.borrowAction(loan, borrow);

        // maker gov liquidates
        this.file(address(dssDeploy.vat()), ilk, "line", 0);
        oracle.tell(ilk);

        // cache some vars
        uint mgrDropPre = drop.balanceOf(address(mgr));
        uint tinPricePre = assessor.calcJuniorTokenPrice();
        uint dropPricePre = assessor.calcSeniorTokenPrice();
        uint juniorStakePre = clerk.juniorStake();

        // trigger a soft liquidation in the manager
        mgr.tell();

        // post mgr.tell() checks
        assertTrue(!clerk.mkrActive(), "clerk should be disabled now");
        assertEq(assessor.calcSeniorTokenPrice(), dropPricePre, "drop price has changed");
        assertEq(clerk.juniorStake(), 0, "juniorStake is not zero");
        assertEq(clerk.remainingCredit(), 0);
        assertEq(
            assessor.calcJuniorTokenPrice(),
            tinPricePre - rdiv(juniorStakePre, tin.totalSupply()),
            "tin price has not been reduced to cover the juniorStake"
        );

        // redeem order has been submitted
        Tranche senior = Tranche(lenderDeployer.seniorTranche());
        (uint orderdInEpoch, uint supplyAmt, uint redeemAmt) = senior.users(address(mgr));
        assertEq(orderdInEpoch, coordinator.currentEpoch());
        assertEq(redeemAmt, mgrDropPre);
        assertEq(supplyAmt, 0);

        // close the epoch :)
        hevm.warp(block.timestamp + 1 days);
        coordinator.closeEpoch();

        if(coordinator.submissionPeriod()) {
            // solve + execute the epoch
            solveEpoch();
            hevm.warp(coordinator.minChallengePeriodEnd());
            uint pre = coordinator.lastEpochExecuted();
            coordinator.executeEpoch();
            uint post = coordinator.lastEpochExecuted();
            assertEq(post, pre + 1, "could not execute epoch");

            Vat vat = dssDeploy.vat();
            (uint preInk, uint preArt) = vat.urns(ilk, address(urn));

            // mkr tries to get some monies back
            mgr.unwind(pre);

            // but there is nothing to give them so they get nothing
            (uint postInk, uint postArt) = vat.urns(ilk, address(urn));
            assertEq(preArt, postArt);
            assertEq(preInk, postInk);
        } else {
            hevm.warp(block.timestamp + 1 days);
            coordinator.closeEpoch();
        }

        // token price checks
        assertLe(
            rmul(drop.totalSupply(), assessor.calcSeniorTokenPrice()) + rmul(tin.totalSupply(), assessor.calcJuniorTokenPrice()),
            reserve.totalBalance() + feed.currentNAV(),
            "incorrect token prices"
        );
    }

    function solveEpoch() public returns (bool isFeasible, uint srSupply, uint srRedeem, uint jrSupply, uint jrRedeem) {
        Tranche senior = Tranche(lenderDeployer.seniorTranche());
        Tranche junior = Tranche(lenderDeployer.juniorTranche());

        string[] memory inputs = new string[](12);

        {
        string memory dropInvest    = uint2str(senior.totalSupply());
        string memory dropRedeem    = uint2str(senior.totalRedeem());
        string memory tinInvest     = uint2str(junior.totalSupply());
        string memory tinRedeem     = uint2str(junior.totalRedeem());
        string memory netAssetValue = uint2str(feed.currentNAV());

        // TODO: should this take the maker creditline into account?
        string memory reserve       = uint2str(reserve.totalBalance());

        string memory seniorAsset   = uint2str(assessor.seniorDebt_() + assessor.seniorBalance_());
        string memory minDropRatio  = uint2str(assessor.minSeniorRatio());
        string memory maxDropRatio  = uint2str(assessor.maxSeniorRatio());
        string memory maxReserve    = uint2str(assessor.maxReserve());

        inputs[0] = "node";
        inputs[1] = "lib/solver/index.js";
        inputs[2] = dropInvest;
        inputs[3] = dropRedeem;
        inputs[4] = tinInvest;
        inputs[5] = tinRedeem;
        inputs[6] = netAssetValue;
        inputs[7] = reserve;
        inputs[8] = seniorAsset;
        inputs[9] = minDropRatio;
        inputs[10] = maxDropRatio;
        inputs[11] = maxReserve;
        }

        (isFeasible, srSupply, srRedeem, jrSupply, jrRedeem) = abi.decode(hevm.ffi(inputs), (bool,uint,uint,uint,uint));

        int valid = coordinator.submitSolution(srRedeem, jrRedeem, jrSupply, srSupply);
        assertEq(uint(valid), 0, "not a valid solution");
        assertEq(coordinator.minChallengePeriodEnd(), block.timestamp + coordinator.challengeTime(), "wrong value for challenge period");
    }

    function priceNFTandSetRisk(uint tokenId, uint nftPrice, uint riskGroup) public {
        uint maturityDate = 600 days;
        lookupId = keccak256(abi.encodePacked(address(collateralNFT), tokenId));

        // -- authorize this contract
        root.relyContract(address(feed), address(this));

        // -- set price and risk
        feed.update(lookupId, nftPrice, riskGroup);
        // add default maturity date
        feed.file("maturityDate", lookupId , maturityDate);
    }

    function KYC(address usr) public {
        uint validUntil = block.timestamp + 700 days;
        jrMemberList.updateMember(usr, validUntil);
        srMemberList.updateMember(usr, validUntil);
    }

    function investBothTranchesProportionally(uint amount) public {
        uint amountSenior = rmul(amount, DEFAULT_SENIOR_RATIO);
        uint amountJunior = rmul(amount, DEFAULT_JUNIOR_RATIO);

        Dai(dai).mint(address(seniorInvestorA), amountSenior);
        Dai(dai).mint(address(juniorInvestorA), amountJunior);

        seniorInvestorA.supplyOrder(amountSenior);
        juniorInvestorA.supplyOrder(amountJunior);
        // close epoch and disburse
        hevm.warp(block.timestamp + 1 days);
        coordinator.closeEpoch();

        // we have approximately `amount` available for lending now
        uint available = reserve.currencyAvailable();
        assertLe(available, amount);

        // the precision loss should not be larger than a cent
        assertLt(amount - available, 0.01 ether);

        seniorInvestorA.disburse();
        juniorInvestorA.disburse();

    }

    function uint2str(uint _i) internal pure returns (string memory _uintAsString) {
          if (_i == 0) {
              return "0";
          }
          uint j = _i;
          uint len;
          while (j != 0) {
              len++;
              j /= 10;
          }
          bytes memory bstr = new bytes(len);
          uint k = len;
          while (_i != 0) {
              k = k-1;
              uint8 temp = (48 + uint8(_i - _i / 10 * 10));
              bytes1 b1 = bytes1(temp);
              bstr[k] = b1;
              _i /= 10;
          }
          return string(bstr);
      }
    function bytesToBytes32(bytes memory b, uint offset) private pure returns (bytes32) {
      bytes32 out;

      for (uint i = 0; i < 32; i++) {
        out |= bytes32(b[offset + i] & 0xFF) >> (i * 8);
      }
      return out;
    }

    function min(uint x, uint y) internal returns (uint) {
        if (x < y) return x;
        return y;
    }
}

contract TinlakeInvariants is Test {
  Actions actions;

  function setUp() override public {
    super.setUp();
    Dai(dai).mint(address(seniorInvestorA), 100 ether);
    //    Dai(dai).mint(address(seniorInvestorB), 80 ether);
    Dai(dai).mint(address(juniorInvestorA), 80 ether);
    actions = new Actions(this, coordinator, seniorInvestorA, juniorInvestorA, borrower, loan);
    targetContracts_.push(address(actions));

    // jump forwards in time to avoid an infinite loop in the navfeed
    hevm.warp(2 days);
  }

  // lets find some cases where srRatio goes above ONE
  function invariantSrRatio() public {
      assertLe(assessor.seniorRatio(), ONE);
  }

  // senior debt + senior reserves == drop supply * drop price
  function invariantSeniorAssets() public {
    (uint jrPrice, uint srPrice) = assessor.calcTokenPrices();
    uint dropSupply = Tranche(address(assessor.seniorTranche())).tokenSupply();

    assertEq(assessor.seniorDebt() + assessor.seniorBalance(), rmul(srPrice, dropSupply));
  }

  // value of all tokens == total assets (modulo rounding)
  function invariantTotalAssets() public {
    (uint jrPrice, uint srPrice) = assessor.calcTokenPrices();
    uint totalBalance = reserve.totalBalance();
    uint nav = feed.currentNAV();
    uint dropSupply = Tranche(address(assessor.seniorTranche())).tokenSupply();
    uint tinSupply = Tranche(address(assessor.juniorTranche())).tokenSupply();

    uint srSupply = Tranche(address(assessor.seniorTranche())).totalSupply();
    uint jrSupply = Tranche(address(assessor.juniorTranche())).totalSupply();

    // total assets according to the reserve & navfeed
    uint totalAssets = totalBalance + nav;

    // total assets according to the token prices
    uint tokenValue = rmul(dropSupply, srPrice) + rmul(tinSupply, jrPrice);

    // allow rounding error as long as the tokenValue is lt 10 wei lower than the totalAssets
    assertTrue(
        totalAssets >= tokenValue
        && totalAssets - tokenValue <= 10
    );

    // senior ratio should
    assertLe(assessor.seniorRatio(), ONE);

    log_named_uint("assessor.tokenBalance()", totalBalance);
    log_named_uint("feed.currentNAV()", nav);
    log_named_uint("jr price", jrPrice);
    log_named_uint("sr price", srPrice);
    log_named_uint("tin supply", tinSupply);
    log_named_uint("drop supply", dropSupply);
    log_named_uint("sr supply in this epoch", srSupply);
    log_named_uint("jr supply in this epoch", jrSupply);
    log_named_uint("current epoch", coordinator.currentEpoch());
    log_named_uint("last executed epoch", coordinator.lastEpochExecuted());
    log_named_uint("last closed epoch", coordinator.lastEpochClosed());
    log_named_uint("srRatio", assessor.seniorRatio());

    log_named_uint("totalAssets", totalAssets);
    log_named_uint("tokenValue", tokenValue);
  }

  function logState() public {
    (uint jrPrice, uint srPrice) = assessor.calcTokenPrices();
    uint dropSupply = Tranche(address(assessor.seniorTranche())).tokenSupply();
    uint tinSupply = Tranche(address(assessor.juniorTranche())).tokenSupply();
    uint srSupplied = Tranche(address(assessor.seniorTranche())).totalSupply();
    uint jrSupplied = Tranche(address(assessor.juniorTranche())).totalSupply();

    log_string("");
    log_string("----------------------------------------------------------------------");
    log_string("");
    log_named_uint("assessor.totalBalance()", assessor.totalBalance());
    log_named_uint("feed.currentNAV()", feed.currentNAV());
    log_named_uint("jr price", jrPrice);
    log_named_uint("sr price", srPrice);
    log_named_uint("tin supply", tinSupply);
    log_named_uint("drop supply", dropSupply);
    log_named_uint("sr supply in this epoch", srSupplied);
    log_named_uint("jr supply in this epoch", jrSupplied);
    log_named_uint("current epoch", coordinator.currentEpoch());
    log_named_uint("last executed epoch", coordinator.lastEpochExecuted());
    log_named_uint("last closed epoch", coordinator.lastEpochClosed());
    log_named_uint("srRatio", assessor.seniorRatio());
    log_named_uint("srDebt", assessor.seniorDebt());
    log_named_uint("lastUpdateSeniorInterest", assessor.lastUpdateSeniorInterest());
    log_string("");
    log_string("----------------------------------------------------------------------");
  }
}

contract Actions is DSTest {
  EpochCoordinator coordinator;
  Investor srInvest;
  Investor jrInvest;
  Borrower borrower;
  Test parent;
  uint loan;
  Hevm hevm;
  constructor(Test parent_, EpochCoordinator coordinator_, Investor a, Investor b, Borrower c, uint l) public {
    coordinator = coordinator_;
    parent = parent_;
    srInvest = a;
    jrInvest = b;
    borrower = c;
    loan = l;
    hevm = parent.hevm();
  }

  function closeEpoch() public {
    log_string("closeEpoch()");
    hevm.warp(block.timestamp + 1 days);
    coordinator.closeEpoch();
    if(coordinator.submissionPeriod()) {
      log_string("partial fulfillment");

      // solve + execute the epoch
      (bool feasible, uint srSupply, uint srRedeem, uint jrSupply, uint jrRedeem) = parent.solveEpoch();

      uint f;
      if (feasible) { f = 1; } else { f = 0; }
      log_named_uint("feasible", f);
      log_named_uint("srSupply", srSupply);
      log_named_uint("srRedeem", srRedeem);
      log_named_uint("jrSupply", jrSupply);
      log_named_uint("jrRedeem", jrRedeem);

      hevm.warp(coordinator.minChallengePeriodEnd());
      coordinator.executeEpoch();
    } else {
      log_string("full fulfillment");
    }
  }

  function smolInvestSr(uint8 amount) public {
    log_named_uint("smolInvestSr()", amount);
    srInvest.supplyOrder(amount * 1 ether);
  }

  function srdisburse() public {
    log_string("srdisburse()");
    srInvest.disburse();
  }

  function jrdisburse() public {
    log_string("jrdisburse()");
    jrInvest.disburse();
  }

  function goFarIntoFuture() public {
    log_string("goFarIntoFuture()");
    hevm.warp(block.timestamp + 60 days);
  }

  function repay(uint8 amount) public {
    log_named_uint("repay()", amount);
    borrower.repay(loan, amount * 1 ether);
  }

  function borrow(uint8 amount) public {
    log_named_uint("borrow()", amount);
    borrower.borrowAction(loan, amount * 1 ether);
  }

  function smolInvestJr(uint8 amount) public {
    log_named_uint("smolInvestJr()", amount);
    jrInvest.supplyOrder(amount * 1 ether);
  }
}
