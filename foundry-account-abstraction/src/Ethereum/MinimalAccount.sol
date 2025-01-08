//SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

/*
 * at some point, EntryPoint.sol will call this contract. It will send the PackedUserOperation to our contract, as well as the userOpHash
 * missingAccountFunds is like a fee: the minimum you have to pay for the call to go through.
 *
 * We will set the signature as valid if it's the MinimalAccount owner. However this can be set to anything we'd like
 */

import {IAccount} from "lib/account-abstraction/contracts/interfaces/IAccount.sol";
import {PackedUserOperation} from "lib/account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {MessageHashUtils} from "lib/openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol";
import {ECDSA} from "lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import {SIG_VALIDATION_FAILED, SIG_VALIDATION_SUCCESS} from "lib/account-abstraction/contracts/core/Helpers.sol";
import {IEntryPoint} from "lib/account-abstraction/contracts/interfaces/IEntryPoint.sol";

contract MinimalAccount is IAccount, Ownable {
    ////////////////////////
    // Errors
    ////////////////////////
    error MinimalAccount__NotFromEntryPoint();
    error MinimalAccount__NotFromEntryPointOrOwner();
    error MinimalAccount__CallFailed(bytes);

    ////////////////////////
    // State Variables
    ////////////////////////

    IEntryPoint private immutable i_entryPoint;

    ////////////////////////
    // Modifiers
    ////////////////////////
    modifier requireFromEntryPoint() {
        if (msg.sender != address(i_entryPoint)) {
            revert MinimalAccount__NotFromEntryPoint();
        }
        _;
    }

    modifier requireFromEntryPointOrOWner() {
        if (msg.sender != address(i_entryPoint) && msg.sender != owner()) {
            revert MinimalAccount__NotFromEntryPointOrOwner();
        }
        _;
    }

    ////////////////////////
    // Functions
    ////////////////////////
    constructor(address entryPoint) Ownable(msg.sender) {
        i_entryPoint = IEntryPoint(entryPoint);
    }

    receive() external payable {}

    ////////////////////////
    // External Functions
    ////////////////////////
    function execute(address dest, uint256 value, bytes calldata functionData) external requireFromEntryPointOrOWner {
        (bool success, bytes memory result) = dest.call{value: value}(functionData);
        if (!success) {
            revert MinimalAccount__CallFailed(result);
        }
    }

    function validateUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash, uint256 missingAccountFunds)
        external
        requireFromEntryPoint
        returns (uint256 validationData)
    {
        validationData = _validateSignature(userOp, userOpHash);
        //ideally add nounce validation
        _payPrefund(missingAccountFunds);
        return validationData;
    }

    ////////////////////////
    // Internal Functions
    ////////////////////////

    //userOpHash is EIP-191 version. We need it to the correct format to do an ECDSA recover
    function _validateSignature(PackedUserOperation calldata userOp, bytes32 userOpHash)
        internal
        view
        returns (uint256 validationData)
    {
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(userOpHash);
        address signer = ECDSA.recover(userOpHash, userOp.signature); //with this signature and this data in this hash, who signed it?
        if (signer != owner()) {
            return SIG_VALIDATION_FAILED;
        }
        return SIG_VALIDATION_SUCCESS;
    }

    function _payPrefund(uint256 missingAccountFunds) internal {
        if (missingAccountFunds != 0) {
            (bool success,) = payable(msg.sender).call{value: missingAccountFunds, gas: type(uint256).max}("");
            (success);
        }
    }

    ///////////////////
    // Getters
    ///////////////////
}
