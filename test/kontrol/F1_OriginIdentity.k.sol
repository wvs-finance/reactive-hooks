// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {OriginEndpoint, originId} from "../../src/types/OriginEndpoint.sol";

/// @dev Kontrol formal verification proofs for OriginEndpoint identity (INV-001, INV-002, INV-003).
contract F1_OriginIdentityProof is Test {
    /// @dev INV-001: originId is deterministic — same inputs always produce same output.
    /// @notice Named test_prove_ so Foundry recognizes it as a fuzz test AND Kontrol recognizes it as a proof.
    function test_prove_originId_deterministic(
        uint32 chainId,
        address emitter,
        bytes32 eventSig
    ) public pure {
        OriginEndpoint memory a = OriginEndpoint(chainId, emitter, eventSig);
        OriginEndpoint memory b = OriginEndpoint(chainId, emitter, eventSig);
        assert(a.originId() == b.originId());
    }

    /// @dev INV-002a: originId is injective over chainId.
    function test_prove_originId_injective_chainId(
        uint32 chainId1,
        uint32 chainId2,
        address emitter,
        bytes32 eventSig
    ) public pure {
        vm.assume(chainId1 != chainId2);
        OriginEndpoint memory a = OriginEndpoint(chainId1, emitter, eventSig);
        OriginEndpoint memory b = OriginEndpoint(chainId2, emitter, eventSig);
        assert(a.originId() != b.originId());
    }

    /// @dev INV-002b: originId is injective over emitter.
    function test_prove_originId_injective_emitter(
        uint32 chainId,
        address emitter1,
        address emitter2,
        bytes32 eventSig
    ) public pure {
        vm.assume(emitter1 != emitter2);
        OriginEndpoint memory a = OriginEndpoint(chainId, emitter1, eventSig);
        OriginEndpoint memory b = OriginEndpoint(chainId, emitter2, eventSig);
        assert(a.originId() != b.originId());
    }

    /// @dev INV-002c: originId is injective over eventSig.
    function test_prove_originId_injective_eventSig(
        uint32 chainId,
        address emitter,
        bytes32 eventSig1,
        bytes32 eventSig2
    ) public pure {
        vm.assume(eventSig1 != eventSig2);
        OriginEndpoint memory a = OriginEndpoint(chainId, emitter, eventSig1);
        OriginEndpoint memory b = OriginEndpoint(chainId, emitter, eventSig2);
        assert(a.originId() != b.originId());
    }

    /// @dev INV-003: originId has no zero-image — no valid OriginEndpoint maps to bytes32(0).
    function test_prove_originId_no_zero_image(
        uint32 chainId,
        address emitter,
        bytes32 eventSig
    ) public pure {
        OriginEndpoint memory e = OriginEndpoint(chainId, emitter, eventSig);
        assert(e.originId() != bytes32(0));
    }
}
