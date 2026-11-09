tolk 1.5

// Economics are in a separate cell so every supported integer/address fits.
struct CreationEconomics {
    serviceFee: coins
    recipientTopup: coins
    initialSupply: coins
    storageReserve: coins
    minimumLaunchValue: coins
    mintValue: coins
}
struct CreationConfig {
    quoteId: uint256
    creator: address
    treasury: address
    deadline: uint32
    economics: Cell<CreationEconomics>
    identity: Cell<LaunchIdentity>
}
struct LaunchIdentity { launcher: address }
// 0: waiting for launch, 1: waiting for mint receipt, 2: fee emitted,
// 3: launch failed/refunded, 4: fee bounced and can be retried.
struct MasterStorage {
    phase: uint8
    totalSupply: coins
    config: Cell<CreationConfig>
    content: cell
    receipts: Cell<CreationReceipts>
    controls: Cell<TokenControls>
}
struct CreationReceipts {
    launchLt: uint64
    settlementSender: address?
    settlementLt: uint64
    feeLt: uint64
}
struct WalletStorage {
    jettonBalance: coins
    ownerAddress: address
    minterAddress: address
    mintQueryId: uint64
    mintedAmount: coins
    frozen: bool
}
struct NftStorage {
    phase: uint8
    ownerAddress: address
    config: Cell<CreationConfig>
    content: cell
    receipts: Cell<CreationReceipts>
    details: Cell<ItemDetails>
}
struct TokenControls {
    owner: address?
    pendingOwner: address?
    maximum: coins
    issued: coins
    mintable: bool
    burnable: bool
    lifetimeCap: bool
    pausable: bool
    paused: bool
    freezable: bool
    metadataMutable: bool
    roles: map<address, uint8>
    walletCode: cell
    pendingMints: map<uint64, PendingMint>
}
struct PendingMint { wallet: address; amount: coins; requester: address }
struct ItemDetails {
    index: uint64
    collection: address?
    metadataAuthority: address?
    mutable: bool
    burnable: bool
    initialMintQueryId: uint64
}
struct CollectionControls {
    owner: address?
    pendingOwner: address?
    maximum: uint64
    mintable: bool
    paused: bool
    metadataMutable: bool
    royaltyMutable: bool
    royaltyNumerator: uint16
    royaltyRecipient: address
    roles: map<address, uint8>
    itemCode: cell
    pending: map<uint64, PendingItem>
}
struct PendingItem { index: uint64; recipient: address; requester: address; content: cell; mint: bool; mutable: bool }
struct CollectionStorage {
    phase: uint8
    nextIndex: uint64
    config: Cell<CreationConfig>
    content: cell
    receipts: Cell<CreationReceipts>
    controls: Cell<CollectionControls>
}
fun CollectionStorage.load():CollectionStorage{return CollectionStorage.fromCell(contract.getData());}
fun CollectionStorage.save(self){contract.setData(self.toCell());}
fun collectionItem(index:uint64,collection:address,config:Cell<CreationConfig>,code:cell):AutoDeployAddress {
    val receipt:CreationReceipts={launchLt:0,settlementSender:null,settlementLt:0,feeLt:0};
    val details:ItemDetails={index,collection,metadataAuthority:collection,mutable:true,burnable:true,initialMintQueryId:0};
    val data:NftStorage={phase:0,ownerAddress:collection,config,content:beginCell().endCell(),receipts:receipt.toCell(),details:details.toCell()};
    return {workchain:0,stateInit:{code,data:data.toCell()}};
}
fun MasterStorage.load(): MasterStorage { return MasterStorage.fromCell(contract.getData()); }
fun MasterStorage.save(self) { contract.setData(self.toCell()); }
fun WalletStorage.load(): WalletStorage { return WalletStorage.fromCell(contract.getData()); }
fun WalletStorage.save(self) { contract.setData(self.toCell()); }
fun NftStorage.load(): NftStorage { return NftStorage.fromCell(contract.getData()); }
fun NftStorage.save(self) { contract.setData(self.toCell()); }

fun deployedWallet(owner: address, minter: address, code: cell): AutoDeployAddress {
    val data: WalletStorage = {jettonBalance: 0, ownerAddress: owner, minterAddress: minter, mintQueryId: 0, mintedAmount: 0, frozen: false};
    return {workchain: 0, stateInit: {code, data: data.toCell()}};
}
fun walletAddress(owner: address, minter: address, code: cell): address {
    return deployedWallet(owner, minter, code).calculateAddress();
}
