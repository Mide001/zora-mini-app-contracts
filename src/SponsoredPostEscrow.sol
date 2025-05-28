// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract SponsoredPostEscrow is ReentrancyGuard, Pausable, Ownable {
    IERC20 public usdc;

    struct SponsoredPost {
        address requester;
        address creator;
        uint256 amount;
        bool isClaimed;
        bool isAccepted;
        uint256 createdAt;
    }

    mapping(uint256 => SponsoredPost) public sponsoredPosts;
    uint256 public nextPostId;
    mapping(uint256 => bool) public postExists;

    uint256 public constant AUTO_REFUND_DURATION = 24 hours;

    event SponsoredPostCreated(
        uint256 indexed postId,
        address requester,
        address creator,
        uint256 amount
    );
    event SponsoredPostAccepted(uint256 indexed postId);
    event SponsoredPostRejected(uint256 indexed postId);
    event FundsClaimed(
        uint256 indexed postId,
        address recipient,
        uint256 amount
    );
    event AutoRefunded(
        uint256 indexed postId,
        address requester,
        uint256 amount
    );

    constructor(address _usdcAddress) Ownable(msg.sender) {
        usdc = IERC20(_usdcAddress);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function createSponsoredPost(
        address _creator,
        uint256 _amount
    ) external nonReentrant whenNotPaused returns (uint256) {
        require(_amount > 0, "Amount must be greater than 0");
        require(_creator != address(0), "Invalid creator address");
        require(_creator != msg.sender, "Cannot create post for yourself");

        require(
            usdc.transferFrom(msg.sender, address(this), _amount),
            "USDC transfer failed"
        );

        uint256 postId = nextPostId++;
        sponsoredPosts[postId] = SponsoredPost({
            requester: msg.sender,
            creator: _creator,
            amount: _amount,
            isClaimed: false,
            isAccepted: false,
            createdAt: block.timestamp
        });

        postExists[postId] = true;

        emit SponsoredPostCreated(postId, msg.sender, _creator, _amount);
        return postId;
    }

    function acceptSponsoredPost(
        uint256 _postId
    ) external nonReentrant whenNotPaused {
        require(postExists[_postId], "Post does not exist");
        SponsoredPost storage post = sponsoredPosts[_postId];

        require(msg.sender == post.creator, "Only creator can accept");
        require(!post.isClaimed, "Post already claimed");
        require(!post.isAccepted, "Post already accepted");
        require(
            block.timestamp <= post.createdAt + AUTO_REFUND_DURATION,
            "Post expired"
        );

        post.isAccepted = true;
        emit SponsoredPostAccepted(_postId);
    }

    function rejectSponsoredPost(
        uint256 _postId
    ) external nonReentrant whenNotPaused {
        require(postExists[_postId], "Post does not exist");
        SponsoredPost storage post = sponsoredPosts[_postId];

        require(msg.sender == post.creator, "Only creator can reject");
        require(!post.isClaimed, "Post already claimed");
        require(!post.isAccepted, "Post already accepted");
        require(
            block.timestamp <= post.createdAt + AUTO_REFUND_DURATION,
            "Post expired"
        );

        emit SponsoredPostRejected(_postId);
    }

    function claimFunds(uint256 _postId) external nonReentrant whenNotPaused {
        require(postExists[_postId], "Post does not exist");
        SponsoredPost storage post = sponsoredPosts[_postId];

        require(!post.isClaimed, "Funds already claimed");

        if (post.isAccepted) {
            require(
                msg.sender == post.creator,
                "Only creator can claim accepted post"
            );
            require(
                usdc.transfer(post.creator, post.amount),
                "Transfer failed"
            );
        } else {
            require(
                msg.sender == post.requester,
                "Only requester can claim rejected post"
            );
            require(
                usdc.transfer(post.requester, post.amount),
                "Transfer failed"
            );
        }

        post.isClaimed = true;
        emit FundsClaimed(_postId, msg.sender, post.amount);
    }

    // Function to check and refund expired posts
    function checkAndRefundExpired(
        uint256 _postId
    ) external nonReentrant whenNotPaused {
        require(postExists[_postId], "Post does not exist");
        SponsoredPost storage post = sponsoredPosts[_postId];

        require(!post.isClaimed, "Post already claimed");
        require(!post.isAccepted, "Post already accepted");
        require(
            block.timestamp > post.createdAt + AUTO_REFUND_DURATION,
            "Post not expired"
        );

        post.isClaimed = true;
        require(usdc.transfer(post.requester, post.amount), "Transfer failed");

        emit AutoRefunded(_postId, post.requester, post.amount);
    }

    // Function to check multiple posts for expiration
    function checkAndRefundMultiple(
        uint256[] calldata _postIds
    ) external nonReentrant whenNotPaused {
        for (uint256 i = 0; i < _postIds.length; i++) {
            uint256 postId = _postIds[i];
            if (postExists[postId]) {
                SponsoredPost storage post = sponsoredPosts[postId];

                if (
                    !post.isClaimed &&
                    !post.isAccepted &&
                    block.timestamp > post.createdAt + AUTO_REFUND_DURATION
                ) {
                    post.isClaimed = true;
                    require(
                        usdc.transfer(post.requester, post.amount),
                        "Transfer failed"
                    );
                    emit AutoRefunded(postId, post.requester, post.amount);
                }
            }
        }
    }

    // Emergency function to recover stuck funds (only owner)
    function emergencyWithdraw(uint256 _postId) external onlyOwner {
        require(postExists[_postId], "Post does not exist");
        SponsoredPost storage post = sponsoredPosts[_postId];

        require(!post.isClaimed, "Funds already claimed");
        require(
            block.timestamp > post.createdAt + 30 days,
            "Too early for emergency withdrawal"
        );

        require(usdc.transfer(post.requester, post.amount), "Transfer failed");
        post.isClaimed = true;
    }
}
