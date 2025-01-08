//SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

//all accounts in ZKSync follow the IAccount interface

/* Lifecycle of a zkSync type 113 (0x71) transaction: 
* -> msg.sender is Bootloader system contract
*
* PHASE 1 - VALIDATION
* 1. The user sends the transaction to the zkSync API client (sort of a light node that does the validation - prevents DoS on Main Node)
* 2. The zkSync API client checks to see the nonce is unique by querying the NonceHolder system contract (NonceHolder.sol)
* 3. The zkSync API client calls validateTransaction, which MUST update the nonce
* 4. The zkSync API client checks the nonce is updated
* 5. The zkSync API client calls payForTransaction, or prepareForPaymaster & validateAndPayForPaymasterTransaction
* 6. The zkSync API client verifies that the Bootloader has been paid.
*
* PHASE 2 - EXECUTION
* 7. The zkSync API client passes the validated transaction to the Main Node / Sequencer (as of today, they are the same)
* 8. The main node calls executeTransaction
* 9. If a paymaster was used, the postTransaction is called
* 
*
*
* To deploy a smart-contract in Ethereum, you merely send an Ethereum transaction containging the compiled code of the smart-contract without specifying any recipient. (forge create does this)
* On zkSync you have to call the create functions on the ContractDeployer contract.
* zkSync has a lot of the system contracts at specific addresses that govern a lot of the functionality in zkSync
* Deploying a contract in zkSync (forge create --zksync --legacy): call create function on ContractDeployer
 */

import {IAccount, ACCOUNT_VALIDATION_SUCCESS_MAGIC} from "lib/foundry-era-contracts/src/system-contracts/contracts/interfaces/IAccount.sol";
import {Transaction, MemoryTransactionHelper} from "lib/foundry-era-contracts/src/system-contracts/contracts/libraries/MemoryTransactionHelper.sol";
import {SystemContractsCaller} from "lib/foundry-era-contracts/src/system-contracts/contracts/libraries/SystemContractsCaller.sol";
import {NONCE_HOLDER_SYSTEM_CONTRACT, BOOTLOADER_FORMAL_ADDRESS, DEPLOYER_SYSTEM_CONTRACT} from "lib/foundry-era-contracts/src/system-contracts/contracts/Constants.sol";
import {INonceHolder} from "lib/foundry-era-contracts/src/system-contracts/contracts/interfaces/INonceHolder.sol";
import {Utils} from "lib/foundry-era-contracts/src/system-contracts/contracts/libraries/Utils.sol";
import {MessageHashUtils} from "lib/openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol";
import {ECDSA} from "lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";

contract ZKMinimalAccount is IAccount, Ownable {
    ///////////////////////////
    ///// Libraries
    ///////////////////////////
    using MemoryTransactionHelper for Transaction;


    ///////////////////////////
    ///// Errors
    ///////////////////////////
    error ZkMinimalAccount__NotEnoughBalance();
    error ZkMinimalAccount__NotFromBootLoader();
    error ZkMinimalAccount__ExecutionFailed();
    error ZkMinimalAccount__NotFromBootLoaderOrOwner();
    error ZkMinimalAccount__FailedToPay();
    error ZkMinimalAccount__InvalidSignature();


    ///////////////////////////
    ///// Modifiers
    ///////////////////////////
    modifier requireFromBootloader() {
        if (msg.sender != BOOTLOADER_FORMAL_ADDRESS) {
            revert ZkMinimalAccount__NotFromBootLoader();
        }
        _;
    }

    modifier requireFromBootloaderOrOwner() {
        if (msg.sender != BOOTLOADER_FORMAL_ADDRESS && msg.sender != owner()) {
            revert ZkMinimalAccount__NotFromBootLoaderOrOwner();
        }
        _;
    }
    ///////////////////////////
    ///// Functions
    ///////////////////////////
    constructor() Ownable(msg.sender) {}

    receive() external payable {}

    ///////////////////////////
    ///// External Functions
    ///////////////////////////

    /* 
    * @notice must increase thenonce
    * @notice must validate transaction (check the owner signed the tx)
    * @notice also check if we have enough money on our wallet
    *
     */
    function validateTransaction(bytes32 /*_txHash*/, bytes32 /*_suggestedSignedHash*/, Transaction memory _transaction)
        external
        payable
        requireFromBootloader
        returns (bytes4 magic) {
        return _validateTransaction(_transaction);
        }

    function executeTransaction(bytes32 /*_txHash*/, bytes32 /*_suggestedSignedHash*/, Transaction memory _transaction)
        external
        payable
        requireFromBootloaderOrOwner {
            _executeTransaction(_transaction);          
        }

    // There is no point in providing possible signed hash in the `executeTransactionFromOutside` method,
    // since it typically should not be trusted.
    function executeTransactionFromOutside(Transaction memory _transaction) external payable {   //no bootloader stuff, no account abstraction stuff
        bytes4 magic = _validateTransaction(_transaction);
        if (magic != ACCOUNT_VALIDATION_SUCCESS_LOGIC) {
            revert ZkMinimalAccount__InvalidSignature();
        }
        _executeTransaction(_transaction);
    }


    function payForTransaction(bytes32 /*_txHash*/, bytes32 /*_suggestedSignedHash*/, Transaction memory _transaction)
        external
        payable {
            bool success = _transaction.payToTheBootloader();
            if (!success) {
                revert ZkMinimalAccount__FailedToPay();
            }
        }

    function prepareForPaymaster(bytes32 _txHash, bytes32 _possibleSignedHash, Transaction memory _transaction)
        external
        payable {}

    ///////////////////////////
    ///// Internal Functions
    ///////////////////////////
    function _validateTransaction(Transaction memory _transaction) internal returns (bytes4 magic) {
        // call NonceHolder
        // increment nonce
        // call(x, y, z) -> system contract call
            SystemContractsCaller.systemCallWithPropagatedRevert(uint32(gasleft()), address(NONCE_HOLDER_SYSTEM_CONTRACT), 0, abi.encodeCall(INonceHolder.incrementMinNonceIfEquals, (_transaction.nonce)));
        
        //check for fee to pay 
        uint256 totalRequiredBalance = _transaction.totalRequiredBalance(); //totalRequiredBalance() calculates the fees necessary for some object, in this case _transaction
        if (totalRequiredBalance > address(this).balance) {
            revert ZkMinimalAccount__NotEnoughBalance();
        }

        //check the signature
        bytes32 txHash = _transaction.encodeHash();
        // bytes32 convertedHash = MessageHashUtils.toEthSignedMessageHash(txHash);
        address signer = ECDSA.recover(txHash, _transaction.signature);
        bool isValidSigner = (signer == owner());
        if (isValidSigner) {
            magic = ACCOUNT_VALIDATION_SUCCESS_MAGIC;
        } else {
            magic = bytes4(0);
        }
        //return the magic number
        return magic;
    }

    function _executeTransaction(Transaction memory _transaction) internal {
        address to = address(uint160(_transaction.to));
        uint128 value = Utils.safeCastToU128(_transaction.value);
        bytes memory data = _transaction.data;

        if (to == address(DEPLOYER_SYSTEM_CONTRACT)) {
            uint32 gas = Utils.safeCastToU32(gasleft());
            SystemContractsCaller.systemCallWithPropagatedRevert(gas, to, value, data);
        } else {
            bool success;
            assembly {
                success := call(gas(), to, value, add(data, 0x20), mload(data), 0, 0)   // same as but in lower level: (bool success, bytes memory result) = dest.call{value: value}(functionData);
            }
            if (!success) {
                revert ZkMinimalAccount__ExecutionFailed();
            }}  
    }
}