// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.6.12;

import {DSTest} from "ds-test/test.sol";
import {Dai} from "dss/dai.sol";
import {TinlakeRoot} from "tinlake/root.sol";
import {LenderDeployer} from "tinlake/lender/deployer.sol";
import {BorrowerDeployer} from "tinlake/borrower/deployer.sol";

import {TrancheFab} from "tinlake/lender/fabs/tranche.sol";
import {MemberlistFab} from "tinlake/lender/fabs/memberlist.sol";
import {RestrictedTokenFab} from "tinlake/lender/fabs/restrictedtoken.sol";
import {ReserveFab} from "tinlake/lender/fabs/reserve.sol";
import {AssessorFab} from "tinlake/lender/fabs/assessor.sol";
import {CoordinatorFab} from "tinlake/lender/fabs/coordinator.sol";
import {OperatorFab} from "tinlake/lender/fabs/operator.sol";
import {AssessorAdminFab} from "tinlake/lender/fabs/assessoradmin.sol";

import {TitleFab} from "tinlake/borrower/fabs/title.sol";
import {ShelfFab} from "tinlake/borrower/fabs/shelf.sol";
import {PileFab} from "tinlake/borrower/fabs/pile.sol";
import {CollectorFab} from "tinlake/borrower/fabs/collector.sol";
import {NAVFeedFab} from "tinlake/borrower/fabs/navfeed.sol";

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

contract Test is DSTest {
    TinlakeRoot root;
    LenderDeployer lenderDeployer;
    BorrowerDeployer borrowerDeployer;
    DssDeploy dssDeploy;

    bytes32 constant ilkId = bytes32("DROP-A");

    function setUp() public {

        // -- deploy mcd --

        uint chainId = 1;
        uint pauseDelay = 0;
        uint esmThreshold = 0;
        address gov = address(this);

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
        dssDeploy.deployPause(pauseDelay, gov);
        dssDeploy.deployESM(gov, esmThreshold);
        dssDeploy.releaseAuth();

        // -- deploy tinlake --

        root = new TinlakeRoot(address(this));

        lenderDeployer = new LenderDeployer(
            address(root),
            address(dssDeploy.dai()),
            address(new TrancheFab()),
            address(new MemberlistFab()),
            address(new RestrictedTokenFab()),
            address(new ReserveFab()),
            address(new AssessorFab()),
            address(new CoordinatorFab()),
            address(new OperatorFab()),
            address(new AssessorAdminFab())
        );

        // TODO: set these to sensible values...
        lenderDeployer.init(
            0,             // minSeniorRatio
            1,             // maxSeniorRatio
            1000000 ether, // maxReserve
            1 days,        // challengeTime
            1,             // seniorInterestRate
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
        lenderDeployer.deploy();

        borrowerDeployer = new BorrowerDeployer(
            address(root),
            address(new TitleFab()),
            address(new ShelfFab()),
            address(new PileFab()),
            address(new CollectorFab()),
            address(new NAVFeedFab()),
            address(dssDeploy.dai()),
            "title",
            "TTL",
            0 // TODO: wtf is a discount rate?
        );

        borrowerDeployer.deployTitle();
        borrowerDeployer.deployPile();
        borrowerDeployer.deployFeed();
        borrowerDeployer.deployShelf();
        borrowerDeployer.deployCollector();
        borrowerDeployer.deploy();

        root.prepare(address(lenderDeployer), address(borrowerDeployer), address(this));
        root.deploy();

        // -- add drop as a collateral type --

        //dss.deployCollateralFlip(ilkId, address join, address pip);
        //dss.deployCollateralClip(ilkId, address join, address pip, address calc);
        //releaseAuthFlip(bytes32 ilk);
        //releaseAuthClip(bytes32 ilk);
    }

    function test_nothing() public {
        assertTrue(true);
    }
}
