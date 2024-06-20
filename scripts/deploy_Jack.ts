import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { MaxUint256, Overrides, ZeroAddress } from "ethers";
import {ethers, network} from "hardhat";
import { DeploymentHelper, contractCall, ownerContractCall } from "./contracts/helpers";
import * as ProxyAdmin from "./contracts/ProxyAdmin";
import { JackDeployment } from "./JackDeployment";

const ChainLinkPriceFeed: {[name: string]: string} = { sAVAX: "0x2854Ca10a54800e15A2a25cFa52567166434Ff0a", AVAX: "0x0A77230d17318075983913bC2145DB16C7366156"};
const wsAVAXAddress = "0x7aa5c727270C7e1642af898E0EA5b85a094C17a1";

async function main() {
    const [deployer] = await ethers.getSigners();
    const deployment = await deploy(deployer, { gasLimit: 9500000 });
    await initialize(deployer, deployment, { gasLimit: 95000000 });
}

export async function deploy(deployer: HardhatEthersSigner, overrides?: Overrides): Promise<JackDeployment> {
    const admin = await ProxyAdmin.deploy(deployer);
    const deployment = new DeploymentHelper(network.name, "Jack.sAVAX", deployer, overrides);
    
    await deployment.contractDeploy(
        "ChainlinkPriceOracle", "ChainlinkPriceOracle", "ChainlinkPriceOracle", []
    );

    // deploy JacksAVAXVwapOracle
    await deployment.contractDeploy(
        "JacksAVAXVwapOracle", "JacksAVAXVwapOracle", "JacksAVAXVwapOracle",
        [
            ChainLinkPriceFeed['sAVAX'], ChainLinkPriceFeed['AVAX'], deployment.get("ChainlinkPriceOracle"), 
            "0x2b2c81e08f1af8835a78bb2a90ae924ace0ea4be", "0xb139352d7e33b96511a798c0110c79bb5b1fb3be"
        ],
    );
    
    // deploy implementation
    for (const name of ["SyntheticToken", "LeveragedToken", "Market", "RebalancePool"]) {
        await deployment.contractDeploy(name + ".implementation", name + " implementation", name, []);
    }

    // deploy sAVAXTreasury implementation
    await deployment.contractDeploy("sAVAXTreasury.implementation", "sAVAXTreasury implementation", "sAVAXTreasury", [ethers.parseEther("0.5")]);

    // deploy proxy for SyntheticToken, LeveragedToken, sAVAXTreasury and Market
    for (const name of ["SyntheticToken", "LeveragedToken", "Market", "RebalancePool", "sAVAXTreasury"]) {
        await deployment.proxyDeploy(
            `${name}.proxy`,
            `${name} Proxy`,
            deployment.get(`${name}.implementation`),
            admin.Jack,
            "0x"
        );
    }

    // deploy sAVAXGateway
    await deployment.contractDeploy("sAVAXGateway", "sAVAXGateway", "sAVAXGateway", [
        deployment.get("Market.proxy"),
        deployment.get("SyntheticToken.proxy"),
        deployment.get("LeveragedToken.proxy"),
        "0x2b2c81e08f1af8835a78bb2a90ae924ace0ea4be", // sAVAX
        wsAVAXAddress, // wsAVAX
        "0xC4729E56b831d74bBc18797e0e17A295fA77488c", // router
        "0x521B1A464b7E02E90eC4F1Ced225fBf38258DAf0"
    ]);
    
    return deployment.toObject() as JackDeployment;
}

export async function initialize(deployer: HardhatEthersSigner, deployment: JackDeployment, overrides?: Overrides) {
    await aUSDxAVAX(deployer, deployment, overrides);
    await oracleSetup(deployer, deployment, overrides);
    await approvals(deployer, deployment, overrides);

    await treasury(deployer, deployment, overrides);
    await market(deployer, deployment, overrides);
    await rebPool(deployer, deployment, overrides);
    
    await sAVAXGatewaySetup(deployer, deployment, overrides);
}

async function aUSDxAVAX(deployer: HardhatEthersSigner, deployment: JackDeployment, overrides?: Overrides){
    const treasury = await ethers.getContractAt("sAVAXTreasury", deployment.sAVAXTreasury.proxy, deployer);
    const aToken = await ethers.getContractAt("SyntheticToken", deployment.SyntheticToken.proxy, deployer);
    const xToken = await ethers.getContractAt("LeveragedToken", deployment.LeveragedToken.proxy, deployer);
    
    await contractCall( aToken, "SyntheticToken init", "initialize", [await treasury.getAddress(), "aUSD", "aUSD"], overrides);
    await contractCall( xToken, "LeveragedToken init", "initialize", [await treasury.getAddress(), await aToken.getAddress(), "xAVAX", "xAVAX"], overrides);
}

async function oracleSetup(deployer: HardhatEthersSigner, deployment: JackDeployment, overrides?: Overrides) {
    const ChainlinkOracle = await ethers.getContractAt("ChainlinkPriceOracle", deployment.ChainlinkPriceOracle, deployer);
    await ownerContractCall(ChainlinkOracle, "setFeeds", "setFeeds", [
        ["0x2854Ca10a54800e15A2a25cFa52567166434Ff0a", "0x0A77230d17318075983913bC2145DB16C7366156"], 
        ["0x2854Ca10a54800e15A2a25cFa52567166434Ff0a", "0x0A77230d17318075983913bC2145DB16C7366156"]
    ]);
}

async function approvals(deployer: HardhatEthersSigner, deployment: JackDeployment, overrides?: Overrides) {
    const rebalancePool = await ethers.getContractAt("RebalancePool", deployment.RebalancePool.proxy, deployer);
    const market = await ethers.getContractAt("Market", deployment.Market.proxy, deployer);
    const aToken = await ethers.getContractAt("SyntheticToken", deployment.SyntheticToken.proxy, deployer);
    const wsAVAX = await ethers.getContractAt("SyntheticToken", wsAVAXAddress, deployer);

    await contractCall( aToken, "SyntheticToken approve rebPool", "approve", [await rebalancePool.getAddress(), MaxUint256], overrides);
    await contractCall(wsAVAX, "Approve for Market", "approve", [await market.getAddress(), MaxUint256], overrides);
}

async function treasury(deployer: HardhatEthersSigner, deployment: JackDeployment, overrides?: Overrides) {
    const treasury = await ethers.getContractAt("sAVAXTreasury", deployment.sAVAXTreasury.proxy, deployer);
    const market = await ethers.getContractAt("Market", deployment.Market.proxy, deployer);
    const rebalancePool = await ethers.getContractAt("RebalancePool", deployment.RebalancePool.proxy, deployer);
    
    const oracle = await ethers.getContractAt("JacksAVAXVwapOracle", deployment.JacksAVAXVwapOracle, deployer);
    const aToken = await ethers.getContractAt("SyntheticToken", deployment.SyntheticToken.proxy, deployer);
    const xToken = await ethers.getContractAt("LeveragedToken", deployment.LeveragedToken.proxy, deployer);

    // Setup sAVAXTreasury
    if ((await treasury.market()) !== await market.getAddress()) {
        await contractCall( treasury, "sAVAXTreasury initialize", "initialize",
            [   await market.getAddress(), wsAVAXAddress, await aToken.getAddress(), await xToken.getAddress(), await oracle.getAddress(), 
                ethers.parseEther("0"),  ethers.parseEther("20"), ZeroAddress
            ],
            overrides
        );
    }
    // Init v2
    if ((await treasury.emaLeverageRatio()).lastTime === 0n) { await contractCall(treasury, "sAVAXTreasury initializeV2", "initializeV2", [15 * 60], overrides);}
    
    await ownerContractCall( treasury, "sAVAXTreasury updateSettleWhitelist", "updateSettleWhitelist", [deployer.address, true], overrides);
    
    // update oracle, protocol and settle
    if((await treasury.priceOracle()) !== deployment.JacksAVAXVwapOracle) {
        await ownerContractCall(treasury, "sAVAXTreasury updatePriceOracle", "updatePriceOracle", [deployment.JacksAVAXVwapOracle], overrides);
    }

    if(await treasury.lastPermissionedPrice() === 0n) {
        await ownerContractCall( treasury, "sAVAXTreasury initialize Price", "initializePrice", [], overrides );
    }

    if ((await treasury.rebalancePool()) !== await rebalancePool.getAddress()) {
        await ownerContractCall(treasury, "sAVAXTreasury updateRebalancePool", "updateRebalancePool", [await rebalancePool.getAddress()], overrides);
    }

    if ((await treasury.harvestBountyRatio()) != 10000000000000000) {
        await ownerContractCall(treasury, "sAVAXTreasury update ratio", "updateRewardRatio", [BigInt("990000000000000000"), 10000000000000000n], overrides);
    }
}

async function market(deployer: HardhatEthersSigner, deployment: JackDeployment, overrides?: Overrides) {
    const treasury = await ethers.getContractAt("sAVAXTreasury", deployment.sAVAXTreasury.proxy, deployer);
    const market = await ethers.getContractAt("Market", deployment.Market.proxy, deployer);
    const sAVAXGateway = await ethers.getContractAt("sAVAXGateway", deployment.sAVAXGateway, deployer );
    const wsAVAX = await ethers.getContractAt("SyntheticToken", wsAVAXAddress, deployer);

    try {
       console.log( await contractCall( market, "Market initialize", "initialize", [await treasury.getAddress(), deployer.address, await sAVAXGateway.getAddress()], overrides));
    } catch (error) {
        console.error("Failed transaction at Market update platform:", error);
    }

    await ownerContractCall( market, "Market update market config", "updateMarketConfig",[ ethers.parseEther("1.6"), ethers.parseEther("1.47"), ethers.parseEther("1.45"), ethers.parseEther("1")], overrides);
    await ownerContractCall( market, "Market update Redeem Fee Ratio", "updateRedeemFeeRatio", [2500000000000000n, -2500000000000000n, true], overrides )
    await ownerContractCall( market, "Market update Redeem Fee Ratio", "updateRedeemFeeRatio", [15000000000000000n, 70000000000000000n, false], overrides)
    await ownerContractCall( market, "Market update pauseMintWhenUnderCollateral", "pauseaTokenMintInSystemStabilityMode", [true], overrides)
    await ownerContractCall( market, "Market update mint Fee Ratio", "updateMintFeeRatio", [5000000000000000n, 0n, true], overrides)
    await ownerContractCall( market, "Market update mint Fee Ratio", "updateMintFeeRatio", [5000000000000000n, -5000000000000000n, false], overrides)
    await contractCall(market, "Market mint", "mint", [ethers.parseEther("3"), deployer.address, 0, 0], overrides);
}

async function rebPool(deployer: HardhatEthersSigner, deployment: JackDeployment, overrides?: Overrides) {
    const treasury = await ethers.getContractAt("sAVAXTreasury", deployment.sAVAXTreasury.proxy, deployer);
    const market = await ethers.getContractAt("Market", deployment.Market.proxy, deployer);
    const rebalancePool = await ethers.getContractAt("RebalancePool", deployment.RebalancePool.proxy, deployer);
    

    //Initialize RebalancePool APool
    if ((await rebalancePool.treasury()) === ZeroAddress) {
        await contractCall( rebalancePool, "RebalancePool initialize", "initialize", [await treasury.getAddress(), await market.getAddress()], overrides);
    }
    
    if ((await rebalancePool.rewardManager(wsAVAXAddress)) === ZeroAddress) {
        await ownerContractCall( rebalancePool, "RebalancePool add LstAVAX as reward", "addReward", [wsAVAXAddress, deployment.sAVAXTreasury.proxy, 86400 * 7], overrides);
    }
    
    if ((await rebalancePool.rewardManager(wsAVAXAddress)) !== deployment.sAVAXTreasury.proxy) {
        await ownerContractCall( rebalancePool, "RebalancePool updateReward for sAVAX", "updateReward", [wsAVAXAddress, deployment.sAVAXTreasury.proxy, 86400 * 7], overrides);
    }

    await contractCall( rebalancePool, "RebalancePool updateUnlockDuration", "updateUnlockDuration", [0], overrides);

    await contractCall( rebalancePool, "RebalancePool updateLiquidatableCollateralRatio", "updateLiquidatableCollateralRatio", [ethers.parseEther("1.6")], overrides);

    await ownerContractCall( rebalancePool, "Update Liquidator", "updateLiquidator", [deployer.address], overrides);
}

async function sAVAXGatewaySetup(deployer: HardhatEthersSigner, deployment: JackDeployment, overrides?: Overrides) {
    const sAVAXGateway = await ethers.getContractAt("sAVAXGateway", deployment.sAVAXGateway, deployer);
    await ownerContractCall(sAVAXGateway, "addAcceptedToken", "addAcceptedToken", ["0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E"]);
    await ownerContractCall(sAVAXGateway, "addAcceptedToken", "addAcceptedToken", ["0x9702230A8Ea53601f5cD2dc00fDBc13d4dF4A8c7"]); 
    await ownerContractCall(sAVAXGateway, "addAcceptedToken", "addAcceptedToken", ["0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7"]);
    await ownerContractCall(sAVAXGateway, "addAcceptedToken", "addAcceptedToken", ["0x2f14682dCc96bD203deaA43F556C3A1E1AeA7496"]);

}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});