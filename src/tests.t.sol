// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.6.12;

import {DSTest} from "ds-test/test.sol";
import {Math} from "tinlake-math/math.sol";
import {Dai} from "dss/dai.sol";
import {TinlakeRoot} from "tinlake/root.sol";
import {LenderDeployer} from "tinlake/lender/deployer.sol";
import {BorrowerDeployer} from "tinlake/borrower/deployer.sol";
import {TinlakeManager} from "tinlake-maker-lib/mgr.sol";

import {TrancheFab} from "tinlake/lender/fabs/tranche.sol";
import {MemberlistFab, Memberlist} from "tinlake/lender/fabs/memberlist.sol";
import {RestrictedTokenFab} from "tinlake/lender/fabs/restrictedtoken.sol";
import {ReserveFab, Reserve} from "tinlake/lender/fabs/reserve.sol";
import {AssessorFab, Assessor} from "tinlake/lender/fabs/assessor.sol";
import {CoordinatorFab, EpochCoordinator} from "tinlake/lender/fabs/coordinator.sol";
import {OperatorFab} from "tinlake/lender/fabs/operator.sol";
import {AssessorAdminFab} from "tinlake/lender/fabs/assessoradmin.sol";
import {ClerkFab} from "tinlake/lender/adapters/mkr/fabs/clerk.sol";
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
}

// helpers to deal with ds-pause related beuracracy
contract ProxyActions {
    DSPause pause;
    GovActions govActions;

    function rely(address from, address to) external {
        address      usr = address(govActions);
        bytes32      tag;  assembly { tag := extcodehash(usr) }
        bytes memory fax = abi.encodeWithSignature("rely(address,address)", from, to);
        uint         eta = now;

        pause.plot(usr, tag, fax, eta);
        pause.exec(usr, tag, fax, eta);
    }

    function file(address who, bytes32 ilk, bytes32 what, uint256 data) external {
        address      usr = address(govActions);
        bytes32      tag;  assembly { tag := extcodehash(usr) }
        bytes memory fax = abi.encodeWithSignature("file(address,bytes32,bytes32,uint256)", who, ilk, what, data);
        uint         eta = now;

        pause.plot(usr, tag, fax, eta);
        pause.exec(usr, tag, fax, eta);
    }

    function file(address who, bytes32 ilk, bytes32 what, address data) external {
        address      usr = address(govActions);
        bytes32      tag;  assembly { tag := extcodehash(usr) }
        bytes memory fax = abi.encodeWithSignature("file(address,bytes32,bytes32,address)", who, ilk, what, data);
        uint         eta = now;

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

        root = new TinlakeRoot(address(this));

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
            address(new AssessorAdminFab()),
            address(new ClerkFab())
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
        lenderDeployer.deployAssessorAdmin();
        lenderDeployer.deployCoordinator();
        lenderDeployer.deployClerk();

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

        root.prepare(address(lenderDeployer), address(borrowerDeployer), address(this));
        root.deploy();

        // -- create borrower user --

        borrower = new Borrower(borrowerDeployer.shelf(),
                                address(reserve),
                                borrowerDeployer.currency(),
                                borrowerDeployer.pile());

        // set up and price the nft collateral
        uint tokenId = collateralNFT.issue(address(borrower));
        feed = NAVFeed(borrowerDeployer.feed());
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
        KYC(address(juniorInvestorA));
    }

    function testInvestmentsReturns(uint128 amount) public {
        if (amount * 1 ether > assessor.maxReserve()) return;
          investBothTranches(amount * 1 ether);
          // close epoch
          hevm.warp(block.timestamp + 1 days);
          coordinator.closeEpoch();

          // 1 wei can be lost due to rounding errs.
          uint available = reserve.currencyAvailable();
          // borrow all of it
          borrower.borrowAction(loan, available);
          // accumulate debt
          hevm.warp(block.timestamp + 1 days);
          // interest is 5% a DAY!
          uint debt = pile.debt(loan);

          // give borrower some dai so they can repay
          Dai(dai).mint(address(borrower), debt - available);
          borrower.doApproveCurrency(borrowerDeployer.shelf(), type(uint).max);
          borrower.repayAction(loan, debt);

          // investor exits
          seniorInvestorA.disburse();
          juniorInvestorA.disburse();

          // TODO: why can they not redeem completely? (coordinator won't execute epoch directly)
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
          log_named_uint("jr investor A put in    ", rmul(amount * 1 ether, DEFAULT_JUNIOR_RATIO));
          uint expectedjr = debt - got;
          log_named_uint("remainder after drop payout", expectedjr);
          log_named_uint("amount received:        ", jrgot);

          assertLe(got - expected, 1 ether);
          assertLe(expectedjr - jrgot, 1 ether);
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
        uint validUntil = block.timestamp + 200 days;
        jrMemberList.updateMember(usr, validUntil);
        srMemberList.updateMember(usr, validUntil);
    }

    function investBothTranches(uint currencyAmount) public {
        uint amountSenior = rmul(currencyAmount, DEFAULT_SENIOR_RATIO);
        uint amountJunior = rmul(currencyAmount, DEFAULT_JUNIOR_RATIO);

        Dai(dai).mint(address(seniorInvestorA), amountSenior);
        Dai(dai).mint(address(juniorInvestorA), amountJunior);

        seniorInvestorA.supplyOrder(amountSenior);
        juniorInvestorA.supplyOrder(amountJunior);
    }
}


// 3 investors put in x_i dai
// a borrower borrows
// wait some time
// they repay their loan
// THERE SHOULD BE NO WAY FOR investor 0 to get more than
// x_0 * 1.03
