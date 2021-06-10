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

// helpers to deal with ds-pause related beuracracy
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

    Hevm hevm = Hevm(HEVM_ADDRESS);

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

    function setUp() public {

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
        uint value = 400 ether;

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
            1 hours,        // challengeTime
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
        uint tokenId = collateralNFT.issue(address(borrower));
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
    }

    function testDefaultNoPayback() public {
        uint amount = 5 ether;
        uint loanAmt_ = 2.5 ether;
        uint loanAmt  = min(amount,  loanAmt_ * 1 ether);

        investBothTranchesProportionally(amount);

        // borrow as much as we can
        borrower.borrowAction(loan, loanAmt);
        uint srDebt = assessor.seniorDebt();
        uint srBal = assessor.seniorBalance();

        // accumulate debt
        // loan expires / enters default
        hevm.warp(block.timestamp + 21 days);

        // interest is 5% a DAY!
        uint debt = pile.debt(loan);
        pile.accrue(loan);

        // don't repay anything

        // investors redeem
        seniorInvestorA.redeemOrder(drop.balanceOf(address(seniorInvestorA)));
        juniorInvestorA.redeemOrder(tin.balanceOf(address(juniorInvestorA)));

        hevm.warp(block.timestamp + 1 days);

        coordinator.closeEpoch();
        assertTrue(coordinator.submissionPeriod());

        // solve + execute the epoch
        solveEpoch();
        hevm.warp(coordinator.minChallengePeriodEnd());
        uint pre = coordinator.lastEpochExecuted();
        coordinator.executeEpoch();

        seniorInvestorA.disburse();
        juniorInvestorA.disburse();

        log_named_uint("we took out a loan of",  loanAmt);
        log_named_uint("leading to a NAV of  ",  feed.currentNAV()); // nav should be 0 because the loan was not repaid
        log_named_uint("sr debt is ",  srDebt);
        log_named_uint("reserve bal", reserve.totalBalance());
        log_named_uint("jrRat is ",  assessor.calcJuniorRatio());
        log_named_uint("srRat is ",  assessor.seniorRatio());
        log_named_uint("repaid: ",  debt);

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
    }

    // this test has a loan that expires, but eventually gets repaid
    // but we repay it before closing the epoch.. 
    function testDefaultLoanMaturityPayback() public {
        uint amount = 5 ether;
        uint loanAmt_ = 2.5 ether;
        uint loanAmt  = min(amount,  loanAmt_ * 1 ether);

        investBothTranchesProportionally(amount);

        // borrow as much as we can
        borrower.borrowAction(loan, loanAmt);
        uint srBal = assessor.seniorBalance();

        // accumulate debt
        // loan expires / enters default
        hevm.warp(block.timestamp + 600 days);

        // don't write off the loan
        // coordinator.closeEpoch();

        // interest is 5% a DAY!
        // need to accrue
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

        log_named_uint("took out a loan of",  loanAmt);
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
    function testDefaultLoanMaturity() public {
        uint amount = 5 ether;
        uint loanAmt_ = 2.5 ether;
        uint loanAmt  = min(amount,  loanAmt_ * 1 ether);

        investBothTranchesProportionally(amount);

        // borrow as much as we can
        borrower.borrowAction(loan, loanAmt);
        uint srBal = assessor.seniorBalance();

        // accumulate debt
        // loan expires / enters default
        hevm.warp(block.timestamp + 600 days);

        // here the defaulting loan should get written off
        coordinator.closeEpoch();

        // interest is 5% a DAY!
        // need to accrue
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

        log_named_uint("took out a loan of",  loanAmt);
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

    function testInvestmentsReturnsNormal(uint amount, uint loanAmt_) public {
        amount *= 1 ether;
        uint loanAmt  = min(amount,  loanAmt_ * 1 ether);
        if (amount == 0) return;
        if (amount > assessor.maxReserve()) return;
        investBothTranchesProportionally(amount);
        // borrow as much as we can
        borrower.borrowAction(loan, loanAmt);
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
    function testMakerLiquidation() public {
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

        // borrow
        borrower.borrowAction(loan, 250);

        // maker gov liquidates
        this.file(address(dssDeploy.vat()), ilk, "line", 0);
        oracle.tell(ilk);

        // trigger a soft liquidation in the manager
        uint mgrDrop = drop.balanceOf(address(mgr));
        log_named_uint("mgrDrop", mgrDrop);
        mgr.tell();

        // redeem order has been submitted
        Tranche senior = Tranche(lenderDeployer.seniorTranche());
        (uint orderdInEpoch, uint supplyAmt, uint redeemAmt) = senior.users(address(mgr));
        assertEq(orderdInEpoch, coordinator.currentEpoch());
        assertEq(redeemAmt, mgrDrop);
        assertEq(supplyAmt, 0);

        // close the epoch :)
        hevm.warp(block.timestamp + 1 days);
        coordinator.closeEpoch();

        // we cannot fulfill all orders, so we enter a submissionPeriod
        assertTrue(coordinator.submissionPeriod());

        // solve + execute the epoch
        solveEpoch();

        hevm.warp(coordinator.minChallengePeriodEnd());
        uint pre = coordinator.lastEpochExecuted();
        coordinator.executeEpoch();
        uint post = coordinator.lastEpochExecuted();
        assertEq(post, pre + 1, "could not execute epoch");
    }

    function solveEpoch() public {
        Tranche senior = Tranche(lenderDeployer.seniorTranche());
        Tranche junior = Tranche(lenderDeployer.juniorTranche());

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
        (bool isFeasible, uint srSupply, uint srRedeem, uint jrSupply, uint jrRedeem) = abi.decode(ret, (bool,uint,uint,uint,uint));

        require(isFeasible, "epoch has no solution");

        coordinator.submitSolution(srRedeem, jrRedeem, srSupply, jrSupply);
        assertEq(coordinator.minChallengePeriodEnd(), block.timestamp + coordinator.challengeTime(), "wrong value for challenge period");
    }

    function priceNFTandSetRisk(uint tokenId, uint nftPrice, uint riskGroup) public {
        uint maturityDate = 600 days;
        bytes32 lookupId = keccak256(abi.encodePacked(address(collateralNFT), tokenId));

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


// 3 investors put in x_i dai
// a borrower borrows
// wait some time
// they repay their loan
// THERE SHOULD BE NO WAY FOR investor 0 to get more than
// x_0 * 1.03
