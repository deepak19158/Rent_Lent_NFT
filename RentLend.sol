// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Receiver.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import "./IResolver.sol";

contract NFT is ERC721Holder, ERC1155Receiver, ERC1155Holder {
    using SafeERC20 for ERC20;

    IResolver private resolver;
    address private admin;
    address payable private beneficiary;
    uint256 private lendingId = 0;
    uint256 public rentFee = 0;
    uint256 private constant SECONDS_IN_DAY = 86400;

    constructor(
        address _resolver,
        address payable _beneficiary,
        address _admin
    ) {
        resolver = IResolver(_resolver);
        beneficiary = _beneficiary;
        admin = _admin;
    }

    event Lended(
        address lenderAddress,
        address nft,
        uint256 tokenId,
        uint256 price
    );
    event Rented(
        address renterAddress,
        address nft,
        uint256 tokenId,
        uint256 collateral,
        uint256 rentPrice
    );

    struct Lending {
        address nft;
        uint256 token_id;
        uint256 nftPrice;
        uint256 maxRentDuration;
        uint256 dailyRentPrice;
        address lenderAddress;
        IResolver.PaymentToken paymentToken;
    }

    struct Renting {
        address renterAddress;
        uint256 rentDuration;
        uint256 rentedAt;
        uint256 totalPayment;
    }

    struct LendingRenting {
        Lending lending;
        Renting renting;
    }

    struct data {
        address nft;
        uint256 tokenId;
        uint256 lendingId;
        address lenderAddress;
        uint256 price;
        uint256 dailyRent;
        uint256 maxRentDuration;
        uint256 rentDuration;
        IResolver.PaymentToken paymentToken;
    }

    mapping(bytes32 => LendingRenting) public lendingRenting;

    event Lend(
        address indexed nftAddress,
        uint256 indexed tokenId,
        uint256 lendingId,
        address indexed lenderAddress,
        uint256 maxRentDuration,
        uint256 dailyRentPrice,
        uint256 nftPrice,
        IResolver.PaymentToken paymentToken
    );

    event Rent(
        uint256 lendingId,
        address indexed renterAddress,
        address indexed nftAddress,
        uint256 indexed tokenId,
        uint256 nftPrice,
        uint256 rentDuration,
        uint256 rentedAt
    );

    event Returned(uint256 indexed lendingId, uint32 returnedAt);

    //LEND FUNCTION

    function lend(address _nft,
            uint256 _tokenId,
            uint256 _price,
            uint256 _dailyRent,
            uint256 _maxRentDuration,
            IResolver.PaymentToken _paymentToken

        ) public {

            require(_nft!=address(0),"NFT address cant be 0.");
            
        require(_maxRentDuration > 0, "ReNFT::duration not zero");
        require(_dailyRent > 0, "ReNFT::rent price not zero");
        require(_price > 0, "ReNFT::nft price not zero");
        _maxRentDuration *= SECONDS_IN_DAY;

     data memory info = data({
            nft:_nft,
            tokenId:_tokenId,
            lendingId:lendingId,
            lenderAddress:msg.sender,
            price:_price,
            dailyRent:_dailyRent,
            rentDuration:0,
            maxRentDuration:_maxRentDuration,
            paymentToken: _paymentToken
        });

        LendingRenting storage item = lendingRenting[
            keccak256(abi.encodePacked(info.nft, info.tokenId, lendingId))
        ];

        item.lending = Lending({
            nft: info.nft,
            token_id: info.tokenId,
            lenderAddress: msg.sender,
            maxRentDuration: info.maxRentDuration,
            dailyRentPrice: info.dailyRent,
            nftPrice: info.price,
            paymentToken: info.paymentToken
        });

        IERC721(info.nft).transferFrom(
            info.lenderAddress,
            address(this),
            info.tokenId
        );

        emit Lend(
            info.nft,
            info.tokenId,
            lendingId,
            msg.sender,
            info.maxRentDuration,
            info.dailyRent,
            info.price,
            info.paymentToken
        );

        lendingId++;
    }

    //RENT FUNCTION
    

    function rent(
        address _nft,
        uint256 _tokenId,
        uint256 _lendingId,
        uint256 _rentDuration
    ) public {

        require(_nft!=address(0),"NFT address cant be 0.");
        require(_rentDuration > 0, "NFT::rent Duration not zero");
        _rentDuration *=SECONDS_IN_DAY;

         data memory info = data({
           nft:_nft,
            tokenId:_tokenId,
            lendingId:_lendingId,
            lenderAddress:address(0),
            price:0,
            dailyRent:0,
            rentDuration:_rentDuration,
            maxRentDuration:0,
            paymentToken:IResolver.PaymentToken(0)
        });

        LendingRenting storage item = lendingRenting[
            keccak256(abi.encodePacked(info.nft, info.tokenId, info.lendingId))
        ];
        // uint8 paymentTokenIx = uint8(item.lending.paymentToken);

        address paymentToken = resolver.getPaymentToken(uint8(item.lending.paymentToken)); 
        // uint256 decimals = ERC20(paymentToken).decimals();

        // uint256 scale = 10**decimals;
        uint256 rentPrice = info.rentDuration * item.lending.dailyRentPrice;

        uint256 nftPrice = item.lending.nftPrice;

        require(rentPrice > 0, "NFT:rent price is zero");
        require(nftPrice > 0, "NFT:nft price is zero");

        ERC20(paymentToken).safeTransferFrom(
            msg.sender,
            address(this),
            rentPrice + nftPrice
        );

        item.renting.renterAddress = msg.sender;
        item.renting.rentDuration = info.rentDuration;
        item.renting.rentedAt = uint32(block.timestamp);
        item.renting.totalPayment = rentPrice + nftPrice;

        IERC721(info.nft).transferFrom(address(this), msg.sender, info.tokenId);

        emit Rent(
            info.lendingId,
            msg.sender,
            info.nft,
            item.lending.token_id,
            item.lending.nftPrice,
            info.rentDuration,
            uint32(block.timestamp)
        );
    }

    //RETURN NFT FUNCTION

    function returnIt(
        address _nft,
        uint256 _tokenId,
        uint256 _lendingId
        ) public {
        
        require(_nft!=address(0),"NFT address cant be 0.");      

        data memory info =data({
            nft:_nft,
            tokenId:_tokenId,
            lendingId:_lendingId,
            lenderAddress:address(0),
            price:0,
            dailyRent:0,
            rentDuration:0,
            maxRentDuration:0,
            paymentToken:IResolver.PaymentToken(0)
        });

        LendingRenting storage item = lendingRenting[
            keccak256(abi.encodePacked(info.nft, info.tokenId, info.lendingId))
        ];

        require(item.renting.renterAddress==msg.sender, "only the render can return the NFT");
        require(item.lending.lenderAddress!=address(0),"NFT not found or Collateral has been claimed");

        distributePayments(item);        

        IERC721(info.nft).transferFrom(
            msg.sender,
            item.lending.lenderAddress,
            info.tokenId
        );

        emit Returned(info.lendingId, uint32(block.timestamp));

        delete item.lending;
        delete item.renting;
    }

    function claimCollateral(
        address _nft,
        uint256 _tokenId,
        uint256 _lendingId
        ) public {

        LendingRenting storage item = lendingRenting[
            keccak256(abi.encodePacked(_nft, _tokenId, _lendingId))
        ];

        require(item.lending.lenderAddress!=address(0),"Sorry, No data exist");
        require(msg.sender==item.lending.lenderAddress,"only lender can claim collateral");
        require(item.renting.rentedAt + item.renting.rentDuration < uint(block.timestamp),"Still under rentDuration");

        uint8 paymentTokenIx = uint8(item.lending.paymentToken);
        address paymentToken = resolver.getPaymentToken(paymentTokenIx);

        ERC20(paymentToken).safeTransfer(
            item.lending.lenderAddress,
            item.lending.nftPrice
        );

        delete item.lending;
        delete item.renting;
    }

    function unpackPrice(uint256 _price, uint256 _scale)
        public
        pure
        returns (uint256)
    {
        // ensureIsUnpackablePrice(_price, _scale);

        uint16 whole = uint16(_price);
        uint16 decimal = uint16((_price << 16));
        uint256 decimalScale = _scale / 10000;

        if (whole > 9999) {
            whole = 9999;
        }
        if (decimal > 9999) {
            decimal = 9999;
        }

        uint256 w = whole * _scale;
        uint256 d = decimal * decimalScale;
        uint256 price = w + d;

        return price;
    }

    function takeFee(uint256 _rent, IResolver.PaymentToken _paymentToken)
        private
        returns (uint256 fee)
    {
        fee = _rent * rentFee;
        fee /= 100;
        uint8 paymentTokenIx = uint8(_paymentToken);
        // ensureTokenNotSentinel(paymentTokenIx);
        ERC20 paymentToken = ERC20(resolver.getPaymentToken(paymentTokenIx));
        paymentToken.safeTransfer(beneficiary, fee);
    }

    function distributePayments(
        LendingRenting storage _lendingRenting
    ) private {
        uint8 paymentTokenIx = uint8(_lendingRenting.lending.paymentToken);
        // ensureTokenNotSentinel(paymentTokenIx);
        address paymentToken = resolver.getPaymentToken(paymentTokenIx);

        uint256 nftPrice = _lendingRenting.lending.nftPrice;
        uint256 rentPrice = _lendingRenting.renting.totalPayment - nftPrice;

        uint256 takenFee = takeFee(
            rentPrice,
            _lendingRenting.lending.paymentToken
        );

        ERC20(paymentToken).safeTransfer(
            _lendingRenting.lending.lenderAddress,
            rentPrice - takenFee
        );
        ERC20(paymentToken).safeTransfer(
            _lendingRenting.renting.renterAddress,
            nftPrice
        );
    }
}
