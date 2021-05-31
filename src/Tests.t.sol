pragma solidity ^0.6.7;

import "ds-test/test.sol";

import "./Tests.sol";

contract TestsTest is DSTest {
    Tests tests;

    function setUp() public {
        tests = new Tests();
    }

    function testFail_basic_sanity() public {
        assertTrue(false);
    }

    function test_basic_sanity() public {
        assertTrue(true);
    }
}
