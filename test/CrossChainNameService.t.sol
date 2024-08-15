// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";

// 在作业中，您需要从 @chainlink/local  包中导入  CCIPLocalSimulator
import {CCIPLocalSimulator} from "@chainlink/local/src/ccip/CCIPLocalSimulator.sol";

import {WETH9} from "@chainlink/local/src/shared/WETH9.sol";
import {LinkToken} from "@chainlink/local/src/shared/LinkToken.sol";
import {BurnMintERC677Helper} from "@chainlink/local/src/ccip/BurnMintERC677Helper.sol";
import {MockCCIPRouter} from "@chainlink/contracts-ccip/src/v0.8/ccip/test/mocks/MockRouter.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";

import {CrossChainNameServiceLookup} from "../contracts/CrossChainNameServiceLookup.sol";
import {CrossChainNameServiceReceiver} from "../contracts/CrossChainNameServiceReceiver.sol";
import {CrossChainNameServiceRegister} from "../contracts/CrossChainNameServiceRegister.sol";

import {EncodeExtraArgs} from "./utils/EncodeExtraArgs.sol";

contract CrossChainNameServiceTest is Test {
    CCIPLocalSimulator public ccipLocalSimulator;

    uint256 ethSepoliaFork;
    uint256 arbSepoliaFork;
    uint256 opSepoliaFork;

    address alice;

    // register
    CrossChainNameServiceLookup public ethSepoliaLookup;
    CrossChainNameServiceRegister public ethSepoliaRegister;

    // receiver-1
    CrossChainNameServiceLookup public arbSepoliaLookup;
    CrossChainNameServiceReceiver public arbSepoliaReceiver;

    // receiver-2
    CrossChainNameServiceLookup public opSepoliaLookup;
    CrossChainNameServiceReceiver public opSepoliaReceiver;

    EncodeExtraArgs public encodeExtraArgs;

    uint64 public chainSelector;
    IRouterClient public sourceRouter;
    IRouterClient public destinationRouter;
    WETH9 public wrappedNative;
    LinkToken public linkToken;
    BurnMintERC677Helper public ccipBnM;
    BurnMintERC677Helper public ccipLnM;

    function setUp() public {
        alice = makeAddr("alice");

        string memory ETHEREUM_SEPOLIA_RPC_URL = vm.envString(
            "ETHEREUM_SEPOLIA_RPC_URL"
        );
        string memory ARBITRUM_SEPOLIA_RPC_URL = vm.envString(
            "ARBITRUM_SEPOLIA_RPC_URL"
        );
        string memory OPTIMISM_SEPOLIA_RPC_URL = vm.envString(
            "OPTIMISM_SEPOLIA_RPC_URL"
        );
        ethSepoliaFork = vm.createSelectFork(ETHEREUM_SEPOLIA_RPC_URL);
        arbSepoliaFork = vm.createFork(ARBITRUM_SEPOLIA_RPC_URL);
        opSepoliaFork = vm.createFork(ARBITRUM_SEPOLIA_RPC_URL);

        ccipLocalSimulator = new CCIPLocalSimulator();

        (
            chainSelector,
            sourceRouter,
            destinationRouter,
            wrappedNative,
            linkToken,
            ccipBnM,
            ccipLnM
        ) = ccipLocalSimulator.configuration();

        console.log("chainSelector:");
        console.log(chainSelector);
        console.log("sourceRouter:");
        console.log(address(sourceRouter));
        console.log("destinationRouter:");
        console.log(address(destinationRouter));
        console.log("wrappedNative:");
        console.log(address(wrappedNative));
        console.log("linkToken:");
        console.log(address(linkToken));

        vm.makePersistent(address(ccipLocalSimulator));

        // source: eth sepolia
        // destination 1: arb sepolia
        // destination 2: op sepolia

        // 步骤 1) 在Ethereum Sepolia网络中部署合约
        assertEq(vm.activeFork(), ethSepoliaFork);

        // 目前我们处于Ethereum Sepolia的分叉网络中
        // assertEq(
        //     ethSepoliaNetworkDetails.chainSelector,
        //     16015286601757825753,
        //     "Sanity check: Ethereum Sepolia chain selector should be 16015286601757825753"
        // );

        vm.startPrank(alice);

        ethSepoliaLookup = new CrossChainNameServiceLookup();
        ethSepoliaRegister = new CrossChainNameServiceRegister(
            address(sourceRouter),
            address(ethSepoliaLookup)
        );

        ccipLocalSimulator.requestLinkFromFaucet(
            address(ethSepoliaRegister),
            3 ether
        );

        // 步骤 2) 在Arbitrum Sepolia网络中部署合约
        vm.selectFork(arbSepoliaFork);
        assertEq(vm.activeFork(), arbSepoliaFork);

        arbSepoliaLookup = new CrossChainNameServiceLookup();
        arbSepoliaReceiver = new CrossChainNameServiceReceiver(
            address(destinationRouter),
            address(arbSepoliaLookup),
            chainSelector
        );

        // arbSepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(
        //     block.chainid
        // ); // 目前我们处于Arbitrum Sepolia的分叉网络中
        // assertEq(
        //     arbSepoliaNetworkDetails.chainSelector,
        //     3478487238524512106,
        //     "Sanity check: Arbitrum Sepolia chain selector should be 421614"
        // );

        // 步骤 3) 在Optimism Sepolia网络中部署合约
        vm.selectFork(opSepoliaFork);
        assertEq(vm.activeFork(), opSepoliaFork);

        opSepoliaLookup = new CrossChainNameServiceLookup();
        opSepoliaReceiver = new CrossChainNameServiceReceiver(
            address(destinationRouter),
            address(opSepoliaLookup),
            chainSelector
        );
    }

    // YOUR TEST GOES HERE...
    function testRegisterAndCrossLookup() public {
        vm.startPrank(alice);
        // 步骤 4) 在Ethereum Sepolia网络中, 调用enableChain方法
        vm.selectFork(ethSepoliaFork);
        assertEq(vm.activeFork(), ethSepoliaFork);

        encodeExtraArgs = new EncodeExtraArgs();

        uint256 gasLimit = 200_000;
        bytes memory extraArgs = encodeExtraArgs.encode(gasLimit);
        assertEq(
            extraArgs,
            hex"97a657c90000000000000000000000000000000000000000000000000000000000030d40"
        ); // 该值来源于 https://cll-devrel.gitbook.io/ccip-masterclass-3/ccip-masterclass/exercise-xnft#step-3-on-ethereum-sepolia-call-enablechain-function

        ethSepoliaRegister.enableChain(
            chainSelector,
            address(arbSepoliaReceiver),
            gasLimit
        );

        // 步骤 5) 在Ethereum Sepolia网络中, 调用register方法
        ethSepoliaRegister.register("alice.ccns");

        // 步骤 6) 在Arbitrum Sepolia网络中, 调用lookup方法
        vm.selectFork(arbSepoliaFork);
        assertEq(vm.activeFork(), arbSepoliaFork);

        address ns = arbSepoliaLookup.lookup("alice.ccns");
        console.log("ns addr in arbSepolia:", ns);

        assertEq(ns, alice);
    }
}
