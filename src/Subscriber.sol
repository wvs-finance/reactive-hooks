// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import "forge-std/interfaces/IERC4626.sol";
import "@reactive/reactive-lib/abstract-base/AbstractReactive.sol";
import "@openzeppelin/utils/structs/EnumerableMap.sol";
import "@compose/diamond/LibDiamond.sol";

library Reactive{
    address payable constant SERVICE = payable(0x0000000000000000000000000000000000fffFfF);
}

interface ISubscriber{
    function initialize() external;
}

contract SubscriptionManager is AbstractPayer{
    uint256 internal constant REACTIVE_IGNORE = 0xa65f96fc951c35ead38878e0f0b7a3c744a6f5ccc1476b313353ce31712313ad;

    
    // NOTE: Manages subscriptions per account, only runs on reactve network
    
    // An account needs to add the funds required to mantain the subscription
    uint256 chainId;

    function initialize(uint256 _chainId) external{
        vendor = IPayable(Reactive.SERVICE);       
        addAuthorizedSender(Reactive.SERVICE);
        chainId = _chainId;
    }
//     function subscribe(address _subscriber, address _emitter, bytes32 eventSelector) external{
//         ISubscriptionService(vendor).subscribe(chainId, _emitter, eventSelector, topic_1, topic_2, topic_3);
//     }
}
type subscriber is address;
type emitter is address;
type eventSelector is bytes4;

library LibSubscriber{
    function subscribe(subscriber __self, emitter _emitter, eventSelector _eventSelector) internal{}
}
contract Subscriber is AbstractReactive{
    
    struct Event{
        address emitter;
        bytes32 eventSelector;
    }

    mapping(address account => Event _event) public subscriptions;
    mapping(address account => IERC4626 treasury) public accounting;
    // mapping(bytes32 eventSelector =>)
    // mapping(uint256 chainId => EnumerableMap.AddressToAddressMap );
    uint256 chainId;
    address callback;

    function initialize(uint256 _chainId, address _callback) external {
        chainId = _chainId;
        callback = _callback;
    }
    // INITIALIZED
    function subscribe(Event memory _event) external rnOnly {
        ISubscriptionService(service).subscribe(chainId, _event.emitter, uint256(_event.eventSelector), REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE);
        subscriptions[msg.sender] = _event;

    }

    function react(LogRecord calldata log) external vmOnly{
        if (
            log.chain_id == chainId &&
            log._contract == subscriptions[msg.sender].emitter && 
            bytes32(log.topic_0) == subscriptions[msg.sender].eventSelector
        ){

        }
    }


}