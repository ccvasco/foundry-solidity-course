// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "forge-std/Script.sol";                         // this is imported from lib/forge-std
import {SimpleStorage} from "../src/SimpleStorage.sol";     // .. dots are used to go down in direction, since we are in script, not src
contract DeploySimpleStorage is Script{                //inheritance
    function run() external returns(SimpleStorage) {
        vm.startBroadcast();  //vm is a keyword only used for foundry (cheatcode)
                                //vm not valid in solidity but we are inheriting it from Script
                                  //it gives command for everything after vm.start line to be sent to the RPC
        SimpleStorage simpleStorage = new SimpleStorage();
        vm.stopBroadcast();
        return simpleStorage;
    }                                                   
}                                                       
