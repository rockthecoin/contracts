// TEP-74, TEP-89 and TEP-62 message layouts. See NOTICE for reference sources.
tolk 1.5

struct (0x52544301) LaunchCreation { queryId: uint64 }
struct (0x52544302) RetrySettlement { queryId: uint64 }
struct (0x52544303) RetryMintReceipt { queryId: uint64 }
struct (0x52544304) RefundExcess { queryId: uint64 }
struct (0x00000000) ServicePayment { queryId: uint64; quoteId: uint256 }
struct (0xd372158c) TopUpTons {}
struct (0x52544310) FactoryLaunch { signature: bits512; terms: Cell<LaunchTerms> }
struct LaunchTerms {
    domain: uint32
    quoteId: uint256
    creator: address
    deadline: uint32
    value: coins
    endpoints: Cell<LaunchEndpoints>
    template: Cell<LaunchTemplate>
}
struct LaunchEndpoints { factory: address; treasury: address }
struct LaunchTemplate { code: cell; data: cell }
struct (0x52544311) FactoryReceipt { queryId: uint64 }
struct (0x52544312) ConfigureService { queryId: uint64; treasury: address; signer: uint256; paused: bool }
struct (0x52544320) MintTokens { queryId: uint64; amount: coins; recipient: address }
struct (0x52544321) SetPause { queryId: uint64; paused: bool }
struct (0x52544322) CloseMinting { queryId: uint64 }
struct (0x52544323) SetMetadata { queryId: uint64; content: cell }
struct (0x52544324) FreezeMetadata { queryId: uint64 }
struct (0x52544325) ProposeOwner { queryId: uint64; owner: address }
struct (0x52544326) AcceptOwner { queryId: uint64 }
struct (0x52544327) RenounceOwner { queryId: uint64 }
struct (0x52544328) SetRole { queryId: uint64; account: address; roles: uint8 }
struct (0x52544329) FreezeWallet { queryId: uint64; account: address; frozen: bool }
struct (0x5254432a) SetWalletFrozen { queryId: uint64; frozen: bool; response: address }
struct (0x52544330) MintItem { queryId: uint64; recipient: address; content: cell }
struct (0x52544331) SetRoyalty { queryId: uint64; numerator: uint16; recipient: address }
struct (0x52544332) FreezeRoyalty { queryId: uint64 }
struct (0x693d3950) RequestRoyalty { queryId: uint64 }
struct (0xa8cb00ad) RoyaltyResponse { queryId: uint64; numerator: uint16; denominator: uint16; recipient: address }
struct (0x52544333) InitializeItem { queryId: uint64; owner: address; content: cell; authority: address?; mutable: bool }
struct (0x52544334) EditItem { queryId: uint64; index: uint64; content: cell; freeze: bool }
struct (0x52544335) BurnItem { queryId: uint64 }
struct (0x52544340) ReleaseEscrow { queryId: uint64 }
struct (0x52544341) ReleaseSurplus { queryId: uint64; amount: coins }
struct (0x52544342) CancelUnfunded { queryId: uint64 }
struct (0xd53276db) ReturnExcessesBack { queryId: uint64 }

struct (0x0f8a7ea5) AskToTransfer {
    queryId: uint64
    jettonAmount: coins
    transferRecipient: address
    sendExcessesTo: address?
    customPayload: cell?
    forwardTonAmount: coins
    forwardPayload: RemainingBitsAndRefs
}
struct (0x178d4519) InternalTransferStep {
    queryId: uint64
    jettonAmount: coins
    transferInitiator: address?
    sendExcessesTo: address?
    forwardTonAmount: coins
    forwardPayload: RemainingBitsAndRefs
}
struct (0x7362d09c) TransferNotificationForRecipient {
    queryId: uint64
    jettonAmount: coins
    transferInitiator: address?
    forwardPayload: RemainingBitsAndRefs
}
struct (0x595f07bc) AskToBurn {
    queryId: uint64
    jettonAmount: coins
    sendExcessesTo: address?
    customPayload: cell?
}
struct (0x7bdd97de) BurnNotificationForMinter {
    queryId: uint64
    jettonAmount: coins
    burnInitiator: address
    sendExcessesTo: address?
}
struct (0x2c76b973) RequestWalletAddress {
    queryId: uint64
    ownerAddress: address
    includeOwnerAddress: bool
}
struct (0xd1735400) ResponseWalletAddress {
    queryId: uint64
    jettonWalletAddress: address?
    ownerAddress: Cell<address>?
}
struct (0x5fcc3d14) AskToChangeOwnership {
    queryId: uint64
    newOwnerAddress: address
    sendExcessesTo: address?
    customPayload: cell?
    forwardTonAmount: coins
    forwardPayload: RemainingBitsAndRefs
}
struct (0x05138d91) NotificationForNewOwner {
    queryId: uint64
    oldOwnerAddress: address
    forwardPayload: RemainingBitsAndRefs
}
struct (0x2fcb26a2) RequestStaticData { queryId: uint64 }
struct (0x8b771735) ResponseStaticData {
    queryId: uint64
    itemIndex: uint256
    collectionAddress: address?
}
fun checkForwardPayload(payload: RemainingBitsAndRefs) {
    var p = payload;
    if (p.loadMaybeRef() != null) { p.assertEnd(); }
}
