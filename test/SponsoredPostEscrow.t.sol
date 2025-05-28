// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/SponsoredPostEscrow.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockUSDC is ERC20 {
    constructor() ERC20("USD Coin", "USDC") {
        _mint(msg.sender, 1000000 * 10**6); // Mint 1M USDC
    }
}

contract SponsoredPostEscrowTest is Test {
    SponsoredPostEscrow public escrow;
    MockUSDC public usdc;
    
    address public requester = address(1);
    address public creator = address(2);
    address public randomUser = address(3);
    uint256 public constant AMOUNT = 100 * 10**6; // 100 USDC
    
    event SponsoredPostCreated(uint256 indexed postId, address requester, address creator, uint256 amount);
    event SponsoredPostAccepted(uint256 indexed postId);
    event SponsoredPostRejected(uint256 indexed postId);
    event FundsClaimed(uint256 indexed postId, address recipient, uint256 amount);
    event AutoRefunded(uint256 indexed postId, address requester, uint256 amount);
    
    function setUp() public {
        usdc = new MockUSDC();
        escrow = new SponsoredPostEscrow(address(usdc));
        
        // Fund requester with USDC
        usdc.transfer(requester, AMOUNT);
        
        // Approve escrow to spend requester's USDC
        vm.prank(requester);
        usdc.approve(address(escrow), AMOUNT);
    }
    
    function testCreateSponsoredPost() public {
        vm.prank(requester);
        vm.expectEmit(true, true, true, true);
        emit SponsoredPostCreated(0, requester, creator, AMOUNT);
        
        uint256 postId = escrow.createSponsoredPost(creator, AMOUNT);
        
        (address postRequester, address postCreator, uint256 postAmount, bool isClaimed, bool isAccepted,) = escrow.sponsoredPosts(postId);
        assertEq(postRequester, requester);
        assertEq(postCreator, creator);
        assertEq(postAmount, AMOUNT);
        assertEq(isClaimed, false);
        assertEq(isAccepted, false);
        assertEq(escrow.postExists(postId), true);
    }
    
    function test_RevertWhen_CreatePostWithZeroAmount() public {
        vm.prank(requester);
        vm.expectRevert("Amount must be greater than 0");
        escrow.createSponsoredPost(creator, 0);
    }
    
    function test_RevertWhen_CreatePostWithZeroAddress() public {
        vm.prank(requester);
        vm.expectRevert("Invalid creator address");
        escrow.createSponsoredPost(address(0), AMOUNT);
    }
    
    function test_RevertWhen_CreatePostForSelf() public {
        vm.prank(requester);
        vm.expectRevert("Cannot create post for yourself");
        escrow.createSponsoredPost(requester, AMOUNT);
    }
    
    function testAcceptSponsoredPost() public {
        // Create post
        vm.prank(requester);
        uint256 postId = escrow.createSponsoredPost(creator, AMOUNT);
        
        // Accept post
        vm.prank(creator);
        vm.expectEmit(true, false, false, false);
        emit SponsoredPostAccepted(postId);
        escrow.acceptSponsoredPost(postId);
        
        (,,,, bool isAccepted,) = escrow.sponsoredPosts(postId);
        assertEq(isAccepted, true);
    }
    
    function test_RevertWhen_AcceptExpiredPost() public {
        // Create post
        vm.prank(requester);
        uint256 postId = escrow.createSponsoredPost(creator, AMOUNT);
        
        // Fast forward 25 hours
        vm.warp(block.timestamp + 25 hours);
        
        // Try to accept expired post
        vm.prank(creator);
        vm.expectRevert("Post expired");
        escrow.acceptSponsoredPost(postId);
    }
    
    function test_RevertWhen_AcceptPostByNonCreator() public {
        // Create post
        vm.prank(requester);
        uint256 postId = escrow.createSponsoredPost(creator, AMOUNT);
        
        // Try to accept as random user
        vm.prank(randomUser);
        vm.expectRevert("Only creator can accept");
        escrow.acceptSponsoredPost(postId);
    }
    
    function test_RevertWhen_AcceptNonExistentPost() public {
        vm.prank(creator);
        vm.expectRevert("Post does not exist");
        escrow.acceptSponsoredPost(999);
    }
    
    function testRejectSponsoredPost() public {
        // Create post
        vm.prank(requester);
        uint256 postId = escrow.createSponsoredPost(creator, AMOUNT);
        
        // Reject post
        vm.prank(creator);
        vm.expectEmit(true, false, false, false);
        emit SponsoredPostRejected(postId);
        escrow.rejectSponsoredPost(postId);
    }
    
    function test_RevertWhen_RejectExpiredPost() public {
        // Create post
        vm.prank(requester);
        uint256 postId = escrow.createSponsoredPost(creator, AMOUNT);
        
        // Fast forward 25 hours
        vm.warp(block.timestamp + 25 hours);
        
        // Try to reject expired post
        vm.prank(creator);
        vm.expectRevert("Post expired");
        escrow.rejectSponsoredPost(postId);
    }
    
    function test_RevertWhen_RejectPostByNonCreator() public {
        // Create post
        vm.prank(requester);
        uint256 postId = escrow.createSponsoredPost(creator, AMOUNT);
        
        // Try to reject as random user
        vm.prank(randomUser);
        vm.expectRevert("Only creator can reject");
        escrow.rejectSponsoredPost(postId);
    }
    
    function testClaimFundsAfterAccept() public {
        // Create and accept post
        vm.prank(requester);
        uint256 postId = escrow.createSponsoredPost(creator, AMOUNT);
        
        vm.prank(creator);
        escrow.acceptSponsoredPost(postId);
        
        // Claim funds
        vm.prank(creator);
        vm.expectEmit(true, true, true, true);
        emit FundsClaimed(postId, creator, AMOUNT);
        escrow.claimFunds(postId);
        
        assertEq(usdc.balanceOf(creator), AMOUNT);
        (,,,bool isClaimed,,) = escrow.sponsoredPosts(postId);
        assertEq(isClaimed, true);
    }
    
    function testClaimFundsAfterReject() public {
        // Create and reject post
        vm.prank(requester);
        uint256 postId = escrow.createSponsoredPost(creator, AMOUNT);
        
        vm.prank(creator);
        escrow.rejectSponsoredPost(postId);
        
        // Claim funds
        vm.prank(requester);
        vm.expectEmit(true, true, true, true);
        emit FundsClaimed(postId, requester, AMOUNT);
        escrow.claimFunds(postId);
        
        assertEq(usdc.balanceOf(requester), AMOUNT);
        (,,,bool isClaimed,,) = escrow.sponsoredPosts(postId);
        assertEq(isClaimed, true);
    }
    
    function testAutoRefundExpiredPost() public {
        // Create post
        vm.prank(requester);
        uint256 postId = escrow.createSponsoredPost(creator, AMOUNT);
        
        // Fast forward 25 hours
        vm.warp(block.timestamp + 25 hours);
        
        // Auto refund
        vm.expectEmit(true, true, true, true);
        emit AutoRefunded(postId, requester, AMOUNT);
        escrow.checkAndRefundExpired(postId);
        
        assertEq(usdc.balanceOf(requester), AMOUNT);
        (,,,bool isClaimed,,) = escrow.sponsoredPosts(postId);
        assertEq(isClaimed, true);
    }
    
    function test_RevertWhen_AutoRefundNonExpiredPost() public {
        // Create post
        vm.prank(requester);
        uint256 postId = escrow.createSponsoredPost(creator, AMOUNT);
        
        // Try to auto refund before expiration
        vm.expectRevert("Post not expired");
        escrow.checkAndRefundExpired(postId);
    }
    
    function testCheckAndRefundMultiple() public {
        // Create multiple posts
        vm.prank(requester);
        uint256 postId1 = escrow.createSponsoredPost(creator, AMOUNT);
        
        // Fund requester with more USDC and approve
        usdc.transfer(requester, AMOUNT);
        vm.prank(requester);
        usdc.approve(address(escrow), AMOUNT);
        
        vm.prank(requester);
        uint256 postId2 = escrow.createSponsoredPost(creator, AMOUNT);
        
        // Fast forward 25 hours
        vm.warp(block.timestamp + 25 hours);
        
        // Auto refund multiple posts
        uint256[] memory postIds = new uint256[](2);
        postIds[0] = postId1;
        postIds[1] = postId2;
        
        escrow.checkAndRefundMultiple(postIds);
        
        assertEq(usdc.balanceOf(requester), AMOUNT * 2);
    }
    
    function testEmergencyWithdraw() public {
        // Create post
        vm.prank(requester);
        uint256 postId = escrow.createSponsoredPost(creator, AMOUNT);
        
        // Fast forward 31 days
        vm.warp(block.timestamp + 31 days);
        
        // Emergency withdraw
        escrow.emergencyWithdraw(postId);
        
        assertEq(usdc.balanceOf(requester), AMOUNT);
        (,,,bool isClaimed,,) = escrow.sponsoredPosts(postId);
        assertEq(isClaimed, true);
    }
    
    function test_RevertWhen_EmergencyWithdrawByNonOwner() public {
        // Create post
        vm.prank(requester);
        uint256 postId = escrow.createSponsoredPost(creator, AMOUNT);
        
        // Fast forward 31 days
        vm.warp(block.timestamp + 31 days);
        
        // Try emergency withdraw as non-owner
        vm.prank(randomUser);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", randomUser));
        escrow.emergencyWithdraw(postId);
    }
}