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
import {NFTFeedFab} from "tinlake/borrower/fabs/nftfeed.sol";

contract Test is DSTest {
    TinlakeRoot root;
    LenderDeployer lenderDeployer;
    BorrowerDeployer borrowerDeployer;
    Dai dai;

    function setUp() public {
        uint chainId = 1;

        dai = new Dai(chainId);
        root = new TinlakeRoot(address(this));

        lenderDeployer = new LenderDeployer(
            address(root),
            address(dai),
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
            0, // minSeniorRatio
            1, // maxSeniorRatio
            1000000 ether, //maxReserve
            1 days, // challengeTime
            1, // seniorInterestRate
            "Tin", // seniorName
            "TIN", // seniorSymbol
            "DROP", // juniorName
            "DRP" // juniorSymbol
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
            address(new NFTFeedFab()),
            address(dai),
            "title",
            "TTL",
            0 // TODO: wtf is a discount rate?
        );

        borrowerDeployer.deployCollector();
        borrowerDeployer.deployPile();
        borrowerDeployer.deployTitle();
        borrowerDeployer.deployShelf();
        borrowerDeployer.deployFeed();
        borrowerDeployer.deploy();

        root.prepare(address(lenderDeployer), address(borrowerDeployer), address(this));
        root.deploy();
    }

    function test_nothing() public {
        assertTrue(true);
    }
}
